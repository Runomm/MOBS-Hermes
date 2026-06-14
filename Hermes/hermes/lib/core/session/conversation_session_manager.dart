import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../audio/audio_input.dart';
import '../audio/wav_writer.dart';
import '../database/app_database.dart';
import '../engines/stt/stt_engine.dart';
import '../engines/translation/translation_engine.dart';
import '../engines/tts/tts_engine.dart';
import '../repositories/conversation_repository.dart';
import '../services/filler_cleaner.dart';
import '../services/title_generator.dart';

/// Konuşma Modu'nun çekirdek state machine'i + pipeline.
///
/// VAD → STT → FillerCleaner → Translate → TTS → Repository
/// zincirini tek noktadan yönetir. UI bu sınıfın `stateStream` ve
/// `eventStream`'ini dinler, butonlardan `start/pause/resume/end` çağırır.
///
/// 6r-a (2026-05-30): LanguageDetector ana akıştan koparıldı; dil tespiti
/// yerine konuşan taraf donanım/butondan bilinir. LangID kodu
/// `lib/core/engines/language_id/` altında saklı, Step 9'da yanlış dil uyarısı
/// + hibrit ders için bekliyor.
///
/// 6r-e (2026-05-31): Manager çift yönlü. `AudioUtteranceEvent.source`'a göre
/// yön çevirir — `primary` = kaynak dili konuştu (source→target, sourceSpeaker),
/// `secondary` = hedef dili konuştu (target→source, targetSpeaker). Bas Konuş'ta
/// `PushToTalkAudioInput` üst yarı için `secondary` yayar; Ders Modu'nda
/// `SingleMicAudioInput` hep `primary` → eski tek-yön davranışı korunur.
///
/// 6r-c (2026-05-30): `VadController` doğrudan bağımlılığı `AudioInput`
/// strategy'sine taşındı. `SingleMicAudioInput` mevcut VAD'i sarmar;
/// `DualMicAudioInput` (6r-d) Voice Translator için iki paralel mic
/// kaynağı sağlar. Manager artık alttaki audio implementasyonundan habersiz.
///
/// Bkz: HERMES_KONUSMA_MODU_TASARIM.md (Bölüm 3.1, 3.2, 4, 5).
class ConversationSessionManager {
  ConversationSessionManager({
    required this.audioInput,
    required this.stt,
    required this.translation,
    required this.tts,
    required this.repository,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.mode,
    this.quality = SessionQuality.fast,
    FillerCleaner fillerCleaner = const FillerCleaner(),
    FillerLevel fillerLevel = FillerLevel.conservative,
    WavWriter wavWriter = const WavWriter(),
    TitleGenerator titleGenerator = const TimestampFallbackGenerator(),
    Future<Directory> Function() temporaryDirectory =
        getTemporaryDirectory,
  })  : _fillerCleaner = fillerCleaner,
        _fillerLevel = fillerLevel,
        _wavWriter = wavWriter,
        _titleGenerator = titleGenerator,
        _temporaryDirectory = temporaryDirectory;

  // --- Dependencies ---

  /// Utterance kaynağı — `SingleMicAudioInput` (Ders Modu / Bas Konuş için
  /// tek mic), ileride `DualMicAudioInput` (Voice Translator) veya
  /// `PushToTalkAudioInput` (Bas Konuş buton-merkezli akışı) ile değiştirilir.
  final AudioInput audioInput;

  final SttEngine stt;
  final TranslationEngine translation;
  final TtsEngine tts;
  final ConversationRepository repository;
  final String sourceLanguage;
  final String targetLanguage;

  /// 3 modun hangisi: `lecture` / `voiceTranslator` / `pushToTalk`.
  /// 6r-b'de tek-boyutlu `fast/full`'tan 3 moda genişledi.
  final SessionMode mode;

  /// Whisper kalite seviyesi — `fast` (tiny) veya `full` (small).
  /// Eskiden `SessionMode.fast/full` tek alanda taşıyordu, 6r-b'de
  /// ayrıldı. TTS davranışı (interrupt vs sequential) bu alana bağlı.
  final SessionQuality quality;

