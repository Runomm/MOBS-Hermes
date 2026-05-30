import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

import 'language_detector.dart';

/// Google ML Kit Language Identification ile çalışan [LanguageDetector].
///
/// On-device, ~3MB bundled model (APK'ya gömülü). 100+ dil destekli.
/// Conf eşiği motor seviyesinde de uygulanabilir; biz `identifyPossibleLanguages`
/// kullanıp en yüksek confidence'lı dili döneriz, sonra çağıranın verdiği
/// `minConfidence` ile karşılaştırırız (esnek eşik için).
class MlKitLanguageDetector implements LanguageDetector {
  MlKitLanguageDetector({double internalConfidenceThreshold = 0.0})
      : _detector = LanguageIdentifier(
          confidenceThreshold: internalConfidenceThreshold,
        );

  final LanguageIdentifier _detector;
  bool _initialized = false;

  @override
  String get engineName => 'Google ML Kit Language ID';

  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> initialize() async {
    // ML Kit kendisi lazy init; ilk identify çağrısı modeli yükler.
    _initialized = true;
  }

  @override
  Future<LanguageDetectionResult?> detect(
    String text, {
    double minConfidence = 0.6,
  }) async {
    if (text.trim().isEmpty) return null;
    if (!_initialized) await initialize();

    final possibilities = await _detector.identifyPossibleLanguages(text);
    if (possibilities.isEmpty) return null;

    // ML Kit `und` (undetermined) döndürebilir — confidence ne olursa olsun
    // bu sonuç çağırana iletilmez.
    final best = possibilities.reduce(
      (a, b) => a.confidence >= b.confidence ? a : b,
    );

    if (best.languageTag == 'und') return null;
    if (best.confidence < minConfidence) return null;

    return LanguageDetectionResult(
      languageCode: best.languageTag,
      confidence: best.confidence,
    );
  }

  @override
  Future<void> dispose() async {
    await _detector.close();
  }
}
