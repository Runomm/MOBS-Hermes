import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'translation_engine.dart';

/// Google ML Kit On-Device Translation motoru.
/// İlk çağrıda ~30MB'lık dil modelini indirir, sonrasında tamamen offline çalışır.
class GoogleMLKitEngine implements TranslationEngine {
  OnDeviceTranslator? _translator;
  TranslateLanguage? _currentSource;
  TranslateLanguage? _currentTarget;

  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();

  @override
  String get engineName => 'Google ML Kit';

  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> ensureModelLoaded(String fromCode, String toCode) async {
    final source = _languageFromCode(fromCode);
    final target = _languageFromCode(toCode);

    // Model dosyalarını indir (yüklüyse atlar)
    if (!await _modelManager.isModelDownloaded(source.bcpCode)) {
      await _modelManager.downloadModel(source.bcpCode);
    }
    if (!await _modelManager.isModelDownloaded(target.bcpCode)) {
      await _modelManager.downloadModel(target.bcpCode);
    }

    // Dil çifti değiştiyse translator'ı yeniden oluştur
    if (_currentSource != source || _currentTarget != target) {
      await _translator?.close();
      _translator = OnDeviceTranslator(
        sourceLanguage: source,
        targetLanguage: target,
      );
      _currentSource = source;
      _currentTarget = target;
    }
  }

  @override
  Future<String> translate(String text, String fromCode, String toCode) async {
    await ensureModelLoaded(fromCode, toCode);
    return _translator!.translateText(text);
  }

  // ---------- Dil paketi yönetimi ----------

  @override
  Future<bool> isLanguageReady(String code) async {
    final lang = _languageFromCode(code);
    return _modelManager.isModelDownloaded(lang.bcpCode);
  }

  /// ML Kit'in resmi belgelerinde dil paketi boyutu yaklaşık ~30MB olarak
  /// belirtiliyor; dilden dile küçük farklar var ama API tam değer vermiyor.
  @override
  int estimatedDownloadSizeMb(String code) => 30;

  @override
  Future<void> downloadLanguage(String code) async {
    final lang = _languageFromCode(code);
    if (await _modelManager.isModelDownloaded(lang.bcpCode)) return;
    await _modelManager.downloadModel(lang.bcpCode);
  }

  @override
  Future<void> deleteLanguage(String code) async {
    final lang = _languageFromCode(code);
    if (!await _modelManager.isModelDownloaded(lang.bcpCode)) return;
    await _modelManager.deleteModel(lang.bcpCode);

    // Silinen dil mevcut translator'ın kaynağı/hedefi ise translator'ı invalide et.
    if (_currentSource == lang || _currentTarget == lang) {
      await _translator?.close();
      _translator = null;
      _currentSource = null;
      _currentTarget = null;
    }
  }

  @override
  Future<void> dispose() async {
    await _translator?.close();
    _translator = null;
    _currentSource = null;
    _currentTarget = null;
  }

  /// BCP-47 dil kodunu (örn. 'tr', 'en') ML Kit enum'una çevirir.
  TranslateLanguage _languageFromCode(String code) {
    return TranslateLanguage.values.firstWhere(
      (lang) => lang.bcpCode == code,
      orElse: () =>
          throw ArgumentError('ML Kit bu dili desteklemiyor: $code'),
    );
  }
}