  final FillerCleaner _fillerCleaner;
  final FillerLevel _fillerLevel;
  final WavWriter _wavWriter;

  /// Oturum başlığı üreticisi (6r-f). Default offline timestamp fallback;
  /// Step 9'da `HybridTitleGenerator(online: GeminiTitleGenerator(...))` ile
  /// içerikten anlamlı başlık üretilebilir.
  final TitleGenerator _titleGenerator;

  final Future<Directory> Function() _temporaryDirectory;

  // --- State ---
  ConversationState _state = ConversationState.idle;
  ConversationState get state => _state;

  /// [prepare] çağrıldı mı? Ağır motor yüklemesini bir kez yapmak için.
  bool _prepared = false;

  /// Motorlar yüklendi mi (ısınma ekranı için).
  bool get isPrepared => _prepared;

  final _stateController =
      StreamController<ConversationState>.broadcast();
  Stream<ConversationState> get stateStream => _stateController.stream;

  final _eventController =
      StreamController<ConversationEvent>.broadcast();
  Stream<ConversationEvent> get eventStream => _eventController.stream;

  int? _activeSessionId;
  int? get activeSessionId => _activeSessionId;

  StreamSubscription<AudioUtteranceEvent>? _audioSub;

  /// VAD utterance'larının sıralı işlenmesi için kuyruk —
  /// Whisper bir utterance işlerken yeni utterance gelirse hemen başlamasın,
  /// sırasını beklesin (tasarım Bölüm 5: "Async queue, sırayla işle").
  Future<void> _pipelineQueue = Future<void>.value();

  /// Oturum kapatılıyor mu? `_state`'ten BAĞIMSIZ kalıcı bayrak. `end()` bunu
  /// set eder; devam eden `_processUtterance` her await sonrası kontrol edip
  /// erken çıkar. (Eskiden `_state == ending` kontrolü vardı ama in-flight iş
  /// bitince `_setState(listening)` ile ezilip backlog'un tamamı işleniyordu →
  /// "Bitir" takılıyor + uzun konuşmada birikme. Bu bayrak ezilmez.)
  bool _stopping = false;

  /// Pipeline'da bekleyen (henüz bitmemiş) utterance sayısı. STT/çeviri canlı
  /// hızdan yavaş kalırsa kuyruk büyümesin diye backpressure sınırı.
  int _pendingUtterances = 0;

  /// Aynı anda en fazla kaç utterance kuyrukta bekleyebilir. Aşılırsa yeni
  /// chunk düşürülür (OOM yerine "geride kalındı" — transkript kaybı kabul,
  /// hız polish'i ayrı). ~3 chunk ≈ ~15sn tampon.
  static const int _maxPendingUtterances = 3;

  /// TTS aktif mi? `_onVadEvent` feedback guard'ı için. `tts.isSpeaking`
  /// native plugin'e bağımlı; biz speak çağrısının await'ini sararak
  /// kendi flag'ımızı tutarız (daha deterministik).
  bool _isTtsSpeaking = false;

  /// LLM çeviri **bağlamı** — bu oturumdaki son turlar (kaynak + çeviri).
  /// Her başarılı çeviriden sonra eklenir, `start()`'ta sıfırlanır. Çeviri
  /// motoruna geçilir; bağlamsız motorlar (MLKit) yok sayar. LLM bununla
  /// referansları çözer + tanıma hatalarını düzeltir (market→marcus).
  final List<TranslationTurn> _recentTurns = [];
  static const int _maxContextTurns = 8;

  // --- Public API ---

