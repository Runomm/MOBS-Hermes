import 'dart:async';

import '../engines/stt/dual_vosk_streaming_controller.dart';
import '../engines/translation/translation_engine.dart';
import '../engines/tts/tts_engine.dart';
import '../repositories/conversation_repository.dart';
import '../services/filler_cleaner.dart';
import '../services/title_generator.dart';

/// Chat'e düşen bir SmallTalk mesajı (hands-free).
class SmallTalkMessage {
  const SmallTalkMessage({
    required this.isMaster,
    required this.transcript,
    required this.translation,
    required this.translationLang,
  });

  /// Konuşan master mı (sağ baloncuk) yoksa local mi (sol)?
  final bool isMaster;

  /// Konuşanın kendi dilindeki transkript.
  final String transcript;

  /// Karşı taraf için çeviri.
  final String translation;

  /// [translation]'ın dili (master mesajı → local dili; local mesajı → master
  /// dili). Play/TTS bunu kullanır.
  final String translationLang;
}

/// Hands-free SmallTalk **streaming orkestratörü** (S3, 2026-06-05).
///
/// Konferans streaming'inin çift yönlü hâli. [DualTranscriber] tek mic'ten iki
/// dilde transkript + akustik güven verir; orkestratör **konuşmacıyı güven
/// skoruna göre** belirler (doğru dildeki tanıyıcı daha yüksek skorlar; eşitlik/
/// belirsizlikte **master önceliklidir** — Mehmet kararı). Sonra filler temizler,
/// MLKit çevirir, DB'ye yazar (`mode=voiceTranslator` → SmallTalk klasörü,
/// crunch uyumlu), [messages]'a yayar.
///
/// **TTS / ses kanal yönlendirme:** narration aktif + master kulaklığı → local'in
/// çevirisi master'a otomatik seslendirilir; master'ın çevirisi yalnız **play**
/// ile. local play → narration session boyunca kapanır. **Seçici kulaklık↔hoparlör
/// yönlendirme DEFERRED** (Mehmet) — bu sürümde TTS varsayılan çıkışı kullanır.
class SmallTalkStreamingSession {
  SmallTalkStreamingSession({
    required this.transcriber,
    required this.repository,
    required this.translation,
    required this.tts,
    required this.masterLang,
    required this.localLang,
    required bool narrationEnabled,
    this.quality = SessionQuality.full,
    this.fillerCleaner = const FillerCleaner(),
    this.fillerLevel = FillerLevel.conservative,
    this.titleGenerator = const TimestampFallbackGenerator(),
  }) : _narrationActive = narrationEnabled;

  final DualTranscriber transcriber;
  final ConversationRepository repository;
  final TranslationEngine translation;
  final TtsEngine tts;

  /// Master = telefon sahibi (kaynak dil, sağ baloncuk).
  final String masterLang;

  /// Local = karşı kişi (hedef dil, sol baloncuk).
  final String localLang;

  /// Oturum kalite katmanı (fast/full/full+) — DB'ye kaydedilir (bilgi amaçlı).
  final SessionQuality quality;

  final FillerCleaner fillerCleaner;
  final FillerLevel fillerLevel;
  final TitleGenerator titleGenerator;

  /// Local→master otomatik seslendirme aktif mi (local play ile kapanır).
  bool _narrationActive;
  bool get narrationActive => _narrationActive;

  final _livePartial = StreamController<String>.broadcast();
  final _messages = StreamController<SmallTalkMessage>.broadcast();
  final _errors = StreamController<String>.broadcast();

  Stream<String> get livePartial => _livePartial.stream;
  Stream<SmallTalkMessage> get messages => _messages.stream;
  Stream<String> get errors => _errors.stream;

  StreamSubscription<String>? _partialSub;
  StreamSubscription<DualTranscript>? _finalSub;

  bool _prepared = false;
  bool get isPrepared => _prepared;
  bool _stopping = false;
  String? _lastText;

  /// Son yönlendirilen konuşmacı (histerezis için). Fast (Vosk) modda iki dilin
  /// güven skoru birbirine yakınsa son konuşanda kalır → çırpınmayı azaltır.
  /// Full (Whisper) modda skorlar 1.0/0 olduğu için bu devreye girmez.
  bool? _lastSpeakerMaster;

  /// İki güven skoru bu farktan az ise belirsiz say → son konuşanda kal.
  static const double _hysteresisMargin = 0.15;

  int? _activeSessionId;
  int? get activeSessionId => _activeSessionId;

  Future<void> _queue = Future<void>.value();

  Future<void> prepare() async {
    if (_prepared) return;
    await transcriber.load();
    await Future.wait([
      translation.ensureModelLoaded(masterLang, localLang),
      translation.ensureModelLoaded(localLang, masterLang),
      tts.initialize(),
    ]);
    _prepared = true;
  }

