import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../audio/wav_writer.dart';
import '../database/app_database.dart';
import '../engines/language_id/language_detector.dart';
import '../engines/stt/stt_engine.dart';
import '../engines/translation/translation_engine.dart';
import '../engines/tts/tts_engine.dart';
import '../repositories/conversation_repository.dart';
import '../services/filler_cleaner.dart';
import '../services/vad_controller.dart';

/// Konuşma Modu'nun çekirdek state machine'i + pipeline.
///
/// VAD → STT → FillerCleaner → LanguageID → Translate → TTS → Repository
/// zincirini tek noktadan yönetir. UI bu sınıfın `stateStream` ve
/// `eventStream`'ini dinler, butonlardan `start/pause/resume/end` çağırır.
///
/// Bkz: HERMES_KONUSMA_MODU_TASARIM.md (Bölüm 3.1, 4, 5).
class ConversationSessionManager {
  ConversationSessionManager({
    required this.vad,
    required this.stt,
    required this.translation,
    required this.tts,
    required this.languageDetector,
    required this.repository,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.mode,
    FillerCleaner fillerCleaner = const FillerCleaner(),
    FillerLevel fillerLevel = FillerLevel.conservative,
    WavWriter wavWriter = const WavWriter(),
    double languageMinConfidence = 0.6,
    Future<Directory> Function() temporaryDirectory =
        getTemporaryDirectory,
  })  : _fillerCleaner = fillerCleaner,
        _fillerLevel = fillerLevel,
        _wavWriter = wavWriter,
        _languageMinConfidence = languageMinConfidence,
        _temporaryDirectory = temporaryDirectory;

  // --- Dependencies ---
  final VadController vad;
  final SttEngine stt;
  final TranslationEngine translation;
  final TtsEngine tts;
  final LanguageDetector languageDetector;
  final ConversationRepository repository;
  final String sourceLanguage;
  final String targetLanguage;
  final SessionMode mode;

  final FillerCleaner _fillerCleaner;
  final FillerLevel _fillerLevel;
  final WavWriter _wavWriter;
  final double _languageMinConfidence;
  final Future<Directory> Function() _temporaryDirectory;

  // --- State ---
  ConversationState _state = ConversationState.idle;
  ConversationState get state => _state;

  final _stateController =
      StreamController<ConversationState>.broadcast();
  Stream<ConversationState> get stateStream => _stateController.stream;

  final _eventController =
      StreamController<ConversationEvent>.broadcast();
  Stream<ConversationEvent> get eventStream => _eventController.stream;

  int? _activeSessionId;
  int? get activeSessionId => _activeSessionId;

  StreamSubscription<VadUtteranceEvent>? _vadSub;

  /// VAD utterance'larının sıralı işlenmesi için kuyruk —
  /// Whisper bir utterance işlerken yeni utterance gelirse hemen başlamasın,
  /// sırasını beklesin (tasarım Bölüm 5: "Async queue, sırayla işle").
  Future<void> _pipelineQueue = Future<void>.value();

  /// TTS aktif mi? `_onVadEvent` feedback guard'ı için. `tts.isSpeaking`
  /// native plugin'e bağımlı; biz speak çağrısının await'ini sararak
  /// kendi flag'ımızı tutarız (daha deterministik).
  bool _isTtsSpeaking = false;

  // --- Public API ---

