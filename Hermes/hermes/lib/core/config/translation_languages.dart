/// Merkezi dil listeleri (2026-06-19). Eskiden her ekran kendi `_languages`
/// haritasını tutuyordu (dağınık, 5-6 dil); buradan tek kaynaktan beslenir.
///
/// - [kMlkitLanguages]: ML Kit çevirisi olan diller (Manuel "Hızlı" tier + OCR).
/// - [kNllbLanguages]: NLLB-600M'in küratörlü ~35 dili (Manuel "NLLB" tier).
/// - [kLiveLanguages]: canlı STT (Vosk) modeli olan diller (Konferans + SmallTalk).
///
/// BCP-47 kısa kod → Türkçe ad. Sıralama kullanıcı görünür sıradır.
library;

/// NLLB katmanı — küratörlü ~35 dil. NLLB motoru (`nllb_translation_engine`
/// `_nllbCode` + `nllb_onnx_translator` `_langIds`) bu kümeyi tanımalı.
const Map<String, String> kNllbLanguages = {
  'tr': 'Türkçe',
  'en': 'İngilizce',
  'de': 'Almanca',
  'fr': 'Fransızca',
  'es': 'İspanyolca',
  'it': 'İtalyanca',
  'nl': 'Felemenkçe',
  'ru': 'Rusça',
  'zh': 'Çince',
  'ar': 'Arapça',
  'pt': 'Portekizce',
  'pl': 'Lehçe',
  'uk': 'Ukraynaca',
  'ja': 'Japonca',
  'ko': 'Korece',
  'el': 'Yunanca',
  'sv': 'İsveççe',
  'da': 'Danca',
  'no': 'Norveççe',
  'fi': 'Fince',
  'cs': 'Çekçe',
  'ro': 'Romence',
  'hu': 'Macarca',
  'bg': 'Bulgarca',
  'hr': 'Hırvatça',
  'sk': 'Slovakça',
  'id': 'Endonezce',
  'vi': 'Vietnamca',
  'th': 'Tayca',
  'hi': 'Hintçe',
  'fa': 'Farsça',
  'he': 'İbranice',
  'sr': 'Sırpça',
  'az': 'Azerbaycanca',
  'ka': 'Gürcüce',
};

/// ML Kit çeviri katmanı (Manuel "Hızlı" + Görsel Çeviri). ML Kit'in çevirebildiği
/// diller; yeni eklenenler nl/ru/zh/ar (Mehmet 2026-06-19).
const Map<String, String> kMlkitLanguages = {
  'en': 'İngilizce',
  'tr': 'Türkçe',
  'de': 'Almanca',
  'fr': 'Fransızca',
  'es': 'İspanyolca',
  'it': 'İtalyanca',
  'nl': 'Felemenkçe',
  'ru': 'Rusça',
  'zh': 'Çince',
  'ar': 'Arapça',
};

/// Canlı modlar (Konferans + SmallTalk) — yalnız **Vosk STT modeli** olan diller
/// (`vosk_models.dart`). nl/ru/zh eklendi; Arapça'nın küçük Vosk modeli yok →
/// canlı modlarda yer almaz (çeviri olarak ML Kit/NLLB'de var).
const Map<String, String> kLiveLanguages = {
  'tr': 'Türkçe',
  'en': 'İngilizce',
  'es': 'İspanyolca',
  'de': 'Almanca',
  'fr': 'Fransızca',
  'it': 'İtalyanca',
  'nl': 'Felemenkçe',
  'ru': 'Rusça',
  'zh': 'Çince',
};