  /// Ağır hazırlık: STT kalite modunu ayarla + tüm motorları (STT/TTS/çeviri
  /// modeli) yükle. **Idempotent** — birden çok kez çağrılırsa ikinciden sonra
  /// no-op. Konferans Modu'nun "ısınma" ekranı bunu `start()`'tan önce çağırır,
  /// böylece başlatma anında gecikme olmaz. `start()` de prepare edilmemişse
  /// kendisi çağırır → eski çağıranlar (Bas Konuş vb.) etkilenmez.
  Future<void> prepare() async {
    if (_prepared) return;

    // 6r-f sonrası (Step 7 burst-3 feedback): quality → Whisper modeli.
    // `full` = doğruluk önceliği (Konferans Modu) → small model; `fast` = tiny.
    // Daha önce hiç bağlanmıyordu → Konferans Modu yanlışlıkla tiny kullanıyordu.
    await stt.setSpeedMode(
      quality == SessionQuality.full
          ? SttSpeedMode.accurate
          : SttSpeedMode.fast,
    );

    await Future.wait([
      stt.initialize(),
      tts.initialize(),
      translation.ensureModelLoaded(sourceLanguage, targetLanguage),
      translation.ensureModelLoaded(targetLanguage, sourceLanguage),
    ]);

    _prepared = true;
  }

  /// Oturumu başlat: motorları hazırla (gerekirse), repository'de session aç,
  /// audio input'u dinlemeye başlat. Önce [prepare] çağrılmışsa ağır iş atlanır
  /// → başlatma anında gerçekleşir.
  Future<void> start() async {
    if (_state != ConversationState.idle) {
      throw StateError('start() yalnızca idle state\'inden çağrılabilir '
          '(şu an: $_state)');
    }

    _stopping = false;
    _pendingUtterances = 0;
    _recentTurns.clear();

    await prepare();

    final session = await repository.createSession(
      mode: mode,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      quality: quality,
    );
    _activeSessionId = session.id;

    _subscribeToAudioInput();
    await audioInput.start();
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
    await audioInput.pause();
    _setState(ConversationState.paused);
  }

  /// Duraklatılmış oturumu devam ettir.
  Future<void> resume() async {
    if (_state != ConversationState.paused) {
      throw StateError(
          'resume() yalnızca paused state\'inden çağrılabilir (şu an: $_state)');
    }
    await audioInput.start();
    _setState(ConversationState.listening);
  }

