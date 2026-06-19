import 'dart:async';
import 'dart:io';

import '../engines/stt/vosk_streaming_controller.dart';
import '../engines/stt/whisper_streaming_transcriber.dart';
import '../engines/translation/translation_engine.dart';
import '../engines/tts/tts_engine.dart';
import '../repositories/conversation_repository.dart';
import '../services/filler_cleaner.dart';
import '../services/title_generator.dart';

/// Konferans Modu'nun **streaming pipeline'ı** (#1, 2026-06-05).
///
/// [ConversationSessionManager]'ın dosya-bazlı (sample→WAV→`transcribeFile`)
/// pipeline'ının yerine geçer: Vosk `SpeechService` doğrudan **metin akışı**
/// ürettiği için (kelime kelime canlı), 5sn'lik chunk + WAV turu + backpressure
/// düşürme ortadan kalkar → konuşma geride kalmaz ("Gemini hızı", Mehmet #1).
///
/// Manager'ı bypass eder; diğer modlar (Bas Konuş) Manager'ı kullanmaya devam
/// eder — değişiklik Konferans'a izoledir.
///
/// Akış:
///   - [StreamingTranscriber.partials] → [livePartial] (yalnız gösterim, çeviri
///     tetiklemez — partial'lar çok hızlı değişir, MLKit'i boğmaz).
///   - [StreamingTranscriber.finals] → filler temizle → MLKit çevir → DB'ye yaz
///     (`sourceText`=transkript → crunch ile uyumlu) → [translations]'a yay →
///     (ttsEnabled ise) seslendir. Finaller sıralı işlenir.
///
/// Crunch değişmeden çalışır: `repository.appendMessage` ile yazılan `sourceText`
/// transkriptlerini `runConferenceCrunch` DB'den okur.
class ConferenceStreamingSession {
  ConferenceStreamingSession({
    required this.transcriber,
    required this.repository,
    required this.translation,
    required this.tts,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.ttsEnabled,
    this.fillerCleaner = const FillerCleaner(),
    this.fillerLevel = FillerLevel.conservative,
    this.titleGenerator = const TimestampFallbackGenerator(),
  });

  final StreamingTranscriber transcriber;
  final ConversationRepository repository;
  final TranslationEngine translation;
  final TtsEngine tts;
  final String sourceLanguage;
  final String targetLanguage;
  final bool ttsEnabled;
  final FillerCleaner fillerCleaner;
  final FillerLevel fillerLevel;
  final TitleGenerator titleGenerator;

  final StreamController<String> _livePartial =
      StreamController<String>.broadcast();
  final StreamController<String> _translations =
      StreamController<String>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();

  /// Canlı kısmi transkript (gösterim — soluk satır). Final gelince '' yayılır.
  Stream<String> get livePartial => _livePartial.stream;

  /// Yeni çevrilmiş cümle (ekranda alt alta gösterilir).
  Stream<String> get translations => _translations.stream;

  /// İşleme hatası (UI yutabilir; log/banner için).
  Stream<String> get errors => _errors.stream;

  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _finalSub;

  bool _prepared = false;
  bool get isPrepared => _prepared;

  bool _stopping = false;

  /// En son işlenen final metni. Vosk `SpeechService` (EventChannel) bazen aynı
  /// finalize olmuş segmenti **art arda birden çok kez** yayıyor → aynı çeviri
  /// tekrarlanıyordu (cihaz testi 2026-06-05: "aynı çeviriyi 4 kere tekrarlıyor").
  /// Ardışık aynı finali atlayarak tekrarı engelleriz (start()'ta sıfırlanır;
  /// non-ardışık tekrar — kullanıcı aynı cümleyi sonra tekrar söylerse — geçer).
  String? _lastFinal;

  int? _activeSessionId;
  int? get activeSessionId => _activeSessionId;

  /// Finalleri sıralı işlemek için kuyruk (çeviri+TTS sırası korunur).
  Future<void> _queue = Future<void>.value();

  /// Transkript modeli warmup'a hazır mı? (indirme kapısı kararı)
  /// - Android: bu dilin **Vosk** modeli inmiş mi.
  /// - iOS: Vosk yok → **Whisper small** inmiş mi ([WhisperStreamingTranscriber]).
  static Future<bool> isModelReady(String language) => Platform.isIOS
      ? WhisperStreamingTranscriber.whisperReady()
      : VoskStreamingController.isModelReady(language);

