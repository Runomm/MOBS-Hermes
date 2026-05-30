import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/engines/language_id/language_detector.dart';

/// In-memory fake — testlerde ML Kit native çağrılarından kaçınmak için.
/// Interface kontratını (boş metin null, conf eşiği uygulanır) doğrular.
class _FakeLanguageDetector implements LanguageDetector {
  _FakeLanguageDetector(this._programmedResult);

  /// Tek bir programlanmış sonuç döner — gerçek tahmin yok.
  final LanguageDetectionResult? _programmedResult;

  @override
  String get engineName => 'Fake';

  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<LanguageDetectionResult?> detect(
    String text, {
    double minConfidence = 0.6,
  }) async {
    if (text.trim().isEmpty) return null;
    final r = _programmedResult;
    if (r == null) return null;
    if (r.confidence < minConfidence) return null;
    return r;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('LanguageDetectionResult', () {
    test('toString iki ondalık basamakla confidence yazdırır', () {
      const result =
          LanguageDetectionResult(languageCode: 'tr', confidence: 0.9234);
      expect(result.toString(), 'LanguageDetectionResult(tr, 0.92)');
    });

    test('alanlar atandığı gibi okunur', () {
      const result =
          LanguageDetectionResult(languageCode: 'en', confidence: 0.55);
      expect(result.languageCode, 'en');
      expect(result.confidence, closeTo(0.55, 1e-9));
    });
  });

  group('LanguageDetector interface kontratı (fake ile)', () {
    test('boş metin → null (whitespace dahil)', () async {
      final detector = _FakeLanguageDetector(
        const LanguageDetectionResult(languageCode: 'tr', confidence: 0.9),
      );
      expect(await detector.detect(''), isNull);
      expect(await detector.detect('   '), isNull);
      expect(await detector.detect('\n\t'), isNull);
    });

    test('confidence >= minConfidence → sonuç döner', () async {
      final detector = _FakeLanguageDetector(
        const LanguageDetectionResult(languageCode: 'tr', confidence: 0.7),
      );
      final result = await detector.detect('Merhaba', minConfidence: 0.6);
      expect(result, isNotNull);
      expect(result!.languageCode, 'tr');
    });

    test('confidence < minConfidence → null (silent drop)', () async {
      final detector = _FakeLanguageDetector(
        const LanguageDetectionResult(languageCode: 'tr', confidence: 0.55),
      );
      expect(
        await detector.detect('belirsiz metin', minConfidence: 0.6),
        isNull,
      );
    });

    test('confidence tam eşikte → kabul (>=)', () async {
      final detector = _FakeLanguageDetector(
        const LanguageDetectionResult(languageCode: 'en', confidence: 0.6),
      );
      final result = await detector.detect('hello', minConfidence: 0.6);
      expect(result, isNotNull);
      expect(result!.languageCode, 'en');
    });

    test('motor null döndürürse (ör. und) çağırana null gider', () async {
      final detector = _FakeLanguageDetector(null);
      expect(await detector.detect('gibberish'), isNull);
    });

    test('default minConfidence 0.6 (karar f)', () async {
      // Tasarımda confidence eşiği 0.6 olarak onaylanmıştı.
      // Bir kez burada da assert edelim ki ileride değişirse test patlar.
      final detector = _FakeLanguageDetector(
        const LanguageDetectionResult(languageCode: 'tr', confidence: 0.59),
      );
      expect(await detector.detect('test'), isNull);

      final detector2 = _FakeLanguageDetector(
        const LanguageDetectionResult(languageCode: 'tr', confidence: 0.6),
      );
      expect(await detector2.detect('test'), isNotNull);
    });
  });
}
