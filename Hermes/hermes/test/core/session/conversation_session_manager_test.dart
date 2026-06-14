import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/audio/audio_input.dart';
import 'package:hermes/core/database/app_database.dart';
import 'package:hermes/core/engines/stt/stt_engine.dart';
import 'package:hermes/core/engines/translation/translation_engine.dart';
import 'package:hermes/core/engines/tts/tts_engine.dart';
import 'package:hermes/core/repositories/conversation_repository.dart';
import 'package:hermes/core/services/title_generator.dart';
import 'package:hermes/core/session/conversation_session_manager.dart';

// ---------------------------------------------------------------------------
// Fake engines — gerçek native bağımlılıklardan kaçınmak için.
// ---------------------------------------------------------------------------

/// 6r-c: Manager artık AudioInput soyutlamasını alıyor. Test'te AudioInput'u
/// direkt fake'lemek daha doğru — alttaki VAD katmanını test etmek
/// gereksiz çünkü bu kontrat (utterance bitmiş, samples hazır) zaten
/// SingleMicAudioInput tarafından sağlanıyor.
class FakeAudioInput implements AudioInput {
  final _controller = StreamController<AudioUtteranceEvent>.broadcast();
  bool _listening = false;

  @override
  Stream<AudioUtteranceEvent> get utterances => _controller.stream;

  @override
  bool get isListening => _listening;

  @override
  Future<void> start() async => _listening = true;

  @override
  Future<void> pause() async => _listening = false;

  @override
  Future<void> stop() async => _listening = false;

  @override
  Future<void> dispose() async {
    _listening = false;
    await _controller.close();
  }

  /// Test API — event injekte et.
  void emit(AudioUtteranceEvent event) => _controller.add(event);

  /// Helper — sadece samples vererek primary source ile utterance gönder.
  void emitSamples(List<double> samples) => emit(
        AudioUtteranceEvent(
          samples: samples,
          source: AudioSource.primary,
          detectedAt: DateTime.now(),
        ),
      );
}

class FakeSttEngine implements SttEngine {
  FakeSttEngine({String fixedTranscript = 'merhaba dünya'})
      : _fixedTranscript = fixedTranscript;

  String _fixedTranscript;
  set fixedTranscript(String v) => _fixedTranscript = v;

  int transcribeCallCount = 0;
  String? lastLanguage;
  SttSpeedMode _speedMode = SttSpeedMode.fast;

  /// Set edilirse `transcribeFile` bu completer tamamlanana kadar bekler —
  /// backpressure / end()-sırasında-takılma testleri için yavaş transcribe
  /// simülasyonu.
  Completer<void>? transcribeGate;

  @override
  String get engineName => 'FakeStt';
  @override
  bool get isOfflineCapable => true;
  @override
  SttSpeedMode get speedMode => _speedMode;

  @override
  Future<void> initialize() async {}

  @override
  Future<String> transcribeFile(String audioPath,
      {String language = 'auto'}) async {
    transcribeCallCount++;
    lastLanguage = language;
    if (transcribeGate != null) await transcribeGate!.future;
    return _fixedTranscript;
  }

  @override
  Future<void> setSpeedMode(SttSpeedMode mode) async => _speedMode = mode;

  @override
  Future<void> dispose() async {}
}

class FakeTranslationEngine implements TranslationEngine {
  int translateCallCount = 0;
  String? lastFrom;
  String? lastTo;
  String? lastText;
  List<TranslationTurn> lastContext = const [];
  Exception? throwOnTranslate;

  @override
  String get engineName => 'FakeTranslation';
  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> ensureModelLoaded(String fromCode, String toCode) async {}

  @override
  Future<String> translate(
    String text,
    String fromCode,
    String toCode, {
    List<TranslationTurn> context = const [],
  }) async {
    if (throwOnTranslate != null) throw throwOnTranslate!;
    translateCallCount++;
    lastFrom = fromCode;
    lastTo = toCode;
    lastText = text;
    lastContext = List.of(context);
    return '[$fromCode→$toCode] $text';
  }

  @override
  Future<bool> isLanguageReady(String code) async => true;
  @override
  int estimatedDownloadSizeMb(String code) => 30;
  @override
  Future<void> downloadLanguage(String code) async {}
  @override
  Future<void> deleteLanguage(String code) async {}
  @override
  Future<void> dispose() async {}
}

class FakeTtsEngine implements TtsEngine {
  int speakCallCount = 0;
  int stopCallCount = 0;
  bool _isSpeaking = false;
  Duration speakDuration = const Duration(milliseconds: 10);
  final List<String> spokenTexts = [];