  /// `start()` devam ederken (prepare/createSession await'leri sırasında)
  /// ikinci çağrıyı engeller — `_activeSessionId` ancak await'lerden sonra
  /// atandığından tek başına yeterli guard değil.
  bool _starting = false;

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
    _lastText = null;
    _lastSpeakerMaster = null;
    await prepare();

    final session = await repository.createSession(
      mode: SessionMode.voiceTranslator,
      sourceLanguage: masterLang,
      targetLanguage: localLang,
      quality: quality,
    );
    _activeSessionId = session.id;

    _partialSub = transcriber.partials.listen((p) {
      if (!_stopping && !_livePartial.isClosed) _livePartial.add(p);
    });
    _finalSub = transcriber.finals.listen(_onFinal);
    await transcriber.start();
  }

  /// Güven skoruna göre konuşmacıyı seç. `(isMaster, text)` veya null (boş).
  /// Eşitlik/belirsizlik → master (öncelik). (Test edilebilir saf mantık.)
  static (bool, String)? route(DualTranscript d) {
    final m = d.masterText.trim();
    final l = d.localText.trim();
    if (m.isEmpty && l.isEmpty) return null;
    if (l.isEmpty) return (true, m);
    if (m.isEmpty) return (false, l);
    return d.masterConf >= d.localConf ? (true, m) : (false, l);
  }

  /// [route] üstüne histerezis: iki metin de doluysa ve güven farkı küçükse
  /// (belirsiz) son konuşanda kal (fast/Vosk çırpınma azaltma).
  (bool, String)? _routeWithHysteresis(DualTranscript d) {
    final base = route(d);
    if (base == null) return null;
    final m = d.masterText.trim();
    final l = d.localText.trim();
    var isMaster = base.$1;
    if (m.isNotEmpty &&
        l.isNotEmpty &&
        _lastSpeakerMaster != null &&
        (d.masterConf - d.localConf).abs() < _hysteresisMargin) {
      isMaster = _lastSpeakerMaster!;
    }
    _lastSpeakerMaster = isMaster;
    return (isMaster, isMaster ? m : l);
  }

  void _onFinal(DualTranscript d) {
    if (_stopping) return;
    final picked = _routeWithHysteresis(d);
    if (picked == null) return;
    final (isMaster, text) = picked;
    if (text == _lastText) return; // ardışık tekrar koruması (Vosk)
    _lastText = text;
    _queue = _queue.then((_) => _process(isMaster, text));
  }

  Future<void> _process(bool isMaster, String raw) async {
    final sessionId = _activeSessionId;
    if (sessionId == null || _stopping) return;
    final fromLang = isMaster ? masterLang : localLang;
    final toLang = isMaster ? localLang : masterLang;
    try {
      final clean = fillerCleaner.clean(
        raw,
        language: fromLang,
        level: fillerLevel,
      );
      if (clean.trim().isEmpty) return;

      final translated = await translation.translate(clean, fromLang, toLang);
      if (_stopping) return;

      await repository.appendMessage(
        sessionId: sessionId,
        speakerLanguage: fromLang,
        sourceText: clean,
        translatedText: translated,
      );

      final msg = SmallTalkMessage(
        isMaster: isMaster,
        transcript: clean,
        translation: translated,
        translationLang: toLang,
      );
      if (!_messages.isClosed) _messages.add(msg);
      if (!_livePartial.isClosed) _livePartial.add('');

      // Local→master otomatik seslendirme (narration aktifse). Master'ın
      // çevirisi yalnız play ile (otomatik değil).
      if (!isMaster &&
          _narrationActive &&
          !_stopping &&
          translated.trim().isNotEmpty) {
        await tts.speak(translated, toLang);
      }
    } catch (e) {
      if (!_errors.isClosed) _errors.add(e.toString());
    }
  }

  /// Bir mesajın çevirisini seslendir (play butonu). Local mesajının play'i
  /// otomatik narration'ı session boyunca kapatır (Mehmet kararı).
  Future<void> playMessage(SmallTalkMessage msg) async {
    if (!msg.isMaster) _narrationActive = false;
    if (msg.translation.trim().isEmpty) return;
    await tts.speak(msg.translation, msg.translationLang);
  }

  Future<int?> end() async {
    if (_activeSessionId == null) return null;
    _stopping = true;
    await _partialSub?.cancel();
    await _finalSub?.cancel();
    _partialSub = null;
    _finalSub = null;
    await transcriber.stop();
    await tts.stop();
    try {
      await _queue;
    } catch (_) {
      /* errors'a düştü */
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
        mode: SessionMode.voiceTranslator,
        messages: messages,
        startedAt: session?.startedAt ?? DateTime.now(),
      );
      await repository.setTitle(sessionId, title);
    } catch (_) {
      /* oturum kapanışını bozma */
    }
  }

  Future<void> dispose() async {
    await end();
    await transcriber.dispose();
    if (!_livePartial.isClosed) await _livePartial.close();
    if (!_messages.isClosed) await _messages.close();
    if (!_errors.isClosed) await _errors.close();
  }
}
