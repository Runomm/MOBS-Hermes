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
        mode: SessionMode.voiceTranslator,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );

      expect(session.id, isPositive);
      expect(session.mode, 'voiceTranslator');
      expect(session.quality, 'fast'); // varsayılan
      expect(session.title, isNull);
      expect(session.sourceLanguage, 'tr');
      expect(session.targetLanguage, 'en');
      expect(session.endedAt, isNull);
    });

    test('createSession explicit quality parametresini saklar', () async {
      final session = await repo.createSession(
        mode: SessionMode.lecture,
        quality: SessionQuality.full,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );

      expect(session.mode, 'lecture');
      expect(session.quality, 'full');
    });

    test('appendMessage oturuma mesaj iliştirir, sıra korunur', () async {
      final session = await repo.createSession(
        mode: SessionMode.lecture,
        quality: SessionQuality.full,
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
        mode: SessionMode.lecture,
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
        mode: SessionMode.voiceTranslator,
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
        mode: SessionMode.voiceTranslator,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );

      await repo.endSession(session.id);

      final reloaded = await repo.getSession(session.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.endedAt, isNotNull);
    });

    test('setTitle başlığı yazar, üzerine yazar (6r-f)', () async {
      final session = await repo.createSession(
        mode: SessionMode.pushToTalk,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );
      expect(session.title, isNull);

      await repo.setTitle(session.id, 'ilk başlık');
      expect((await repo.getSession(session.id))!.title, 'ilk başlık');

      await repo.setTitle(session.id, 'güncellenmiş başlık');
      expect((await repo.getSession(session.id))!.title, 'güncellenmiş başlık');
    });

    test('listAllSessions en yeni önce sırasıyla döner', () async {
      final s1 = await repo.createSession(
        mode: SessionMode.voiceTranslator,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );
      final s2 = await repo.createSession(
        mode: SessionMode.pushToTalk,
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
        mode: SessionMode.voiceTranslator,
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

  group('Konferans crunch + arşiv (v3)', () {
    test('yeni oturumda crunch alanları null', () async {
      final s = await repo.createSession(
        mode: SessionMode.lecture,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );
      expect(s.crunchedAt, isNull);
      expect(s.crunchTitle, isNull);
      expect(s.crunchTranslation, isNull);
      expect(s.crunchSummary, isNull);
    });

    test('setCrunchResult başlık/çeviri/özet + crunchedAt yazar', () async {
      final s = await repo.createSession(
        mode: SessionMode.lecture,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );

      await repo.setCrunchResult(
        s.id,
        title: 'Doğrusal Cebir 1',
        translation: 'Full translation text',
        summary: 'Önemli noktalar: ...',
      );

      final r = (await repo.getSession(s.id))!;
      expect(r.crunchedAt, isNotNull);
      expect(r.crunchTitle, 'Doğrusal Cebir 1');
      expect(r.crunchTranslation, 'Full translation text');
      expect(r.crunchSummary, 'Önemli noktalar: ...');
    });

    test('listSessionsForMode yalnız ilgili modu, en yeni önce döner',
        () async {
      final lec1 = await repo.createSession(
        mode: SessionMode.lecture,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );
      await repo.createSession(
        mode: SessionMode.pushToTalk,
        sourceLanguage: 'tr',
        targetLanguage: 'de',
      );
      final lec2 = await repo.createSession(
        mode: SessionMode.lecture,
        sourceLanguage: 'en',
        targetLanguage: 'tr',
      );

      final lectures = await repo.listSessionsForMode(SessionMode.lecture);
      expect(lectures.map((s) => s.id).toList(), [lec2.id, lec1.id]);
      expect(lectures.every((s) => s.mode == 'lecture'), isTrue);
    });

    test('deleteSession oturumu + mesajlarını siler', () async {
      final s = await repo.createSession(
        mode: SessionMode.lecture,
        sourceLanguage: 'tr',
        targetLanguage: 'en',
      );
      await repo.appendMessage(
        sessionId: s.id,
        speakerLanguage: 'tr',
        sourceText: 'gidecek',
      );

      await repo.deleteSession(s.id);

      expect(await repo.getSession(s.id), isNull);
      expect(await repo.listMessagesForSession(s.id), isEmpty);
    });
  });

  group('SessionMode enum (6r-b, 3 değerli)', () {
    test('dbValue stringi enum adıyla eşleşir', () {
      expect(SessionMode.lecture.dbValue, 'lecture');
      expect(SessionMode.voiceTranslator.dbValue, 'voiceTranslator');
      expect(SessionMode.pushToTalk.dbValue, 'pushToTalk');
    });

    test('fromDbValue round-trip — 3 yeni değer', () {
      expect(SessionMode.fromDbValue('lecture'), SessionMode.lecture);
      expect(
        SessionMode.fromDbValue('voiceTranslator'),
        SessionMode.voiceTranslator,
      );
      expect(SessionMode.fromDbValue('pushToTalk'), SessionMode.pushToTalk);
    });

    test(
        'fromDbValue eski v1 fast/full değerlerini yeni evrene map\'ler '
        '(savunma katmanı, migration sonrası DB\'de bulunmamalı)', () {
      // Migration runtime'da satırları kalıcı olarak günceller; bu fallback
      // sadece tohum dosya / harici satır gelirse devreye girer.
      expect(SessionMode.fromDbValue('fast'), SessionMode.voiceTranslator);
      expect(SessionMode.fromDbValue('full'), SessionMode.lecture);
    });

    test('fromDbValue bilinmeyen string için voiceTranslator fallback', () {
      expect(SessionMode.fromDbValue('garbage'), SessionMode.voiceTranslator);
    });
  });

  group('SessionQuality enum (6r-b, yeni)', () {
    test('dbValue stringi enum adıyla eşleşir', () {
      expect(SessionQuality.fast.dbValue, 'fast');
      expect(SessionQuality.full.dbValue, 'full');
      expect(SessionQuality.fullPlus.dbValue, 'fullPlus'); // F2 3. katman
    });

    test('fromDbValue round-trip', () {
      expect(SessionQuality.fromDbValue('fast'), SessionQuality.fast);
      expect(SessionQuality.fromDbValue('full'), SessionQuality.full);
      expect(
          SessionQuality.fromDbValue('fullPlus'), SessionQuality.fullPlus);
    });

    test('fromDbValue bilinmeyen string için fast fallback', () {
      expect(SessionQuality.fromDbValue('garbage'), SessionQuality.fast);
    });
  });

  group('Schema v1 → v2 migration SQL davranışı', () {
    // Burada gerçek schema upgrade tetiklenmiyor (Drift Migrator API'sini
    // wire'lamak büyük bir scope). Onun yerine v2 tablosuna eski v1
    // değerleriyle satır enjekte ediyoruz, sonra migration UPDATE'lerini
    // birebir çalıştırıp sonuç doğru mu doğruluyoruz. Bu, migration
    // logic'inin asıl riski olan SQL sıralaması + mapping doğruluğunu
    // kapsar.
    test(
        'fast satırı voiceTranslator+fast olur, full satırı lecture+full olur',
        () async {
      final mDb = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        // v1 değerleriyle eski tip iki satır — quality default 'fast' alır
        // (v2 column default).
        await mDb.customStatement(
          "INSERT INTO sessions (mode, source_language, target_language) "
          "VALUES ('fast', 'tr', 'en')",
        );
        await mDb.customStatement(
          "INSERT INTO sessions (mode, source_language, target_language) "
          "VALUES ('full', 'tr', 'de')",
        );

        // Migration SQL'leri (app_database.dart onUpgrade ile birebir).
        await mDb.customStatement(
          "UPDATE sessions SET quality = 'full' WHERE mode = 'full'",
        );
        await mDb.customStatement(
          "UPDATE sessions SET mode = 'voiceTranslator' WHERE mode = 'fast'",
        );
        await mDb.customStatement(
          "UPDATE sessions SET mode = 'lecture' WHERE mode = 'full'",
        );

        final all = await mDb.select(mDb.sessions).get();
        final byLang = {for (final s in all) s.targetLanguage: s};

        expect(byLang['en']!.mode, 'voiceTranslator');
        expect(byLang['en']!.quality, 'fast');
        expect(byLang['de']!.mode, 'lecture');
        expect(byLang['de']!.quality, 'full');
      } finally {
        await mDb.close();
      }
    });

    test('UPDATE sıralaması — quality ÖNCE mode güncellenmeli', () async {
      // Eğer mode önce remap edilirse 'full' bilgisi kaybolur,
      // quality default 'fast' kalır → yanlış sonuç. Sıralamayı tersine
      // çevirip yanlış sonuç çıktığını doğrularız (regression koruması).
      final mDb = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        await mDb.customStatement(
          "INSERT INTO sessions (mode, source_language, target_language) "
          "VALUES ('full', 'tr', 'de')",
        );

        // YANLIŞ sıralama — önce mode remap.
        await mDb.customStatement(
          "UPDATE sessions SET mode = 'lecture' WHERE mode = 'full'",
        );
        // Şimdi quality update'i hiçbir satıra match etmez (mode artık
        // 'lecture').
        await mDb.customStatement(
          "UPDATE sessions SET quality = 'full' WHERE mode = 'full'",
        );

        final row = (await mDb.select(mDb.sessions).get()).single;
        // Quality 'fast' kaldı (default) — bilgi kaybı.
        expect(row.mode, 'lecture');
        expect(
          row.quality,
          'fast',
          reason: 'mode önce remap edilirse full bilgisi kaybolur — '
              'gerçek migration\'da quality ÖNCE update edilmeli',
        );
      } finally {
        await mDb.close();
      }
    });
  });
}