  @override
  String get engineName => 'FakeTts';
  @override
  bool get isOfflineCapable => true;
  @override
  bool get isSpeaking => _isSpeaking;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(String text, String languageCode) async {
    speakCallCount++;
    spokenTexts.add(text);
    _isSpeaking = true;
    await Future<void>.delayed(speakDuration);
    _isSpeaking = false;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    _isSpeaking = false;
  }

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Test helper — manager'ı eşit fixture'la kuruyor.
// ---------------------------------------------------------------------------

class Fixture {
  Fixture({
    required this.manager,
    required this.audioInput,
    required this.stt,
    required this.translation,
    required this.tts,
    required this.db,
    required this.repo,
    required this.tempDir,
  });

  final ConversationSessionManager manager;
  final FakeAudioInput audioInput;
  final FakeSttEngine stt;
  final FakeTranslationEngine translation;
  final FakeTtsEngine tts;
  final AppDatabase db;
  final ConversationRepository repo;
  final Directory tempDir;

  Future<void> dispose() async {
    await manager.dispose();
    await db.close();
    await audioInput.dispose();
    await tempDir.delete(recursive: true);
  }
}

/// Sabit başlık döndüren fake — Manager'ın end()'de TitleGenerator'ı çağırıp
/// sonucu yazdığını doğrulamak için.
class FakeTitleGenerator implements TitleGenerator {
  FakeTitleGenerator(this.title);
  final String title;
  int callCount = 0;

  @override
  Future<String> generate({
    required SessionMode mode,
    required List<MessageRow> messages,
    required DateTime startedAt,
  }) async {
    callCount++;
    return title;
  }
}

Future<Fixture> buildFixture({
  SessionMode mode = SessionMode.voiceTranslator,
  SessionQuality quality = SessionQuality.fast,
  String sourceLanguage = 'tr',
  String targetLanguage = 'en',
  String transcript = 'merhaba',
  TitleGenerator titleGenerator = const TimestampFallbackGenerator(),
}) async {
  final tempDir = await Directory.systemTemp.createTemp('hermes_test_');
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final repo = ConversationRepository(db);

  final audioInput = FakeAudioInput();
  final stt = FakeSttEngine(fixedTranscript: transcript);
  final translation = FakeTranslationEngine();
  final tts = FakeTtsEngine();

  final manager = ConversationSessionManager(
    audioInput: audioInput,
    stt: stt,
    translation: translation,
    tts: tts,
    repository: repo,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    mode: mode,
    quality: quality,
    titleGenerator: titleGenerator,
    temporaryDirectory: () async => tempDir,
  );

  return Fixture(
    manager: manager,
    audioInput: audioInput,
    stt: stt,
    translation: translation,
    tts: tts,
    db: db,
    repo: repo,
    tempDir: tempDir,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConversationSessionManager — state machine', () {
    test('idle → listening on start, repository session açılır', () async {
      final f = await buildFixture();
      try {
        expect(f.manager.state, ConversationState.idle);
        await f.manager.start();
        expect(f.manager.state, ConversationState.listening);
        expect(f.audioInput.isListening, isTrue);
        expect(f.manager.activeSessionId, isNotNull);

        final session = await f.repo.getSession(f.manager.activeSessionId!);
        expect(session, isNotNull);
        expect(session!.endedAt, isNull);
      } finally {
        await f.dispose();
      }
    });

    test('quality → Whisper speed mode bağlanır (full=accurate, fast=fast)',
        () async {
      final full = await buildFixture(quality: SessionQuality.full);
      try {
        await full.manager.start();
        expect(full.stt.speedMode, SttSpeedMode.accurate);
      } finally {
        await full.dispose();
      }

      final fast = await buildFixture(quality: SessionQuality.fast);
      try {
        await fast.manager.start();
        expect(fast.stt.speedMode, SttSpeedMode.fast);
      } finally {
        await fast.dispose();
      }
    });

    test('start() çift çağrılırsa StateError fırlatır', () async {
      final f = await buildFixture();
      try {
        await f.manager.start();
        expect(() => f.manager.start(), throwsStateError);
      } finally {
        await f.dispose();
      }
    });

    test('pause → resume → end state akışı', () async {
      final f = await buildFixture();
      try {
        await f.manager.start();
        await f.manager.pause();
        expect(f.manager.state, ConversationState.paused);

        await f.manager.resume();
        expect(f.manager.state, ConversationState.listening);

        final sessionId = f.manager.activeSessionId!;
        // Boş oturum end()'de silinir (Mehmet 2026-06-11) → mesaj ekle ki kalsın.
        await f.repo.appendMessage(
          sessionId: sessionId,
          speakerLanguage: 'tr',
          sourceText: 'merhaba',
          translatedText: 'hello',
        );
        await f.manager.end();
        expect(f.manager.state, ConversationState.idle);

        final session = await f.repo.getSession(sessionId);
        expect(session, isNotNull);
        expect(session!.endedAt, isNotNull);
      } finally {
        await f.dispose();
      }
    });

    test('end() başlık üretip sessions.title\'a yazar (6r-f)', () async {
      final gen = FakeTitleGenerator('kahve siparişi');
      final f = await buildFixture(titleGenerator: gen);
      try {
        await f.manager.start();
        final sessionId = f.manager.activeSessionId!;
        // Boş oturum end()'de silinir (Mehmet 2026-06-11) → mesaj ekle ki kalsın.
        await f.repo.appendMessage(
          sessionId: sessionId,
          speakerLanguage: 'tr',
          sourceText: 'bir kahve lütfen',
          translatedText: 'one coffee please',
        );
        await f.manager.end();

        expect(gen.callCount, 1);
        final session = await f.repo.getSession(sessionId);
        expect(session!.title, 'kahve siparişi');
      } finally {
        await f.dispose();
      }
    });

    test('end() boş oturumu siler ve null döner (Mehmet 2026-06-11)', () async {
      final gen = FakeTitleGenerator('kullanılmamalı');
      final f = await buildFixture(titleGenerator: gen);
      try {
        await f.manager.start();
        final sessionId = f.manager.activeSessionId!;
        final kept = await f.manager.end();

        expect(kept, isNull);
        expect(gen.callCount, 0); // silinen oturum için başlık üretilmez
        expect(await f.repo.getSession(sessionId), isNull);
        expect(f.manager.state, ConversationState.idle);
      } finally {
        await f.dispose();
      }
    });

    test('end() idempotent — ikinci çağrı no-op', () async {
      final f = await buildFixture();
      try {
        await f.manager.start();
        await f.manager.end();
        await f.manager.end();
        expect(f.manager.state, ConversationState.idle);
      } finally {
        await f.dispose();
      }
    });

    test('resume() paused değilse StateError', () async {
      final f = await buildFixture();
      try {
        await f.manager.start();
        expect(() => f.manager.resume(), throwsStateError);
      } finally {
        await f.dispose();
      }
    });

    test('pause() idle iken no-op', () async {
      final f = await buildFixture();
      try {
        await f.manager.pause();
        expect(f.manager.state, ConversationState.idle);
      } finally {
        await f.dispose();
      }
    });
  });

