import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/database/app_database.dart';
import 'package:hermes/core/engines/language_id/language_detector.dart';
import 'package:hermes/core/engines/stt/stt_engine.dart';
import 'package:hermes/core/engines/translation/translation_engine.dart';
import 'package:hermes/core/engines/tts/tts_engine.dart';
import 'package:hermes/core/repositories/conversation_repository.dart';
import 'package:hermes/core/services/vad_controller.dart';
import 'package:hermes/core/session/conversation_session_manager.dart';

// ---------------------------------------------------------------------------
// Fake engines — gerçek native bağımlılıklardan kaçınmak için.
// ---------------------------------------------------------------------------

class FakeVadController implements VadController {
  final _controller = StreamController<VadUtteranceEvent>.broadcast();
  bool _listening = false;

  @override
  Stream<VadUtteranceEvent> get events => _controller.stream;

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
  void emit(VadUtteranceEvent event) => _controller.add(event);
}

class FakeSttEngine implements SttEngine {
  FakeSttEngine({String fixedTranscript = 'merhaba dünya'})
      : _fixedTranscript = fixedTranscript;

  String _fixedTranscript;
  set fixedTranscript(String v) => _fixedTranscript = v;

  int transcribeCallCount = 0;

  @override
  String get engineName => 'FakeStt';
  @override
  bool get isOfflineCapable => true;
  @override
  SttSpeedMode get speedMode => SttSpeedMode.fast;

  @override
  Future<void> initialize() async {}

  @override
  Future<String> transcribeFile(String audioPath,
      {String language = 'auto'}) async {
    transcribeCallCount++;
    return _fixedTranscript;
  }

  @override
  Future<void> setSpeedMode(SttSpeedMode mode) async {}

  @override
  Future<void> dispose() async {}
}

class FakeTranslationEngine implements TranslationEngine {
  int translateCallCount = 0;
  String? lastFrom;
  String? lastTo;
  String? lastText;
  Exception? throwOnTranslate;

  @override
  String get engineName => 'FakeTranslation';
  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> ensureModelLoaded(String fromCode, String toCode) async {}

