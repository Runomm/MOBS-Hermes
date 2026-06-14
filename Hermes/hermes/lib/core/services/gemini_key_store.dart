import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcının kendi Gemini API anahtarını kalıcı saklar (çevrimiçi crunch
/// fallback için — düşük-RAM cihazlarda yerel Gemma3 yerine internet üzerinden
/// özet).
///
/// `HfTokenStore` ile birebir aynı kalıp: anahtar bir kez girilince Ayarlar
/// kutusu kayıtlı değeri otomatik doldurur; varlığı detay ekranındaki çevrimiçi
/// butonları açar.
///
/// ⚠️ shared_preferences düz metin saklar. Bu, kullanıcının kendi cihazındaki
/// kendi anahtarı; APK'ya GÖMÜLMEZ (RELEASE_CHECKLIST). Üretim/dağıtım
/// senaryosunda secure storage gerekir.
class GeminiKeyStore {
  GeminiKeyStore._();
  static final GeminiKeyStore instance = GeminiKeyStore._();

  static const _key = 'gemini_api_key';

  String? _cached;
  bool _loaded = false;

  /// Kayıtlı anahtar (yoksa null). İlk çağrıda prefs'ten okur, sonra cache'ler.
  Future<String?> read() async {
    if (_loaded) return _cached;
    final prefs = await SharedPreferences.getInstance();
    _cached = prefs.getString(_key);
    _loaded = true;
    return _cached;
  }

  /// Anahtarı kaydeder. Boş/whitespace → kaydı siler.
  Future<void> save(String key) async {
    final trimmed = key.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_key);
      _cached = null;
    } else {
      await prefs.setString(_key, trimmed);
      _cached = trimmed;
    }
    _loaded = true;
  }

  /// Kayıtlı anahtarı temizler.
  Future<void> clear() => save('');
}