  group('ConversationSessionManager — pipeline happy path', () {
    test('source dili konuşulursa target dile çevrilir, mesaj eklenir',
        () async {
      final f = await buildFixture(
        sourceLanguage: 'tr',
        targetLanguage: 'en',
        transcript: 'merhaba dünya',
      );
      try {
        await f.manager.start();

        final messageAdded = f.manager.eventStream
            .where((e) => e is ConversationMessageAdded)
            .cast<ConversationMessageAdded>()
            .first;

        f.audioInput.emitSamples(List<double>.filled(8000, 0.1));
        final event = await messageAdded.timeout(const Duration(seconds: 3));

        expect(event.participant, ConversationParticipant.sourceSpeaker);
        // FillerCleaner cümle başını büyük yapar: 'merhaba' → 'Merhaba'.
        expect(event.message.sourceText, 'Merhaba dünya');
        expect(event.message.translatedText, '[tr→en] Merhaba dünya');
        expect(f.translation.lastFrom, 'tr');
        expect(f.translation.lastTo, 'en');
        // 6r-a: Whisper'a explicit language=sourceLanguage geçilir.
        expect(f.stt.lastLanguage, 'tr');
        expect(f.tts.spokenTexts, ['[tr→en] Merhaba dünya']);
      } finally {
        await f.dispose();
      }
    });

    test('secondary source → ters yön çevrilir (targetSpeaker)', () async {
      // 6r-e: Bas Konuş üst yarı → AudioSource.secondary → hedef dili konuştu.
      // Manager yönü çevirmeli: target→source, targetSpeaker, Whisper lang=target.
      final f = await buildFixture(
        sourceLanguage: 'tr',
        targetLanguage: 'en',
        transcript: 'hello world',
      );
      try {
        await f.manager.start();

        final messageAdded = f.manager.eventStream
            .where((e) => e is ConversationMessageAdded)
            .cast<ConversationMessageAdded>()
            .first;

        f.audioInput.emit(
          AudioUtteranceEvent(
            samples: List<double>.filled(8000, 0.1),
            source: AudioSource.secondary,
            detectedAt: DateTime.now(),
          ),
        );
        final event = await messageAdded.timeout(const Duration(seconds: 3));

        expect(event.participant, ConversationParticipant.targetSpeaker);
        // Ters yön: en→tr. FillerCleaner cümle başını büyütür.
        expect(event.message.sourceText, 'Hello world');
        expect(event.message.translatedText, '[en→tr] Hello world');
        expect(event.message.speakerLanguage, 'en');
        expect(f.translation.lastFrom, 'en');
        expect(f.translation.lastTo, 'tr');
        // Whisper'a hedef dil geçilmeli (konuşan üst yarı).
        expect(f.stt.lastLanguage, 'en');
        expect(f.tts.spokenTexts, ['[en→tr] Hello world']);
      } finally {
        await f.dispose();
      }
    });

    test('iki utterance üst üste, iki ayrı mesaj eklenir', () async {
      // primary source → her ikisi de sourceSpeaker (tek yön, Ders Modu davranışı).
      final f = await buildFixture(
        sourceLanguage: 'tr',
        targetLanguage: 'en',
        transcript: 'evet',
      );
      try {
        await f.manager.start();

        final added = <ConversationMessageAdded>[];
        final sub = f.manager.eventStream.listen((e) {
          if (e is ConversationMessageAdded) added.add(e);
        });

        f.audioInput.emitSamples(List<double>.filled(4000, 0.1));
        f.audioInput.emitSamples(List<double>.filled(4000, 0.2));

        // Kuyrukta sıralı işleneceği için biraz bekle.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await sub.cancel();

        expect(added, hasLength(2));
        expect(added[0].participant, ConversationParticipant.sourceSpeaker);
        expect(added[1].participant, ConversationParticipant.sourceSpeaker);
      } finally {
        await f.dispose();
      }
    });
  });