  /// Oturumu kapat: audio input durdur, TTS durdur, session'ı flush et.
  /// Idempotent — birden fazla kez çağrılırsa ikinciden sonra no-op.
  /// Oturumu bitirir. Döndürdüğü id = arşivde kalan oturum; **boş transkriptli
  /// oturum silinir → `null`** döner (Mehmet 2026-06-11: boş kayıt yapma).
  Future<int?> end() async {
    if (_state == ConversationState.idle) return null;

    // KRİTİK: önce _stopping — devam eden/sıradaki pipeline işleri bunu görüp
    // erken çıksın. Böylece `await _pipelineQueue` yalnız o an çalışan TEK
    // transcribe'ı bekler (backlog'un tamamını değil) → "Bitir" anında yanıt.
    _stopping = true;
    _setState(ConversationState.ending);

    await _audioSub?.cancel();
    _audioSub = null;
    await audioInput.stop();
    await tts.stop();
    _isTtsSpeaking = false;

    // Sırada bekleyen işler _stopping'i görüp hemen döner; yalnız in-flight
    // transcribe tamamlanana kadar bekleriz (iptal edilemez native çağrı).
    try {
      await _pipelineQueue;
    } catch (_) {
      // Pipeline hatası end() akışını bozmasın; eventStream'e zaten düşmüş olur.
    }

    final sessionId = _activeSessionId;
    int? kept = sessionId;
    if (sessionId != null) {
      if (await repository.deleteSessionIfEmpty(sessionId)) {
        kept = null; // boş transkript → kaydetme
      } else {
        await _writeTitle(sessionId);
        await repository.endSession(sessionId);
      }
    }
    _activeSessionId = null;

    _setState(ConversationState.idle);
    return kept;
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

  void _subscribeToAudioInput() {
    _audioSub = audioInput.utterances.listen(_onAudioEvent);
  }

  void _onAudioEvent(AudioUtteranceEvent event) {
    // AudioInput abstraction'ı sadece bitmiş utterance yayar — VAD ara
    // state'leri (SpeechStart vs.) bu seviyede görünmez.
    //
    // Pause sırasında AudioInput durdurulmuş olur ama tampona bir event
    // takılı kalmış olabilir; ekstra savunma.
    if (_stopping ||
        _state == ConversationState.paused ||
        _state == ConversationState.ending ||
        _state == ConversationState.idle) {
      return;
    }
    // Backpressure: STT/çeviri canlı hızdan yavaş kalırsa kuyruk sınırsız
    // büyür → bellek şişer + `end()` geride kalır. Sınır aşılırsa yeni chunk'ı
    // düşür ("geride kalındı" sinyali). Hız iyileştirmesi ayrı polish notu.
    if (_pendingUtterances >= _maxPendingUtterances) {
      _drop('Pipeline meşgul — chunk atlandı (backpressure)');
      return;
    }
    // ⚠ KRİTİK: TTS feedback guard (tasarım Bölüm 5).
    // TTS oynarken mikrofon kendi sesini duyup VAD tetikler → loop riski.
    // Manager kendi flag'ını tutar (tts.isSpeaking native plugin'e bağımlı,
    // her tick'te güvenilir olmayabilir).
    //
    // Voice Translator'da donanım ayrımı bu riski büyük ölçüde çözer ama
    // guard yine de savunma katmanı olarak kalır (özellikle Bas Konuş'ta
    // hoparlörden seslendirme + dahili mic için kritik).
    if (_isTtsSpeaking) {
      _drop('TTS oynuyor (feedback guard)');
      return;
    }
    // 6r-e: event.source çift yönlü routing'i belirler. Bas Konuş'ta hangi
    // ekran yarısına basıldıysa o source gelir; Ders Modu / tek-mic her zaman
    // primary yayar (davranış değişmez).
    _enqueueUtterance(event.samples, event.source);
  }

  void _enqueueUtterance(List<double> samples, AudioSource source) {
    _pendingUtterances++;
    _pipelineQueue = _pipelineQueue.then((_) async {
      try {
        await _processUtterance(samples, source);
      } finally {
        _pendingUtterances--;
      }
    });
  }

  Future<void> _processUtterance(List<double> samples, AudioSource source) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    // Pipeline tetiklenmeden önce oturum kapatılmış olabilir (kalıcı bayrak —
    // in-flight iş `_setState(listening)` ile state'i ezse bile bu sıfırlanmaz).
    if (_stopping) return;

    // 6r-e: Çift yönlü routing. `primary` = kaynak dili konuştu
    // (sourceLanguage → targetLanguage, sourceSpeaker); `secondary` = hedef
    // dili konuştu (targetLanguage → sourceLanguage, targetSpeaker). Bas
    // Konuş'ta üst yarı `secondary` yayar. Ders Modu hep `primary` →
    // davranış birebir korunur.
    final isPrimary = source == AudioSource.primary;
    final fromCode = isPrimary ? sourceLanguage : targetLanguage;
    final toCode = isPrimary ? targetLanguage : sourceLanguage;
    final participant = isPrimary
        ? ConversationParticipant.sourceSpeaker
        : ConversationParticipant.targetSpeaker;

    File? wavFile;
    try {
      _setState(ConversationState.transcribing);
      wavFile = await _dumpToTempWav(samples);

      // Diller UI'dan + konuşan yarıdan biliniyor. Whisper'a explicit
      // language verilir, dil tespitine ihtiyaç yok.
      final rawText = await stt.transcribeFile(
        wavFile.path,
        language: fromCode,
      );
      // Uzun/iptal edilemez transcribe bitti — kapatma istendiyse burada dur
      // (çeviri + TTS'e girip end()'i bekletme).
      if (_stopping) return;
      if (rawText.trim().isEmpty) {
        // Motor-agnostik nötr sebep (UI bunu kullanıcıya gösterebiliyor —
        // hangi STT motorunun çalıştığı son kullanıcıyı ilgilendirmez).
        _drop('Ses algılanamadı');
        _setState(ConversationState.listening);
        return;
      }

      final cleanText = _fillerCleaner.clean(
        rawText,
        language: fromCode,
        level: _fillerLevel,
      );
      if (cleanText.trim().isEmpty) {
        _drop('Anlamlı konuşma bulunamadı');
        _setState(ConversationState.listening);
        return;
      }

      _setState(ConversationState.translating);
      final translated = await translation.translate(
        cleanText,
        fromCode,
        toCode,
        context: _recentTurns,
      );
      if (_stopping) return;

      // Bağlamı güncelle (sonraki çeviriler bu turu görsün). LLM referans +
      // tanıma hatası düzeltmesi bunu kullanır; MLKit yok sayar.
      _recentTurns.add(TranslationTurn(
        fromCode: fromCode,
        toCode: toCode,
        sourceText: cleanText,
        translatedText: translated,
      ));
      if (_recentTurns.length > _maxContextTurns) {
        _recentTurns.removeRange(0, _recentTurns.length - _maxContextTurns);
      }

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

      if (_stopping) return;
      _setState(ConversationState.speaking);
      await _speakWithMode(translated, toCode);

      if (!_stopping) _setState(ConversationState.listening);
    } catch (e) {
      _eventController.add(ConversationErrorEvent(e.toString()));
      if (!_stopping) {
        _setState(ConversationState.error);
        // Hatadan recover et — yeni utterance dinlemeye devam.
        _setState(ConversationState.listening);
      }
    } finally {
      // Temp WAV temizliği — best effort, hata logu lüks.
      if (wavFile != null) {
        unawaited(wavFile.delete().catchError((_) => wavFile!));
      }
    }
  }

