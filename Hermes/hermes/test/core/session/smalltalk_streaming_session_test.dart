import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/database/app_database.dart';
import 'package:hermes/core/engines/stt/dual_vosk_streaming_controller.dart';
import 'package:hermes/core/engines/stt/whisper_langid_transcriber.dart';
import 'package:hermes/core/engines/translation/translation_engine.dart';
import 'package:hermes/core/engines/tts/tts_engine.dart';
import 'package:hermes/core/repositories/conversation_repository.dart';
import 'package:hermes/core/session/smalltalk_streaming_session.dart';

class FakeDualTranscriber implements DualTranscriber {
  final _partials = StreamController<String>.broadcast();
  final _finals = StreamController<DualTranscript>.broadcast();
  bool started = false;
  bool stopped = false;

  @override
  Stream<String> get partials => _partials.stream;
  @override
  Stream<DualTranscript> get finals => _finals.stream;
  @override
  Future<void> load() async {}
  @override
  Future<void> start() async => started = true;
  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> dispose() async {
    if (!_partials.isClosed) await _partials.close();
    if (!_finals.isClosed) await _finals.close();
  }

  void emitFinal(DualTranscript d) => _finals.add(d);
}

class FakeTranslationEngine implements TranslationEngine {
  String? lastFrom;
  String? lastTo;
  int calls = 0;
  @override
  String get engineName => 'fake';
  @override
  bool get isOfflineCapable => true;
  @override
  Future<void> ensureModelLoaded(String f, String t) async {}
  @override
  Future<String> translate(
    String text,
    String from,
    String to, {
    List<TranslationTurn> context = const [],
  }) async {
    calls++;
    lastFrom = from;
    lastTo = to;
    return '[$from→$to] $text';
  }

  @override
  Future<bool> isLanguageReady(String c) async => true;
  @override
  int estimatedDownloadSizeMb(String c) => 0;
  @override
  Future<void> downloadLanguage(String c) async {}
  @override
  Future<void> deleteLanguage(String c) async {}
  @override
  Future<void> dispose() async {}
}