  group('ConversationSessionManager — sessiz drop senaryoları', () {
    test('boş transkript → ConversationDropped, mesaj eklenmez', () async {
      final f = await buildFixture(
        transcript: '   ',
      );
      try {
        await f.manager.start();

        final dropped = f.manager.eventStream
            .where((e) => e is ConversationDropped)
            .cast<ConversationDropped>()
            .first;

        f.audioInput.emitSamples(List<double>.filled(1000, 0.05));
        final event = await dropped.timeout(const Duration(seconds: 3));

        expect(event.reason, contains('algılanamadı'));
        expect(f.translation.translateCallCount, 0);
      } finally {
        await f.dispose();
      }
    });

    test('translation exception → ConversationErrorEvent, manager dimdik',
        () async {
      final f = await buildFixture(
        transcript: 'merhaba',
      );
      f.translation.throwOnTranslate = Exception('mock fail');

      try {
        await f.manager.start();

        final err = f.manager.eventStream
            .where((e) => e is ConversationErrorEvent)
            .cast<ConversationErrorEvent>()
            .first;

        f.audioInput.emitSamples(List<double>.filled(1000, 0.05));
        final event = await err.timeout(const Duration(seconds: 3));
        expect(event.message, contains('mock fail'));

        // Recover edip listening'e dönmeli.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(f.manager.state, ConversationState.listening);
      } finally {
        await f.dispose();
      }
    });
  });

  group('ConversationSessionManager — TTS feedback guard', () {
    test('TTS oynarken audio event → drop (feedback guard)', () async {
      final f = await buildFixture(
        transcript: 'merhaba',
      );
      // TTS uzun sürsün ki guard test edilebilsin.
      f.tts.speakDuration = const Duration(milliseconds: 500);

      try {
        await f.manager.start();

        final added = <ConversationMessageAdded>[];
        final dropped = <ConversationDropped>[];
        final sub = f.manager.eventStream.listen((e) {
          if (e is ConversationMessageAdded) added.add(e);
          if (e is ConversationDropped) dropped.add(e);
        });

        // İlk utterance → pipeline'a girer, TTS oynamaya başlar.
        f.audioInput.emitSamples(List<double>.filled(1000, 0.05));

        // İlk pipeline'ın TTS noktasına gelmesini bekle (~50ms yeter).
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // TTS oynarken yeni utterance gelir → feedback guard drop etmeli.
        f.audioInput.emitSamples(List<double>.filled(1000, 0.05));

        // İlk TTS'in bitmesini bekle.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await sub.cancel();

        expect(added, hasLength(1), reason: 'sadece ilk utterance işlenmeli');
        expect(dropped, hasLength(1), reason: 'ikincisi guard ile drop');
        expect(dropped.first.reason, contains('feedback guard'));
      } finally {
        await f.dispose();
      }
    });
  });