  /// Ağır hazırlık (ısınma ekranı çağırır): model + çeviri + TTS yükle.
  /// Idempotent.
  Future<void> prepare() async {
    if (_prepared) return;
    await transcriber.load(sourceLanguage);
    await Future.wait([
      translation.ensureModelLoaded(sourceLanguage, targetLanguage),
      tts.initialize(),
    ]);
    _prepared = true;
  }

  /// `start()` devam ederken (prepare/createSession await'leri sırasında)
  /// ikinci çağrıyı engeller — `_activeSessionId` ancak await'lerden sonra
  /// atandığından tek başına yeterli guard değil.
  bool _starting = false;

  /// Oturumu başlat: DB session aç + akışa abone ol + dinlemeye başla.
  Future<void> start() async {
    if (_starting || _activeSessionId != null) {
      throw StateError('Oturum zaten başladı.');
    }
    _starting = true;
    try {
      await _start();
    } finally {
      _starting = false;
    }
  }

  Future<void> _start() async {
    _stopping = false;
    _lastFinal = null;
    await prepare();

    final session = await repository.createSession(
      mode: SessionMode.lecture,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      quality: SessionQuality.full,
    );
    _activeSessionId = session.id;

    _partialSub = transcriber.partials.listen((p) {
      if (_stopping || _livePartial.isClosed) return;
      _livePartial.add(p);
    });
    _finalSub = transcriber.finals.listen(_onFinal);

    await transcriber.start();
  }

  void _onFinal(String text) {
    if (_stopping) return;
    final raw = text.trim();
    if (raw.isEmpty) return;
    // Ardışık aynı final = Vosk EventChannel tekrarı → atla (tekrar bug fix).
    if (raw == _lastFinal) return;
    _lastFinal = raw;
    _queue = _queue.then((_) => _processFinal(raw));
  }

  Future<void> _processFinal(String raw) async {
    final sessionId = _activeSessionId;
    if (sessionId == null || _stopping) return;
    try {
      final clean = fillerCleaner.clean(
        raw,
        language: sourceLanguage,
        level: fillerLevel,
      );
      if (clean.trim().isEmpty) return;

      final translated = await translation.translate(
        clean,
        sourceLanguage,
        targetLanguage,
      );
      if (_stopping) return;

      // Crunch transkripte (sourceText) dayanır → her zaman yaz.
      await repository.appendMessage(
        sessionId: sessionId,
        speakerLanguage: sourceLanguage,
        sourceText: clean,
        translatedText: translated,
      );

      if (!_translations.isClosed && translated.trim().isNotEmpty) {
        _translations.add(translated.trim());
      }
      // Final işlendi → canlı partial satırını temizle.
      if (!_livePartial.isClosed) _livePartial.add('');

      if (ttsEnabled && !_stopping && translated.trim().isNotEmpty) {
        await tts.speak(translated, targetLanguage);
      }
    } catch (e) {
      if (!_errors.isClosed) _errors.add(e.toString());
    }
  }

  /// Oturumu kapat: dinlemeyi durdur, bekleyen işi bitir, başlık üret, session'ı
  /// flush et. Biten session id'sini döndürür (crunch için).
  Future<int?> end() async {
    if (_activeSessionId == null) return null;
    _stopping = true;

    await _partialSub?.cancel();
    await _finalSub?.cancel();
    _partialSub = null;
    _finalSub = null;
    await transcriber.stop();
    await tts.stop();

    // Sırada bekleyen finalleri bekle (kısa — metin çeviri).
    try {
      await _queue;
    } catch (_) {
      /* hata zaten errors'a düştü */
    }

    final sessionId = _activeSessionId;
    int? kept = sessionId;
    if (sessionId != null) {
      if (await repository.deleteSessionIfEmpty(sessionId)) {
        kept = null; // boş transkript → kaydetme (Mehmet 2026-06-11)
      } else {
        await _writeTitle(sessionId);
        await repository.endSession(sessionId);
      }
    }
    _activeSessionId = null;
    return kept;
  }

  Future<void> _writeTitle(int sessionId) async {
    try {
      final session = await repository.getSession(sessionId);
      final messages = await repository.listMessagesForSession(sessionId);
      final title = await titleGenerator.generate(
        mode: SessionMode.lecture,
        messages: messages,
        startedAt: session?.startedAt ?? DateTime.now(),
      );
      await repository.setTitle(sessionId, title);
    } catch (_) {
      // Başlık üretimi oturum kapanışını bozmasın.
    }
  }

  Future<void> dispose() async {
    await end();
    await transcriber.dispose();
    if (!_livePartial.isClosed) await _livePartial.close();
    if (!_translations.isClosed) await _translations.close();
    if (!_errors.isClosed) await _errors.close();
  }
}
