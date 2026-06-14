import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/engines/translation/nllb_translation_engine.dart';

/// NllbTranslationEngine — native ONNX/path_provider gerektirmeyen davranış:
/// BCP-47 dil desteği + desteklenmeyen dilde hata (model kontrolünden ÖNCE).
void main() {
  test('supportsLanguage — Faz 1 dilleri', () {
    for (final c in ['tr', 'en', 'es', 'de', 'fr', 'it']) {
      expect(NllbTranslationEngine.supportsLanguage(c), isTrue, reason: c);
    }
    expect(NllbTranslationEngine.supportsLanguage('ja'), isFalse);
    expect(NllbTranslationEngine.supportsLanguage('zz'), isFalse);
  });

  test('desteklenmeyen dil → ArgumentError (model kontrolünden önce)', () async {
    final engine = NllbTranslationEngine();
    // 'ja' desteklenmiyor → manager/ONNX'e dokunmadan ArgumentError.
    expect(
      () => engine.translate('test', 'ja', 'en'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => engine.ensureModelLoaded('en', 'ja'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('engineName + offline', () {
    final engine = NllbTranslationEngine();
    expect(engine.engineName, 'NLLB-600M');
    expect(engine.isOfflineCapable, isTrue);
    expect(engine.estimatedDownloadSizeMb('tr'), greaterThan(1000));
  });
}
