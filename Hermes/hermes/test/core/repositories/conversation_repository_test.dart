import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/database/app_database.dart';
import 'package:hermes/core/repositories/conversation_repository.dart';

void main() {
  late AppDatabase db;
  late ConversationRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ConversationRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ConversationRepository — temel akış', () {
    test('createSession yeni satır ekler ve startedAt set eder', () async {
      final session = await repo.createSession(
        mode: SessionMode.fast,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );

      expect(session.id, isPositive);
      expect(session.mode, 'fast');
      expect(session.sourceLanguage, 'tr');
      expect(session.targetLanguage, 'en');
      expect(session.endedAt, isNull);
    });

    test('appendMessage oturuma mesaj iliştirir, sıra korunur', () async {
      final session = await repo.createSession(
        mode: SessionMode.full,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );

      await repo.appendMessage(
        sessionId: session.id,
        speakerLanguage: 'tr',
        sourceText: 'Merhaba',
        translatedText: 'Hello',
      );
      await repo.appendMessage(
        sessionId: session.id,
        speakerLanguage: 'en',
        sourceText: 'How are you?',
        translatedText: 'Nasılsın?',
      );

      final messages = await repo.listMessagesForSession(session.id);
      expect(messages, hasLength(2));
      expect(messages[0].sourceText, 'Merhaba');
      expect(messages[1].sourceText, 'How are you?');
      expect(messages[1].translatedText, 'Nasılsın?');
    });

    test('translatedText null kabul edilir (çeviri başarısız senaryosu)',
        () async {
      final session = await repo.createSession(
        mode: SessionMode.full,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );

      final msg = await repo.appendMessage(
        sessionId: session.id,
        speakerLanguage: 'tr',
        sourceText: 'Ham metin',
      );

      expect(msg.translatedText, isNull);
    });

    test('countMessages doğru sayım döner', () async {
      final session = await repo.createSession(
        mode: SessionMode.fast,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );

      expect(await repo.countMessages(session.id), 0);

      for (var i = 0; i < 3; i++) {
        await repo.appendMessage(
          sessionId: session.id,
          speakerLanguage: 'tr',
          sourceText: 'satır $i',
        );
      }

      expect(await repo.countMessages(session.id), 3);
    });

    test('getSession bilinmeyen id için null', () async {
      expect(await repo.getSession(9999), isNull);
    });

    test('endSession endedAt alanini doldurur', () async {
      final session = await repo.createSession(
        mode: SessionMode.fast,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );

      await repo.endSession(session.id);

      final reloaded = await repo.getSession(session.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.endedAt, isNotNull);
    });

    test('listAllSessions en yeni önce sırasıyla döner', () async {
      final s1 = await repo.createSession(
        mode: SessionMode.fast,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );
      final s2 = await repo.createSession(
        mode: SessionMode.full,
        sourceLanguage: 'tr',
        targetLanguage: 'de',
      );

      // startedAt SQLite'da saniye granularitesinde — aynı saniyede açılan
      // iki oturum için id desc ile tiebreak yapıyoruz.
      final all = await repo.listAllSessions();
      expect(all.map((s) => s.id).toList(), [s2.id, s1.id]);
    });

    test('cascade delete: oturum silinince mesajları da gider', () async {
      final session = await repo.createSession(
        mode: SessionMode.fast,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );
      await repo.appendMessage(
        sessionId: session.id,
        speakerLanguage: 'tr',
        sourceText: 'silinecek',
      );

      await (db.delete(db.sessions)..where((s) => s.id.equals(session.id)))
          .go();

      final remaining = await repo.listMessagesForSession(session.id);
      expect(remaining, isEmpty);
    });
  });

  group('SessionMode enum', () {
    test('dbValue stringi enum adıyla eşleşir', () {
      expect(SessionMode.fast.dbValue, 'fast');
      expect(SessionMode.full.dbValue, 'full');
    });

    test('fromDbValue round-trip', () {
      expect(SessionMode.fromDbValue('fast'), SessionMode.fast);
      expect(SessionMode.fromDbValue('full'), SessionMode.full);
    });

    test('fromDbValue bilinmeyen string için fallback', () {
      expect(SessionMode.fromDbValue('garbage'), SessionMode.full);
    });
  });
}