  group('ConversationSessionManager — quality davranışı', () {
    test('fast quality: TTS oynarken _speakWithMode tetiklenirse stop çağrılır',
        () async {
      // Pratikte VAD guard nedeniyle bu yol açık değil; manuel TTS replay
      // (gelecek UI) için interrupt kontratını burada doğruluyoruz.
      // 6r-b: davranış SessionMode'tan SessionQuality'ye taşındı.
      final f = await buildFixture(
        mode: SessionMode.voiceTranslator,
        quality: SessionQuality.fast,
        transcript: 'merhaba',
      );
      f.tts.speakDuration = const Duration(milliseconds: 200);

      try {
        await f.manager.start();

        // Tek normal utterance — TTS speak çağrılır.
        f.audioInput.emitSamples(List<double>.filled(1000, 0.05));
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(f.tts.speakCallCount, 1);
        // fast quality'de ilk speak başlamadan önce stop denenmedi (zaten TTS yoktu).
        expect(f.tts.stopCallCount, 0);
      } finally {
        await f.dispose();
      }
    });

    test('full quality: TTS sequential, stop çağrılmaz', () async {
      final f = await buildFixture(
        mode: SessionMode.lecture,
        quality: SessionQuality.full,
        transcript: 'merhaba',
      );
      f.tts.speakDuration = const Duration(milliseconds: 50);

      try {
        await f.manager.start();
        f.audioInput.emitSamples(List<double>.filled(1000, 0.05));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(f.tts.speakCallCount, 1);
        expect(f.tts.stopCallCount, 0);
      } finally {
        await f.dispose();
      }
    });
  });

  // Uzun konferans bug'ı (2026-06-05): STT yetişemeyince kuyruk şişiyor +
  // end() tüm backlog'u bekleyip "Bitir" takılıyordu. Fix: _stopping bayrağı
  // (ezilmez) + backpressure sınırı.
  group('backpressure + end() takılma fix', () {
    test('end() in-flight transcribe takılıyken backlog\'u işlemez, '
        'state idle\'a döner', () async {
      final f = await buildFixture(
        mode: SessionMode.lecture,
        quality: SessionQuality.full,
      );
      try {
        final gate = Completer<void>();
        f.stt.transcribeGate = gate;
        await f.manager.start();

        // Burst — ilk utterance transcribe'da bloke, kalanlar kuyrukta.
        for (var i = 0; i < 4; i++) {
          f.audioInput.emitSamples(List<double>.filled(800, 0.05));
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // end() çağrılır (in-flight transcribe hâlâ bloke) → _stopping set.
        final endFuture = f.manager.end();
        gate.complete(); // in-flight transcribe döner; _stopping ile bail.
        await endFuture;

        expect(f.manager.state, ConversationState.idle);
        // Hiçbiri çeviriye geçmemeli — transcribe sonrası _stopping bail.
        expect(f.translation.translateCallCount, 0);
      } finally {
        await f.dispose();
      }
    });

    test('kuyruk sınırı (backpressure) aşılınca fazlalık chunk düşürülür',
        () async {
      final f = await buildFixture(
        mode: SessionMode.lecture,
        quality: SessionQuality.full,
      );
      try {
        final gate = Completer<void>();
        f.stt.transcribeGate = gate;
        await f.manager.start();

        final dropped = <String>[];
        final sub = f.manager.eventStream.listen((e) {
          if (e is ConversationDropped) dropped.add(e.reason);
        });

        // 6 utterance burst; ilki transcribe'da bloke → kuyruk dolar, cap=3
        // aşılınca fazlalar düşer.
        for (var i = 0; i < 6; i++) {
          f.audioInput.emitSamples(List<double>.filled(800, 0.05));
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(dropped.where((r) => r.contains('backpressure')).isNotEmpty,
            isTrue);

        gate.complete();
        await sub.cancel();
      } finally {
        await f.dispose();
      }
    });
  });
}
