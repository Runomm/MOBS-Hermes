import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/database/app_database.dart';
import 'package:hermes/core/engines/stt/vosk_streaming_controller.dart';
import 'package:hermes/core/engines/translation/translation_engine.dart';
import 'package:hermes/core/engines/tts/tts_engine.dart';
import 'package:hermes/core/repositories/conversation_repository.dart';
import 'package:hermes/core/services/title_generator.dart';
import 'package:hermes/core/session/conference_streaming_session.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeStreamingTranscriber implements StreamingTranscriber {
  final _partials = StreamController<String>.broadcast();
  final _finals = StreamController<String>.broadcast();

  bool loaded = false;
  bool started = false;
  bool stopped = false;
  bool disposed = false;
  String? loadedLang;

  @override
  Stream<String> get partials => _partials.stream;
  @override
  Stream<String> get finals => _finals.stream;

  @override
  Future<void> load(String language) async {
    loaded = true;
    loadedLang = language;
  }

  @override
  Future<void> start() async => started = true;
  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!_partials.isClosed) await _partials.close();
    if (!_finals.isClosed) await _finals.close();
  }

  // Test API
  void emitPartial(String s) => _partials.add(s);
  void emitFinal(String s) => _finals.add(s);
}

class FakeTranslationEngine implements TranslationEngine {
  int translateCallCount = 0;
  String? lastFrom;
  String? lastTo;
  final List<String> translatedInputs = [];

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
    translateCallCount++;
    lastFrom = fromCode;
    lastTo = toCode;
    translatedInputs.add(text);
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
  final List<String> spokenTexts = [];
  final bool _speaking = false;

