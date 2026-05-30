import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/filler_cleaner.dart';

void main() {
  const cleaner = FillerCleaner();

  group('FillerCleaner — level: off', () {
    test('Hiçbir kelime silinmez, sadece whitespace normalize edilir', () {
      final result = cleaner.clean(
        'Ee,  yani  bugün  hava güzel.',
        language: 'tr',
        level: FillerLevel.off,
      );
      expect(result, 'Ee, yani bugün hava güzel.');
    });

    test('Trim ve çoklu boşluk temizleme', () {
      final result = cleaner.clean(
        '   merhaba   nasılsın   ',
        language: 'tr',
        level: FillerLevel.off,
      );
      expect(result, 'merhaba nasılsın');
    });
  });

  group('FillerCleaner — TR conservative', () {
    test('Cümle başındaki "Ee," yutulur ve sonraki harf büyür', () {
      final result = cleaner.clean(
        'Ee, bugün hava çok güzel.',
        language: 'tr',
        level: FillerLevel.conservative,
      );
      expect(result, 'Bugün hava çok güzel.');
    });

    test('Conservative seviyede "yani" yutulmaz', () {
      final result = cleaner.clean(
        'Yani bugün sinema gideceğiz.',
        language: 'tr',
        level: FillerLevel.conservative,
      );
      expect(result, 'Yani bugün sinema gideceğiz.');
    });

    test('"Mmm" ve "Aaa" jeneriktir, conservative\'de temizlenir', () {
      final result = cleaner.clean(
        'Mmm, aaa düşünüyorum.',
        language: 'tr',
        level: FillerLevel.conservative,
      );
      expect(result, 'Düşünüyorum.');
    });

    test('Cümle ortasındaki "ee" yutulur', () {
      final result = cleaner.clean(
        'Bugün, ee, sinema gideceğiz.',
        language: 'tr',
        level: FillerLevel.conservative,
      );
      expect(result, 'Bugün, sinema gideceğiz.');
    });
  });

  group('FillerCleaner — TR aggressive', () {
    test('Söz kalıpları temizlenir', () {
      // "şey," yutulurken sonraki virgül de filler suffix'i olarak yutulur,
      // bu yüzden "bugün ... sinema" arasında virgül kalmaz (akıcı).
      final result = cleaner.clean(
        'Ee, yani bugün şey, sinema mı gideceğiz hani?',
        language: 'tr',
        level: FillerLevel.aggressive,
      );
      expect(result, 'Bugün sinema mı gideceğiz?');
    });

    test('Aggressive "işte" ve "falan" da yer', () {
      final result = cleaner.clean(
        'İşte böyle bir şey falan oldu.',
        language: 'tr',
        level: FillerLevel.aggressive,
      );
      expect(result, 'Böyle bir oldu.');
    });
  });

  group('FillerCleaner — EN conservative', () {
    test('"Um" ve "uh" temizlenir', () {
      final result = cleaner.clean(
        'Um, I think uh we should go.',
        language: 'en',
        level: FillerLevel.conservative,
      );
      expect(result, 'I think we should go.');
    });

    test('Conservative seviyede "you know" yutulmaz', () {
      final result = cleaner.clean(
        'You know, this is important.',
        language: 'en',
        level: FillerLevel.conservative,
      );
      expect(result, 'You know, this is important.');
    });
  });

  group('FillerCleaner — EN aggressive', () {
    test('"you know" ve "i mean" yutulur', () {
      final result = cleaner.clean(
        'You know, I mean, we should kinda go now.',
        language: 'en',
        level: FillerLevel.aggressive,
      );
      expect(result, 'We should go now.');
    });
  });

  group('FillerCleaner — edge cases', () {
    test('Boş string güvenli', () {
      expect(cleaner.clean('', language: 'tr'), '');
    });

    test('Sadece boşluklardan oluşan input', () {
      expect(cleaner.clean('     ', language: 'tr'), '');
    });

    test('Bilinmeyen dil için sadece whitespace normalize edilir', () {
      final result = cleaner.clean(
        '  Hola,  ee  como  estás?  ',
        language: 'es',
        level: FillerLevel.aggressive,
      );
      // 'ee' generic değil TR'ye özgü; ES için sadece whitespace temizliği +
      // jenerik mmm/aaa kontrolü. 'ee' aynen kalır.
      expect(result, 'Hola, ee como estás?');
    });

    test('Cümle başı büyük harf — Türkçe karakter', () {
      final result = cleaner.clean(
        'ee, şirket toplantısı vardı.',
        language: 'tr',
        level: FillerLevel.conservative,
      );
      expect(result, 'Şirket toplantısı vardı.');
    });

    test('Noktalama öncesi boşluk silinir', () {
      final result = cleaner.clean(
        'Bugün ,  yarın  ve   sonra  .',
        language: 'tr',
        level: FillerLevel.off,
      );
      expect(result, 'Bugün, yarın ve sonra.');
    });
  });
}
