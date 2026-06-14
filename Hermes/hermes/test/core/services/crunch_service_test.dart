import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/crunch_service.dart';

void main() {
  // Yeni promptlara göre deterministik fake (özet/başlık). Çeviri ayrı `translate`.
  String fakeRun(String prompt) {
    if (prompt.contains('descriptive title')) return 'Test Title';
    if (prompt.contains('single concise summary')) return 'REDUCED';
    if (prompt.contains('Key points:')) return 'NOTE';
    return '';
  }

  group('translateTranscript (Faz A — Derinlemesine Çevir)', () {
    test('2 chunk → 2 çeviri çağrısı, birleşik döner', () async {
      final order = <String>[];
      final svc = CrunchService(
        translate: (t, s, g) async {
          order.add('t');
          return 'TR';
        },
        run: (_) async => '',
        maxCharsPerChunk: 10,
      );
      final r = await svc.translateTranscript(
        transcripts: const ['aaaa', 'bbbb', 'cccc'],
        sourceLang: 'tr',
        targetLang: 'en',
      );
      expect(order.length, 2);
      expect(r, 'TR\n\nTR');
    });

    test('boş transkript → boş çeviri', () async {
      final svc = CrunchService(
        translate: (t, s, g) async => 'X',
        run: (_) async => '',
      );
      final r = await svc.translateTranscript(
        transcripts: const ['', '   '],
        sourceLang: 'tr',
        targetLang: 'en',
      );
      expect(r, '');
    });
  });

  group('summarize (Faz B — Özetle)', () {
    test('3 chunk → 3 not + 1 reduce + başlık', () async {
      final runCalls = <String>[];
      final svc = CrunchService(
        translate: (t, s, g) async => t,
        run: (p) async {
          runCalls.add(p);
          return fakeRun(p);
        },
        maxCharsPerChunk: 2,
      );
      // 'aa bb cc' her kelime 2 char → 3 chunk.
      final r = await svc.summarize(translationText: 'aa bb cc', targetLang: 'en');
      int c(String m) => runCalls.where((p) => p.contains(m)).length;
      expect(c('Key points:'), 3);
      expect(c('single concise summary'), 1); // 3 not → 1 reduce
      expect(c('descriptive title'), 1);
      expect(r.summary, 'REDUCED');
      expect(r.title, 'Test Title');
    });

    test('tek chunk → reduce yok, not doğrudan özet', () async {
      final runCalls = <String>[];
      final svc = CrunchService(
        translate: (t, s, g) async => t,
        run: (p) async {
          runCalls.add(p);
          return fakeRun(p);
        },
      );
      final r = await svc.summarize(translationText: 'kısa', targetLang: 'en');
      expect(
          runCalls.where((p) => p.contains('single concise summary')).isEmpty,
          isTrue);
      expect(r.summary, 'NOTE');
    });

    test('boş çeviri → varsayılan başlık "Konuşma", boş özet', () async {
      final svc = CrunchService(
        translate: (t, s, g) async => t,
        run: (p) async => fakeRun(p),
      );
      final r = await svc.summarize(translationText: '   ', targetLang: 'en');
      expect(r.title, 'Konuşma');
      expect(r.summary, '');
    });

    test('başlık tırnak/sonbaşı noktalamadan temizlenir', () async {
      final svc = CrunchService(
        translate: (t, s, g) async => t,
        run: (p) async {
          if (p.contains('descriptive title')) return '"Doğrusal Cebir".\n(x)';
          if (p.contains('Key points:')) return 'NOTE';
          return '';
        },
      );
      final r = await svc.summarize(translationText: 'bir cümle', targetLang: 'en');
      expect(r.title, 'Doğrusal Cebir');
    });

    test('ilerleme monoton artar ve 1.0 ile biter', () async {
      final progress = <double>[];
      final svc = CrunchService(
        translate: (t, s, g) async => t,
        run: (p) async => fakeRun(p),
        maxCharsPerChunk: 2,
      );
      await svc.summarize(
          translationText: 'aa bb cc dd',
          targetLang: 'en',
          onProgress: progress.add);
      expect(progress.last, 1.0);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    });
  });

  group('crunch (tek-adım — de-risk uyumluluğu)', () {
    test('çeviri → afterTranslate → özet sırası korunur', () async {
      final order = <String>[];
      var after = false;
      final svc = CrunchService(
        translate: (t, s, g) async {
          order.add('translate');
          return 'TR';
        },
        run: (p) async {
          order.add('run');
          return fakeRun(p);
        },
        afterTranslate: () async {
          after = true;
          order.add('after');
        },
        maxCharsPerChunk: 10,
      );
      final r = await svc.crunch(
        transcripts: const ['aaaa', 'bbbb', 'cccc'],
        sourceLang: 'tr',
        targetLang: 'en',
      );
      final firstRun = order.indexOf('run');
      expect(order.lastIndexOf('translate'), lessThan(firstRun));
      expect(after, isTrue);
      expect(order.indexOf('after'), lessThan(firstRun));
      expect(r.fullTranslation, 'TR\n\nTR');
      expect(r.title, 'Test Title');
    });

    test('boş → "Konuşma" başlık, boş çeviri, ilerleme 1.0, afterTranslate', () async {
      final progress = <double>[];
      var after = false;
      final svc = CrunchService(
        translate: (t, s, g) async => 'TR',
        run: (p) async => fakeRun(p),
        afterTranslate: () async => after = true,
      );
      final r = await svc.crunch(
        transcripts: const ['', '   '],
        sourceLang: 'tr',
        targetLang: 'en',
        onProgress: progress.add,
      );
      expect(r.title, 'Konuşma');
      expect(r.fullTranslation, '');
      expect(progress.last, 1.0);
      expect(after, isTrue);
    });
  });
}