  /// Quality-aware TTS oynatma.
  ///
  /// - [SessionQuality.fast]: TTS aktif iken yeni `_speakWithMode` çağrısı
  ///   gelirse önceki TTS'i hemen kes, yeniyi oynat. Doğal diyalog
  ///   temposu için "kes" davranışı (tasarım karar b).
  /// - [SessionQuality.full]: Kuyruk davranışı — pipeline zaten sıralı
  ///   olduğu için ek iş yok, sadece await edilir.
  ///
  /// Not: Pipeline mevcut hâlinde tek sıralı kuyruk (transcribe→…→TTS),
  /// dolayısıyla `fast` interrupt'ı pratikte yalnızca bu çağrı başka bir
  /// koddan paralel tetiklenirse devreye girer (ör. UI'dan manuel replay).
  /// Step 7+ ile pipeline parçalanırsa davranış doğal olarak açılır.
  ///
  /// 6r-b: Eskiden `mode == SessionMode.fast` kontrolüydü; 3-mod ayrımı
  /// gelince bu davranış doğal olarak `quality`'ye taşındı.
  Future<void> _speakWithMode(String text, String languageCode) async {
    if (quality == SessionQuality.fast &&
        (_isTtsSpeaking || tts.isSpeaking)) {
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

  /// 6r-f: Oturum kapanırken başlık üret + `sessions.title`'a yaz. Mesajlardan
  /// (online üretici varsa) veya timestamp fallback'ten. Başlık üretimi end()
  /// akışını bozmamalı — hata yutulur, oturum başlıksız kalır.
  Future<void> _writeTitle(int sessionId) async {
    try {
      final session = await repository.getSession(sessionId);
      final messages = await repository.listMessagesForSession(sessionId);
      final title = await _titleGenerator.generate(
        mode: mode,
        messages: messages,
        startedAt: session?.startedAt ?? DateTime.now(),
      );
      await repository.setTitle(sessionId, title);
    } catch (_) {
      // Başlık üretimi/yazımı oturum kapanışını bozmasın.
    }
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
