import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/config/translation_languages.dart';
import 'package:hermes/core/engines/translation/nllb_translation_engine.dart';

/// NllbTranslationEngine — native ONNX/path_provider gerektirmeyen davranış:
/// BCP-47 dil desteği + desteklenmeyen dilde hata (model kontrolünden ÖNCE).
void main() {
  test('supportsLanguage — küratörlü diller (2026-06-19 genişletildi)', () {
    // Çekirdek + sonradan eklenen küratörlü diller (nl/ru/zh/ja/ar...).
    for (final c in ['tr', 'en', 'es', 'de', 'fr', 'it', 'nl', 'ru', 'zh',
        'ar', 'ja', 'ko', 'pt']) {
      expect(NllbTranslationEngine.supportsLanguage(c), isTrue, reason: c);
    }
    // Listede olmayan diller hâlâ desteklenmez.
    expect(NllbTranslationEngine.supportsLanguage('sw'), isFalse);
    expect(NllbTranslationEngine.supportsLanguage('zz'), isFalse);
  });

  test('desteklenmeyen dil → ArgumentError (model kontrolünden önce)', () async {
    final engine = NllbTranslationEngine();
    // 'sw' (Swahili) küratörlü listede yok → manager/ONNX'e dokunmadan
    // ArgumentError.
    expect(
      () => engine.translate('test', 'sw', 'en'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => engine.ensureModelLoaded('en', 'sw'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('merkezi kNllbLanguages ↔ motor tutarlı (her dil destekli)', () {
    // Manuel ekranın NLLB dil listesi ile motorun _nllbCode haritası uyuşmalı;
    // biri eklenip diğeri unutulursa "desteklenmiyor" hatası verir (Mehmet
    // 2026-06-19).
    for (final code in kNllbLanguages.keys) {
      expect(
        NllbTranslationEngine.supportsLanguage(code),
        isTrue,
        reason: 'kNllbLanguages içindeki $code NLLB motorunda tanımsız',
      );
    }
  });

  test('engineName + offline', () {
    final engine = NllbTranslationEngine();
    expect(engine.engineName, 'NLLB-600M');
    expect(engine.isOfflineCapable, isTrue);
    expect(engine.estimatedDownloadSizeMb('tr'), greaterThan(1000));
  });
}
