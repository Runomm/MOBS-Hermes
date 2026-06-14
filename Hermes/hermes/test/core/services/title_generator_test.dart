import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/database/app_database.dart';
import 'package:hermes/core/repositories/conversation_repository.dart';
import 'package:hermes/core/services/title_generator.dart';

/// Online üreticiyi taklit eden fake — verilen davranışı uygular.
class _FakeOnline implements TitleGenerator {
  _FakeOnline({this.result, this.throwIt = false});
  final String? result;
  final bool throwIt;
  int callCount = 0;

  @override
  Future<String> generate({
    required SessionMode mode,
    required List<MessageRow> messages,
    required DateTime startedAt,
  }) async {
    callCount++;
    if (throwIt) throw Exception('online patladı');
    return result ?? '';
  }
}

void main() {
  group('TimestampFallbackGenerator', () {
    test('format: YYYY-MM-DD-HH-MM-SS tarihli {mod} konuşması', () {
      final title = TimestampFallbackGenerator.titleFor(
        SessionMode.pushToTalk,
        DateTime(2026, 5, 31, 21, 4, 8),
      );
      expect(title, '2026-05-31-21-04-08 tarihli bas konuş konuşması');
    });

    test('mod adları doğru', () {
      expect(
          TimestampFallbackGenerator.modeName(SessionMode.lecture), 'konferans');
      expect(
        TimestampFallbackGenerator.modeName(SessionMode.voiceTranslator),
        'smalltalk',
      );
      expect(
        TimestampFallbackGenerator.modeName(SessionMode.pushToTalk),
        'bas konuş',
      );
    });

    test('generate() titleFor ile aynı sonucu verir', () async {
      const gen = TimestampFallbackGenerator();
      final dt = DateTime(2026, 1, 2, 3, 4, 5);
      final got = await gen.generate(
        mode: SessionMode.lecture,
        messages: const [],
        startedAt: dt,
      );
      expect(got, TimestampFallbackGenerator.titleFor(SessionMode.lecture, dt));
    });
  });

  group('HybridTitleGenerator', () {
    final dt = DateTime(2026, 5, 31, 12, 0, 0);

    test('online null → timestamp fallback', () async {
      const gen = HybridTitleGenerator();
      final got = await gen.generate(
        mode: SessionMode.pushToTalk,
        messages: const [],
        startedAt: dt,
      );
      expect(got, TimestampFallbackGenerator.titleFor(SessionMode.pushToTalk, dt));
    });

    test('online geçerli başlık → kullanılır (trim\'li)', () async {
      final online = _FakeOnline(result: '  kahve siparişi  ');
      final gen = HybridTitleGenerator(online: online);
      final got = await gen.generate(
        mode: SessionMode.pushToTalk,
        messages: const [],
        startedAt: dt,
      );
      expect(got, 'kahve siparişi');
      expect(online.callCount, 1);
    });

    test('online boş döner → fallback', () async {
      final online = _FakeOnline(result: '   ');
      final gen = HybridTitleGenerator(online: online);
      final got = await gen.generate(
        mode: SessionMode.lecture,
        messages: const [],
        startedAt: dt,
      );
      expect(got, TimestampFallbackGenerator.titleFor(SessionMode.lecture, dt));
    });

    test('online fırlatır → fallback (akış bozulmaz)', () async {
      final online = _FakeOnline(throwIt: true);
      final gen = HybridTitleGenerator(online: online);
      final got = await gen.generate(
        mode: SessionMode.lecture,
        messages: const [],
        startedAt: dt,
      );
      expect(got, TimestampFallbackGenerator.titleFor(SessionMode.lecture, dt));
      expect(online.callCount, 1);
    });
  });
}