  /// Oturumu başlat: repository'de session aç, motorları initialize et,
  /// VAD'i dinlemeye başlat.
  Future<void> start() async {
    if (_state != ConversationState.idle) {
      throw StateError('start() yalnızca idle state\'inden çağrılabilir '
          '(şu an: $_state)');
    }

    await Future.wait([
      stt.initialize(),
      tts.initialize(),
      languageDetector.initialize(),
      translation.ensureModelLoaded(sourceLanguage, targetLanguage),
      translation.ensureModelLoaded(targetLanguage, sourceLanguage),
    ]);

    final session = await repository.createSession(
      mode: mode,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    _activeSessionId = session.id;

    _subscribeToVad();
    await vad.start();
    _setState(ConversationState.listening);
  }

  /// Mikrofonu duraklat. Aktif pipeline işi (transcribe vs) tamamlanır,
  /// yeni utterance yakalanmaz. State → paused.
  Future<void> pause() async {
    if (_state == ConversationState.idle ||
        _state == ConversationState.ending ||
        _state == ConversationState.paused) {
      return;
    }
    await vad.pause();
    _setState(ConversationState.paused);
  }

  /// Duraklatılmış oturumu devam ettir.
  Future<void> resume() async {
    if (_state != ConversationState.paused) {
      throw StateError(
          'resume() yalnızca paused state\'inden çağrılabilir (şu an: $_state)');
    }
    await vad.start();
    _setState(ConversationState.listening);
  }

  /// Oturumu kapat: VAD durdur, TTS durdur, session'ı flush et.
  /// Idempotent — birden fazla kez çağrılırsa ikinciden sonra no-op.
  Future<void> end() async {
    if (_state == ConversationState.idle) return;

    _setState(ConversationState.ending);

    await _vadSub?.cancel();
    _vadSub = null;
    await vad.stop();
    await tts.stop();
    _isTtsSpeaking = false;

    // Sırada bekleyen son pipeline işini bitir.
    try {
      await _pipelineQueue;
    } catch (_) {
      // Pipeline hatası end() akışını bozmasın; eventStream'e zaten düşmüş olur.
    }

    final sessionId = _activeSessionId;
    if (sessionId != null) {
      await repository.endSession(sessionId);
    }
    _activeSessionId = null;

    _setState(ConversationState.idle);
  }

  /// Kaynakları serbest bırak. Bu çağrıdan sonra manager kullanılamaz.
  Future<void> dispose() async {
    await end();
    await _stateController.close();
    await _eventController.close();
  }

  // --- Internals ---

  void _setState(ConversationState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void _subscribeToVad() {
    _vadSub = vad.events.listen(_onVadEvent);
  }

  void _onVadEvent(VadUtteranceEvent event) {
    // Sadece "konuşma bitti, samples hazır" event'iyle ilgileniyoruz.
    // SpeechStart, RealSpeechStart, Misfire — UI debug için isteğe bağlı,
    // şu an no-op (sessiz drop).
    if (event is! VadSpeechEnd) return;
    // Pause sırasında VAD durdurulmuş olur ama tampona bir event takılı
    // kalmış olabilir; ekstra savunma.
    if (_state == ConversationState.paused ||
        _state == ConversationState.ending ||
        _state == ConversationState.idle) {
      return;
    }
    // ⚠ KRİTİK: TTS feedback guard (tasarım Bölüm 5).
    // TTS oynarken mikrofon kendi sesini duyup VAD tetikler → loop riski.
    // Manager kendi flag'ını tutar (tts.isSpeaking native plugin'e bağımlı,
    // her tick'te güvenilir olmayabilir).
    if (_isTtsSpeaking) {
      _drop('TTS oynuyor (feedback guard)');
      return;
    }
    _enqueueUtterance(event.samples);
  }

  void _enqueueUtterance(List<double> samples) {
    _pipelineQueue = _pipelineQueue.then((_) => _processUtterance(samples));
  }

  Future<void> _processUtterance(List<double> samples) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    // Pipeline tetiklenmeden önce oturum kapatılmış olabilir.
    if (_state == ConversationState.ending ||
        _state == ConversationState.idle) {
      return;
    }

    File? wavFile;
    try {
      _setState(ConversationState.transcribing);
      wavFile = await _dumpToTempWav(samples);

      // Whisper: language='auto' — kendi içinde dil seçer, biz metin alırız.
      final rawText = await stt.transcribeFile(
        wavFile.path,
        language: 'auto',
      );
      if (rawText.trim().isEmpty) {
        _drop('Whisper boş transkript');
        _setState(ConversationState.listening);
        return;
      }

      // Önce dil tespit (filler kelimeleri dile bağımlı, sıralama önemli).
      final detection = await languageDetector.detect(
        rawText,
        minConfidence: _languageMinConfidence,
      );
      if (detection == null) {
        _drop('Dil tespiti belirsiz veya conf < $_languageMinConfidence');
        _setState(ConversationState.listening);
        return;
      }

      final participant = _classifyParticipant(detection.languageCode);
      if (participant == null) {
        _drop('Yabancı dil: ${detection.languageCode}');
        _setState(ConversationState.listening);
        return;
      }

      // Filler temizleme — tespit edilen dil ile.
      final cleanText = _fillerCleaner.clean(
        rawText,
        language: detection.languageCode,
        level: _fillerLevel,
      );
      if (cleanText.trim().isEmpty) {
        _drop('Filler sonrası metin boş');
        _setState(ConversationState.listening);
        return;
      }

      _setState(ConversationState.translating);
      final fromCode = detection.languageCode;
      final toCode =
          participant == ConversationParticipant.sourceSpeaker
              ? targetLanguage
              : sourceLanguage;
      final translated = await translation.translate(cleanText, fromCode, toCode);

      // Repository'e yaz — speaking'den önce, böylece TTS patlasa bile
      // mesaj kalıcı kalır.
      final message = await repository.appendMessage(
        sessionId: sessionId,
        speakerLanguage: fromCode,
        sourceText: cleanText,
        translatedText: translated,
      );

      _eventController.add(
        ConversationMessageAdded(message: message, participant: participant),
      );

      _setState(ConversationState.speaking);
      await _speakWithMode(translated, toCode);

      _setState(ConversationState.listening);
    } catch (e) {
      _eventController.add(ConversationErrorEvent(e.toString()));
      _setState(ConversationState.error);
      // Hatadan recover et — yeni utterance dinlemeye devam.
      _setState(ConversationState.listening);
    } finally {
      // Temp WAV temizliği — best effort, hata logu lüks.
      if (wavFile != null) {
        unawaited(wavFile.delete().catchError((_) => wavFile!));
      }
    }
  }

  /// Mode-aware TTS oynatma.
  ///
  /// - [SessionMode.fast]: TTS aktif iken yeni `_speakWithMode` çağrısı
  ///   gelirse önceki TTS'i hemen kes, yeniyi oynat. Doğal diyalog
  ///   temposu için "kes" davranışı (tasarım karar b).
  /// - [SessionMode.full]: Kuyruk davranışı — pipeline zaten sıralı
  ///   olduğu için ek iş yok, sadece await edilir.
  ///
  /// Not: Pipeline mevcut hâlinde tek sıralı kuyruk (transcribe→…→TTS),
  /// dolayısıyla `fast` interrupt'ı pratikte yalnızca bu çağrı başka bir
  /// koddan paralel tetiklenirse devreye girer (ör. UI'dan manuel replay).
  /// Step 7+ ile pipeline parçalanırsa davranış doğal olarak açılır.
  Future<void> _speakWithMode(String text, String languageCode) async {
    if (mode == SessionMode.fast && (_isTtsSpeaking || tts.isSpeaking)) {
      await tts.stop();
      _isTtsSpeaking = false;
    }
    _isTtsSpeaking = true;
    try {
      await tts.speak(text, languageCode);
    } finally {
      _isTtsSpeaking = false;
    }
  }

  ConversationParticipant? _classifyParticipant(String detectedLang) {
    if (detectedLang == sourceLanguage) {
      return ConversationParticipant.sourceSpeaker;
    }
    if (detectedLang == targetLanguage) {
      return ConversationParticipant.targetSpeaker;
    }
    return null;
  }

  Future<File> _dumpToTempWav(List<double> samples) async {
    final dir = await _temporaryDirectory();
    final path = p.join(
      dir.path,
      'hermes_utt_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    return _wavWriter.writeMono16kHz(samples, path);
  }

  void _drop(String reason) {
    _eventController.add(ConversationDropped(reason));
  }
}

/// Manager'ın state'leri.
enum ConversationState {
  idle,
  listening,
  transcribing,
  translating,
  speaking,
  paused,
  ending,
  error,
}

/// Sözceyi söyleyen taraf — UI'da chat balonunun nereye hizalanacağı.
enum ConversationParticipant {
  /// Kaynak dili (örn. `sourceLanguage='tr'`) konuştu.
  sourceSpeaker,

  /// Hedef dili (örn. `targetLanguage='en'`) konuştu.
  targetSpeaker,
}

/// UI'a yayılan event'ler.
sealed class ConversationEvent {
  const ConversationEvent();
}

/// Yeni bir çevrilmiş mesaj chat'e eklendi.
class ConversationMessageAdded extends ConversationEvent {
  const ConversationMessageAdded({
    required this.message,
    required this.participant,
  });

  final MessageRow message;
  final ConversationParticipant participant;
}

/// Bir utterance sessizce işlenmedi (UI'da çoğunlukla gösterilmez,
/// debug ekranında log gibi).
class ConversationDropped extends ConversationEvent {
  const ConversationDropped(this.reason);
  final String reason;
}

/// Pipeline'da hata oluştu — UI hata banner'ı gösterebilir.
class ConversationErrorEvent extends ConversationEvent {
  const ConversationErrorEvent(this.message);
  final String message;
}
