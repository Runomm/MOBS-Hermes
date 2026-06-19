import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/engines/language_id/heuristic_language_detector.dart';

void main() {
  group('HeuristicLanguageDetector.score (saf/senkron)', () {
    test('Türkçe cümle tr↔en arasında tr seçer', () {
      final r = HeuristicLanguageDetector.score(
        'Merhaba nasılsın bugün hava çok güzel',
        ['tr', 'en'],
      );
      expect(r, isNotNull);
      expect(r!.languageCode, 'tr');
    });

    test('İngilizce cümle tr↔en arasında en seçer', () {
      final r = HeuristicLanguageDetector.score(
        'Hello how are you today, the weather is nice',
        ['tr', 'en'],
      );
      expect(r, isNotNull);
      expect(r!.languageCode, 'en');
    });

    test('Türkçe-özel karakterler güçlü sinyal (kısa sözce)', () {
      final r = HeuristicLanguageDetector.score('Günaydın, teşekkürler', ['tr', 'en']);
      expect(r?.languageCode, 'tr');
    });

    test('İspanyolca es↔en arasında es seçer', () {
      final r = HeuristicLanguageDetector.score(
        'Hola, ¿cómo estás? muy bien gracias',
        ['es', 'en'],
      );
      expect(r?.languageCode, 'es');
    });

    test('Almanca de↔en arasında de seçer', () {
      final r = HeuristicLanguageDetector.score(
        'Hallo, wie geht es dir? ich bin gut danke',
        ['de', 'en'],
      );
      expect(r?.languageCode, 'de');
    });

    test('boş metin → null', () {
      expect(HeuristicLanguageDetector.score('   ', ['tr', 'en']), isNull);
    });

    test('hiç im yoksa (anlamsız) → null', () {
      expect(HeuristicLanguageDetector.score('xyzq wprq zzz', ['tr', 'en']), isNull);
    });

    test('aday yoksa → null', () {
      expect(HeuristicLanguageDetector.score('hello world', []), isNull);
    });

    test('confidence 0.5..1 aralığında', () {
      final r = HeuristicLanguageDetector.score(
        'the and is you to of in it',
        ['tr', 'en'],
      );
      expect(r, isNotNull);
      expect(r!.confidence, inInclusiveRange(0.5, 1.0));
    });
  });

  group('HeuristicLanguageDetector.detect (LanguageDetector arayüzü)', () {
    test('iki dilli kurulum → doğru dili döner', () async {
      final d = HeuristicLanguageDetector(candidates: ['tr', 'en']);
      final r = await d.detect('bir şey söyleyeyim ve bu çok önemli',
          minConfidence: 0.0);
      expect(r?.languageCode, 'tr');
      await d.dispose();
    });

    test('minConfidence eşiği uygulanır (karışık sinyal düşük güven)', () async {
      final d = HeuristicLanguageDetector(candidates: ['tr', 'en']);
      // Her iki dil de birer sinyal verir → conf ~0.5, yüksek eşikte null.
      final r = await d.detect('the ve', minConfidence: 0.99);
      expect(r, isNull);
      await d.dispose();
    });

    test('isOfflineCapable true, native bağımlılık yok', () {
      final d = HeuristicLanguageDetector(candidates: ['tr', 'en']);
      expect(d.isOfflineCapable, isTrue);
    });
  });
}