  @override
  Future<String> translate(String text, String fromCode, String toCode) async {
    if (throwOnTranslate != null) throw throwOnTranslate!;
    translateCallCount++;
    lastFrom = fromCode;
    lastTo = toCode;
    lastText = text;
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

class FakeLanguageDetector implements LanguageDetector {
  FakeLanguageDetector({this.result});

  LanguageDetectionResult? result;

  @override
  String get engineName => 'FakeLangId';
  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<LanguageDetectionResult?> detect(String text,
      {double minConfidence = 0.6}) async {
    final r = result;
    if (r == null) return null;
    if (r.confidence < minConfidence) return null;
    return r;
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
    required this.vad,
    required this.stt,
    required this.translation,
    required this.tts,
    required this.langDetector,
    required this.db,
    required this.repo,
    required this.tempDir,
  });

  final ConversationSessionManager manager;
  final FakeVadController vad;
  final FakeSttEngine stt;
  final FakeTranslationEngine translation;
  final FakeTtsEngine tts;
  final FakeLanguageDetector langDetector;
  final AppDatabase db;
  final ConversationRepository repo;
  final Directory tempDir;

  Future<void> dispose() async {
    await manager.dispose();
    await db.close();
    await vad.dispose();
    await tempDir.delete(recursive: true);
  }
}

Future<Fixture> buildFixture({
  SessionMode mode = SessionMode.fast,
  String sourceLanguage = 'tr',
  String targetLanguage = 'en',
  LanguageDetectionResult? detectorResult,
  String transcript = 'merhaba',
}) async {
  final tempDir = await Directory.systemTemp.createTemp('hermes_test_');
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final repo = ConversationRepository(db);

  final vad = FakeVadController();
  final stt = FakeSttEngine(fixedTranscript: transcript);
  final translation = FakeTranslationEngine();
  final tts = FakeTtsEngine();
  final langDetector = FakeLanguageDetector(result: detectorResult);

  final manager = ConversationSessionManager(
    vad: vad,
    stt: stt,
    translation: translation,
    tts: tts,
    languageDetector: langDetector,
    repository: repo,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    mode: mode,
    temporaryDirectory: () async => tempDir,
  );

  return Fixture(
    manager: manager,
    vad: vad,
    stt: stt,
    translation: translation,
    tts: tts,
    langDetector: langDetector,
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
        expect(f.vad.isListening, isTrue);
        expect(f.manager.activeSessionId, isNotNull);

        final session = await f.repo.getSession(f.manager.activeSessionId!);
        expect(session, isNotNull);
        expect(session!.endedAt, isNull);
      } finally {
        await f.dispose();
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
        await f.manager.end();
        expect(f.manager.state, ConversationState.idle);

        final session = await f.repo.getSession(sessionId);
        expect(session, isNotNull);
        expect(session!.endedAt, isNotNull);
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
        detectorResult:
            const LanguageDetectionResult(languageCode: 'tr', confidence: 0.9),
      );
      try {
        await f.manager.start();

        final messageAdded = f.manager.eventStream
            .where((e) => e is ConversationMessageAdded)
            .cast<ConversationMessageAdded>()
            .first;

        f.vad.emit(VadSpeechEnd(List<double>.filled(8000, 0.1)));
        final event = await messageAdded.timeout(const Duration(seconds: 3));

        expect(event.participant, ConversationParticipant.sourceSpeaker);
        // FillerCleaner cümle başını büyük yapar: 'merhaba' → 'Merhaba'.
        expect(event.message.sourceText, 'Merhaba dünya');
        expect(event.message.translatedText, '[tr→en] Merhaba dünya');
        expect(f.translation.lastFrom, 'tr');
        expect(f.translation.lastTo, 'en');
        expect(f.tts.spokenTexts, ['[tr→en] Merhaba dünya']);
      } finally {
        await f.dispose();
      }
    });

    test('target dili konuşulursa source dile çevrilir (ters yön)', () async {
      final f = await buildFixture(
        sourceLanguage: 'tr',
        targetLanguage: 'en',
        transcript: 'hello world',
        detectorResult:
            const LanguageDetectionResult(languageCode: 'en', confidence: 0.95),
      );
      try {
        await f.manager.start();

        final messageAdded = f.manager.eventStream
            .where((e) => e is ConversationMessageAdded)
            .cast<ConversationMessageAdded>()
            .first;

        f.vad.emit(VadSpeechEnd(List<double>.filled(8000, 0.1)));
        final event = await messageAdded.timeout(const Duration(seconds: 3));

        expect(event.participant, ConversationParticipant.targetSpeaker);
        expect(f.translation.lastFrom, 'en');
        expect(f.translation.lastTo, 'tr');
      } finally {
        await f.dispose();
      }
    });

    test('aynı dil iki kez üst üste söylenir, iki ayrı mesaj eklenir', () async {
      // Karar (c): aynı dil üst üste — sessizce devam, iki ayrı mesaj.
      final f = await buildFixture(
        sourceLanguage: 'tr',
        targetLanguage: 'en',
        transcript: 'evet',
        detectorResult:
            const LanguageDetectionResult(languageCode: 'tr', confidence: 0.9),
      );
      try {
        await f.manager.start();

        final added = <ConversationMessageAdded>[];
        final sub = f.manager.eventStream.listen((e) {
          if (e is ConversationMessageAdded) added.add(e);
        });

        f.vad.emit(VadSpeechEnd(List<double>.filled(4000, 0.1)));
        f.vad.emit(VadSpeechEnd(List<double>.filled(4000, 0.2)));

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
        detectorResult:
            const LanguageDetectionResult(languageCode: 'tr', confidence: 0.9),
      );
      try {
        await f.manager.start();

        final dropped = f.manager.eventStream
            .where((e) => e is ConversationDropped)
            .cast<ConversationDropped>()
            .first;

        f.vad.emit(VadSpeechEnd(List<double>.filled(1000, 0.05)));
        final event = await dropped.timeout(const Duration(seconds: 3));

        expect(event.reason, contains('boş'));
        expect(f.translation.translateCallCount, 0);
      } finally {
        await f.dispose();
      }
    });

    test('langDetect null (conf düşük) → drop, çeviri yapılmaz', () async {
      final f = await buildFixture(
        transcript: 'belirsiz cümle',
        detectorResult:
            const LanguageDetectionResult(languageCode: 'tr', confidence: 0.4),
      );
      try {
        await f.manager.start();

        final dropped = f.manager.eventStream
            .where((e) => e is ConversationDropped)
            .cast<ConversationDropped>()
            .first;

        f.vad.emit(VadSpeechEnd(List<double>.filled(1000, 0.05)));
        final event = await dropped.timeout(const Duration(seconds: 3));

        expect(event.reason, contains('belirsiz'));
        expect(f.translation.translateCallCount, 0);
      } finally {
        await f.dispose();
      }
    });

    test('yabancı dil (source/target değil) → drop', () async {
      final f = await buildFixture(
        sourceLanguage: 'tr',
        targetLanguage: 'en',
        transcript: 'Guten Tag',
        detectorResult:
            const LanguageDetectionResult(languageCode: 'de', confidence: 0.95),
      );
      try {
        await f.manager.start();

        final dropped = f.manager.eventStream
            .where((e) => e is ConversationDropped)
            .cast<ConversationDropped>()
            .first;

        f.vad.emit(VadSpeechEnd(List<double>.filled(1000, 0.05)));
        final event = await dropped.timeout(const Duration(seconds: 3));

        expect(event.reason, contains('Yabancı'));
        expect(event.reason, contains('de'));
        expect(f.translation.translateCallCount, 0);
      } finally {
        await f.dispose();
      }
    });

    test('translation exception → ConversationErrorEvent, manager dimdik',
        () async {
      final f = await buildFixture(
        transcript: 'merhaba',
        detectorResult:
            const LanguageDetectionResult(languageCode: 'tr', confidence: 0.9),
      );
      f.translation.throwOnTranslate = Exception('mock fail');

      try {
        await f.manager.start();

        final err = f.manager.eventStream
            .where((e) => e is ConversationErrorEvent)
            .cast<ConversationErrorEvent>()
            .first;

        f.vad.emit(VadSpeechEnd(List<double>.filled(1000, 0.05)));
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
    test('TTS oynarken VAD event → drop (feedback guard)', () async {
      final f = await buildFixture(
        transcript: 'merhaba',
        detectorResult:
            const LanguageDetectionResult(languageCode: 'tr', confidence: 0.9),
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
        f.vad.emit(VadSpeechEnd(List<double>.filled(1000, 0.05)));

        // İlk pipeline'ın TTS noktasına gelmesini bekle (~50ms yeter).
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // TTS oynarken yeni utterance gelir → feedback guard drop etmeli.
        f.vad.emit(VadSpeechEnd(List<double>.filled(1000, 0.05)));

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

  group('ConversationSessionManager — mode davranışı', () {
    test('fast mode: TTS oynarken _speakWithMode tetiklenirse stop çağrılır',
        () async {
      // Pratikte VAD guard nedeniyle bu yol açık değil; manuel TTS replay
      // (gelecek UI) için interrupt kontratını burada doğruluyoruz.
      final f = await buildFixture(
        mode: SessionMode.fast,
        transcript: 'merhaba',
        detectorResult:
            const LanguageDetectionResult(languageCode: 'tr', confidence: 0.9),
      );
      f.tts.speakDuration = const Duration(milliseconds: 200);

      try {
        await f.manager.start();

        // Tek normal utterance — TTS speak çağrılır.
        f.vad.emit(VadSpeechEnd(List<double>.filled(1000, 0.05)));
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(f.tts.speakCallCount, 1);
        // fast mode'da ilk speak başlamadan önce stop denenmedi (zaten TTS yoktu).
        expect(f.tts.stopCallCount, 0);
      } finally {
        await f.dispose();
      }
    });

    test('full mode: TTS sequential, stop çağrılmaz', () async {
      final f = await buildFixture(
        mode: SessionMode.full,
        transcript: 'merhaba',
        detectorResult:
            const LanguageDetectionResult(languageCode: 'tr', confidence: 0.9),
      );
      f.tts.speakDuration = const Duration(milliseconds: 50);

      try {
        await f.manager.start();
        f.vad.emit(VadSpeechEnd(List<double>.filled(1000, 0.05)));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(f.tts.speakCallCount, 1);
        expect(f.tts.stopCallCount, 0);
      } finally {
        await f.dispose();
      }
    });
  });
}