  @override
  String get engineName => 'FakeTts';
  @override
  bool get isOfflineCapable => true;
  @override
  bool get isSpeaking => _speaking;
  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(String text, String languageCode) async {
    speakCallCount++;
    spokenTexts.add(text);
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

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

class Fixture {
  Fixture({
    required this.session,
    required this.transcriber,
    required this.translation,
    required this.tts,
    required this.db,
    required this.repo,
  });

  final ConferenceStreamingSession session;
  final FakeStreamingTranscriber transcriber;
  final FakeTranslationEngine translation;
  final FakeTtsEngine tts;
  final AppDatabase db;
  final ConversationRepository repo;

  Future<void> dispose() async {
    await session.dispose();
    await db.close();
  }
}

Future<Fixture> build({
  bool ttsEnabled = true,
  String source = 'tr',
  String target = 'en',
  TitleGenerator titleGenerator = const TimestampFallbackGenerator(),
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final repo = ConversationRepository(db);
  final transcriber = FakeStreamingTranscriber();
  final translation = FakeTranslationEngine();
  final tts = FakeTtsEngine();
  final session = ConferenceStreamingSession(
    transcriber: transcriber,
    repository: repo,
    translation: translation,
    tts: tts,
    sourceLanguage: source,
    targetLanguage: target,
    ttsEnabled: ttsEnabled,
    titleGenerator: titleGenerator,
  );
  return Fixture(
    session: session,
    transcriber: transcriber,
    translation: translation,
    tts: tts,
    db: db,
    repo: repo,
  );
}

void main() {
  group('ConferenceStreamingSession', () {
    test('start() lecture/full session açar, model yüklenir, dinleme başlar',
        () async {
      final f = await build();
      try {
        await f.session.start();
        expect(f.transcriber.loaded, isTrue);
        expect(f.transcriber.loadedLang, 'tr');
        expect(f.transcriber.started, isTrue);
        expect(f.session.activeSessionId, isNotNull);

        final s = await f.repo.getSession(f.session.activeSessionId!);
        expect(s, isNotNull);
        expect(s!.mode, SessionMode.lecture.dbValue);
        expect(s.quality, SessionQuality.full.dbValue);
      } finally {
        await f.dispose();
      }
    });

    test('final → filler temizle → çevir → mesaj yaz → translations yayılır',
        () async {
      final f = await build();
      try {
        await f.session.start();

        final firstTranslation = f.session.translations.first;
        f.transcriber.emitFinal('merhaba dünya');
        final t =
            await firstTranslation.timeout(const Duration(seconds: 3));

        // FillerCleaner cümle başını büyütür: 'merhaba' → 'Merhaba'.
        expect(t, '[tr→en] Merhaba dünya');
        expect(f.translation.lastFrom, 'tr');
        expect(f.translation.lastTo, 'en');

        final msgs =
            await f.repo.listMessagesForSession(f.session.activeSessionId!);
        expect(msgs, hasLength(1));
        expect(msgs.first.sourceText, 'Merhaba dünya');
        expect(msgs.first.translatedText, '[tr→en] Merhaba dünya');
        expect(msgs.first.speakerLanguage, 'tr');

        // ttsEnabled → seslendirilir.
        expect(f.tts.spokenTexts, ['[tr→en] Merhaba dünya']);
      } finally {
        await f.dispose();
      }
    });

    test('boş final → çeviri yok, mesaj yok', () async {
      final f = await build();
      try {
        await f.session.start();
        f.transcriber.emitFinal('   ');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(f.translation.translateCallCount, 0);
        final msgs =
            await f.repo.listMessagesForSession(f.session.activeSessionId!);
        expect(msgs, isEmpty);
      } finally {
        await f.dispose();
      }
    });

    test('partial → livePartial yayılır, çeviri tetiklemez', () async {
      final f = await build();
      try {
        await f.session.start();
        final firstPartial = f.session.livePartial.first;
        f.transcriber.emitPartial('mer');
        final p = await firstPartial.timeout(const Duration(seconds: 3));
        expect(p, 'mer');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(f.translation.translateCallCount, 0);
      } finally {
        await f.dispose();
      }
    });

    test('ttsEnabled=false → seslendirme yok ama mesaj yazılır', () async {
      final f = await build(ttsEnabled: false);
      try {
        await f.session.start();
        final firstTranslation = f.session.translations.first;
        f.transcriber.emitFinal('merhaba');
        await firstTranslation.timeout(const Duration(seconds: 3));
        expect(f.tts.speakCallCount, 0);
        final msgs =
            await f.repo.listMessagesForSession(f.session.activeSessionId!);
        expect(msgs, hasLength(1));
      } finally {
        await f.dispose();
      }
    });

    test('iki final sırayla → iki mesaj, sıra korunur', () async {
      final f = await build(ttsEnabled: false);
      try {
        await f.session.start();
        f.transcriber.emitFinal('bir');
        f.transcriber.emitFinal('iki');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final msgs =
            await f.repo.listMessagesForSession(f.session.activeSessionId!);
        expect(msgs, hasLength(2));
        expect(msgs[0].sourceText, 'Bir');
        // TR locale fix: cümle başı 'i' → 'İ' (eskiden yanlış 'Iki' üretiliyordu).
        expect(msgs[1].sourceText, 'İki');
      } finally {
        await f.dispose();
      }
    });

    test('ardışık aynı final tekrarı atlanır (4x → 1 mesaj)', () async {
      // Cihaz bug'ı (2026-06-05): Vosk EventChannel aynı finali art arda yayıyor.
      final f = await build(ttsEnabled: false);
      try {
        await f.session.start();
        for (var i = 0; i < 4; i++) {
          f.transcriber.emitFinal('merhaba dünya');
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final msgs =
            await f.repo.listMessagesForSession(f.session.activeSessionId!);
        expect(msgs, hasLength(1));
        expect(f.translation.translateCallCount, 1);
      } finally {
        await f.dispose();
      }
    });

    test('non-ardışık tekrar geçer (A, B, A → 3 mesaj)', () async {
      final f = await build(ttsEnabled: false);
      try {
        await f.session.start();
        f.transcriber.emitFinal('bir');
        f.transcriber.emitFinal('iki');
        f.transcriber.emitFinal('bir');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final msgs =
            await f.repo.listMessagesForSession(f.session.activeSessionId!);
        expect(msgs, hasLength(3));
      } finally {
        await f.dispose();
      }
    });

    test('end() başlık yazar, session kapatır, id döner, transcriber durur',
        () async {
      final gen = FakeTitleGenerator('Doğrusal Cebir');
      final f = await build(titleGenerator: gen);
      try {
        await f.session.start();
        final id = f.session.activeSessionId!;
        // Boş oturum end()'de silinir (Mehmet 2026-06-11) → mesaj ekle ki kalsın.
        await f.repo.appendMessage(
          sessionId: id,
          speakerLanguage: 'en',
          sourceText: 'linear algebra lecture',
          translatedText: 'doğrusal cebir dersi',
        );
        final returned = await f.session.end();

        expect(returned, id);
        expect(f.transcriber.stopped, isTrue);
        expect(gen.callCount, 1);
        expect(f.session.activeSessionId, isNull);

        final s = await f.repo.getSession(id);
        expect(s!.title, 'Doğrusal Cebir');
        expect(s.endedAt, isNotNull);
      } finally {
        await f.dispose();
      }
    });

    test('end() boş oturumu siler ve null döner (Mehmet 2026-06-11)', () async {
      final gen = FakeTitleGenerator('kullanılmamalı');
      final f = await build(titleGenerator: gen);
      try {
        await f.session.start();
        final id = f.session.activeSessionId!;
        final returned = await f.session.end();

        expect(returned, isNull);
        expect(gen.callCount, 0); // silinen oturum için başlık üretilmez
        expect(await f.repo.getSession(id), isNull);
      } finally {
        await f.dispose();
      }
    });

    test('end() sonrası gelen final işlenmez', () async {
      final f = await build(ttsEnabled: false);
      try {
        await f.session.start();
        final id = f.session.activeSessionId!;
        await f.session.end();
        // end() finals aboneliğini iptal etti + _stopping true → bu final yutulur.
        f.transcriber.emitFinal('geç gelen');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final msgs = await f.repo.listMessagesForSession(id);
        expect(msgs, isEmpty);
      } finally {
        await f.dispose();
      }
    });
  });
}
