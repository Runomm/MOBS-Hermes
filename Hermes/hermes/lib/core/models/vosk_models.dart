/// Uygulamanın desteklediği dillerin Vosk small model kayıtları.
///
/// Karar (2026-06-01, Mehmet): Vosk ana STT, her dil kendi Vosk modeliyle;
/// iyi Vosk modeli olmayan diller Whisper'a düşer (router — Burst 2).
///
/// İndirme kaynağı: resmi alphacephei.com ~30 KB/s throttle ediyor → HuggingFace
/// aynası `rhasspy/vosk-models` (~8 MB/s CDN) kullanılıyor. Klasör = uygulama
/// dil kodu (en/tr/...); model adı dile göre değişir (İngilizce `en-us`).
class VoskModelInfo {
  const VoskModelInfo({
    required this.langCode,
    required this.langName,
    required this.modelName,
    required this.folder,
    required this.sizeMb,
  });

  /// Uygulama dil kodu (BCP-47 kısa): en, tr, es, fr, de, it.
  final String langCode;

  /// Türkçe görünen ad (Ayarlar UI).
  final String langName;

  /// Vosk model dizin/dosya adı, örn. `vosk-model-small-tr-0.3`.
  final String modelName;

  /// HuggingFace aynasındaki dil klasörü.
  final String folder;

  final int sizeMb;

  /// HuggingFace aynası zip URL'i.
  String get url =>
      'https://huggingface.co/rhasspy/vosk-models/resolve/main/$folder/$modelName.zip';
}

/// Desteklenen dillerin Vosk model registry'si (dil kodu → bilgi).
class VoskModels {
  VoskModels._();

  static const Map<String, VoskModelInfo> byLang = {
    'en': VoskModelInfo(
      langCode: 'en',
      langName: 'İngilizce',
      modelName: 'vosk-model-small-en-us-0.15',
      folder: 'en',
      sizeMb: 39,
    ),
    'tr': VoskModelInfo(
      langCode: 'tr',
      langName: 'Türkçe',
      modelName: 'vosk-model-small-tr-0.3',
      folder: 'tr',
      sizeMb: 35,
    ),
    'es': VoskModelInfo(
      langCode: 'es',
      langName: 'İspanyolca',
      modelName: 'vosk-model-small-es-0.42',
      folder: 'es',
      sizeMb: 38,
    ),
    'fr': VoskModelInfo(
      langCode: 'fr',
      langName: 'Fransızca',
      modelName: 'vosk-model-small-fr-0.22',
      folder: 'fr',
      sizeMb: 40,
    ),
    'de': VoskModelInfo(
      langCode: 'de',
      langName: 'Almanca',
      modelName: 'vosk-model-small-de-0.15',
      folder: 'de',
      sizeMb: 44,
    ),
    'it': VoskModelInfo(
      langCode: 'it',
      langName: 'İtalyanca',
      modelName: 'vosk-model-small-it-0.22',
      folder: 'it',
      sizeMb: 47,
    ),
  };

  /// Bu dilin bir Vosk modeli var mı? (router'da Vosk mı Whisper mı kararı)
  static bool supports(String langCode) => byLang.containsKey(langCode);

  static VoskModelInfo? forLang(String langCode) => byLang[langCode];
}