class FakeTtsEngine implements TtsEngine {
  final List<String> spoken = [];
  final List<String> spokenLang = [];
  @override
  String get engineName => 'fake';
  @override
  bool get isOfflineCapable => true;
  @override
  bool get isSpeaking => false;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> speak(String text, String lang) async {
    spoken.add(text);
    spokenLang.add(lang);
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

DualTranscript _d({
  String m = '',
  double mc = 0,
  String l = '',
  double lc = 0,
}) =>
    DualTranscript(masterText: m, masterConf: mc, localText: l, localConf: lc);

void main() {
  group('SmallTalkStreamingSession.route', () {
    test('ikisi de boş → null', () {
      expect(SmallTalkStreamingSession.route(_d()), isNull);
    });
    test('local boş → master', () {
      expect(SmallTalkStreamingSession.route(_d(m: 'merhaba', mc: 0.4)),
          (true, 'merhaba'));
    });
    test('master boş → local', () {
      expect(SmallTalkStreamingSession.route(_d(l: 'hello', lc: 0.4)),
          (false, 'hello'));
    });
    test('güven yüksek olan kazanır (local)', () {
      expect(
        SmallTalkStreamingSession.route(
            _d(m: 'gibberish', mc: 0.3, l: 'hello', lc: 0.9)),
        (false, 'hello'),
      );
    });
    test('eşit güven → master (öncelik)', () {
      expect(
        SmallTalkStreamingSession.route(
            _d(m: 'merhaba', mc: 0.7, l: 'hello', lc: 0.7)),
        (true, 'merhaba'),
      );
    });
  });

  group('WhisperLangIdTranscriber.slotFor (full mod)', () {
    test('master dili → 1', () {
      expect(WhisperLangIdTranscriber.slotFor('tr', 'tr', 'en'), 1);
    });
    test('local dili → -1', () {
      expect(WhisperLangIdTranscriber.slotFor('en', 'tr', 'en'), -1);
    });
    test('alakasız dil → 0 (drop)', () {
      expect(WhisperLangIdTranscriber.slotFor('de', 'tr', 'en'), 0);
    });
    test('null → 0', () {
      expect(WhisperLangIdTranscriber.slotFor(null, 'tr', 'en'), 0);
    });
  });

  group('SmallTalkStreamingSession pipeline', () {
    late AppDatabase db;
    late ConversationRepository repo;
    late FakeDualTranscriber tr;
    late FakeTranslationEngine trans;
    late FakeTtsEngine tts;

    Future<SmallTalkStreamingSession> build({bool narration = true}) async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = ConversationRepository(db);
      tr = FakeDualTranscriber();
      trans = FakeTranslationEngine();
      tts = FakeTtsEngine();
      final s = SmallTalkStreamingSession(
        transcriber: tr,
        repository: repo,
        translation: trans,
        tts: tts,
        masterLang: 'tr',
        localLang: 'en',
        narrationEnabled: narration,
      );
      await s.start();
      return s;
    }

    tearDown(() async => db.close());

    test('start lecture-benzeri voiceTranslator/full session açar', () async {
      final s = await build();
      final row = await repo.getSession(s.activeSessionId!);
      expect(row!.mode, SessionMode.voiceTranslator.dbValue);
      expect(row.quality, SessionQuality.full.dbValue);
      expect(tr.started, isTrue);
      await s.dispose();
    });

    test('master konuşur → sağ mesaj, tr→en, otomatik TTS YOK', () async {
      final s = await build();
      final first = s.messages.first;
      tr.emitFinal(_d(m: 'merhaba', mc: 0.9, l: 'gib', lc: 0.2));
      final msg = await first.timeout(const Duration(seconds: 3));
      expect(msg.isMaster, isTrue);
      expect(msg.transcript, 'Merhaba'); // filler büyütür
      expect(msg.translation, '[tr→en] Merhaba');
      expect(msg.translationLang, 'en');
      expect(trans.lastFrom, 'tr');
      expect(trans.lastTo, 'en');
      expect(tts.spoken, isEmpty); // master otomatik seslendirilmez
      await s.dispose();
    });

    test('local konuşur → sol mesaj, en→tr, narration açıksa otomatik TTS',
        () async {
      final s = await build(narration: true);
      final first = s.messages.first;
      tr.emitFinal(_d(m: 'gib', mc: 0.2, l: 'hello', lc: 0.9));
      final msg = await first.timeout(const Duration(seconds: 3));
      expect(msg.isMaster, isFalse);
      expect(msg.translation, '[en→tr] Hello');
      expect(msg.translationLang, 'tr');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tts.spoken, ['[en→tr] Hello']); // master'a otomatik
      await s.dispose();
    });

    test('narration kapalı → local otomatik TTS yok', () async {
      final s = await build(narration: false);
      final first = s.messages.first;
      tr.emitFinal(_d(l: 'hello', lc: 0.9));
      await first.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tts.spoken, isEmpty);
      await s.dispose();
    });

    test('playMessage(local) narration kapatır + seslendirir', () async {
      final s = await build(narration: true);
      expect(s.narrationActive, isTrue);
      await s.playMessage(const SmallTalkMessage(
        isMaster: false,
        transcript: 'hello',
        translation: 'merhaba',
        translationLang: 'tr',
      ));
      expect(tts.spoken, ['merhaba']);
      expect(s.narrationActive, isFalse);
      await s.dispose();
    });

    test('ardışık aynı seçilen metin tekrarı atlanır', () async {
      final s = await build(narration: false);
      tr.emitFinal(_d(m: 'merhaba', mc: 0.9));
      tr.emitFinal(_d(m: 'merhaba', mc: 0.9));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final msgs = await repo.listMessagesForSession(s.activeSessionId!);
      expect(msgs, hasLength(1));
      await s.dispose();
    });

    test('histerezis: belirsiz güven farkında son konuşanda kalır', () async {
      final s = await build(narration: false);
      // 1) master net konuşur → master.
      tr.emitFinal(_d(m: 'merhaba', mc: 0.9, l: 'x', lc: 0.2));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // 2) belirsiz (local hafif yüksek ama fark < 0.15) → master'da kal.
      tr.emitFinal(_d(m: 'devam', mc: 0.50, l: 'bb', lc: 0.55));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final msgs = await repo.listMessagesForSession(s.activeSessionId!);
      expect(msgs, hasLength(2));
      expect(msgs[1].speakerLanguage, 'tr'); // histerezis master'da tuttu
      await s.dispose();
    });

    test('end başlık yazar + session kapatır + id döner', () async {
      final s = await build();
      final id = s.activeSessionId!;
      // Boş oturum end()'de silinir (Mehmet 2026-06-11) → mesaj ekle ki kalsın.
      await repo.appendMessage(
        sessionId: id,
        speakerLanguage: 'tr',
        sourceText: 'merhaba',
        translatedText: 'hello',
      );
      final ret = await s.end();
      expect(ret, id);
      expect(tr.stopped, isTrue);
      final row = await repo.getSession(id);
      expect(row!.endedAt, isNotNull);
      expect(row.title, isNotNull);
      await s.dispose();
    });

    test('end boş oturumu siler ve null döner (Mehmet 2026-06-11)', () async {
      final s = await build();
      final id = s.activeSessionId!;
      final ret = await s.end();
      expect(ret, isNull);
      expect(await repo.getSession(id), isNull);
      await s.dispose();
    });
  });
}
