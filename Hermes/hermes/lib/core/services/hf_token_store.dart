import 'package:shared_preferences/shared_preferences.dart';

/// HuggingFace Read token'ını kalıcı saklar (Gemma gated indirme için).
///
/// Mehmet isteği (NS-3, 2026-06-06): token bir kez girilince tekrar
/// yapıştırılmasın — model seçici + Ayarlar token kutusu kayıtlı değeri
/// otomatik doldursun.
///
/// ⚠️ shared_preferences düz metin saklar. Bu kişisel cihazdaki kullanıcının
/// kendi Read token'ı; APK'ya GÖMÜLMEZ (RELEASE_CHECKLIST). Üretim/dağıtım
/// senaryosunda secure storage veya self-host gerekir.
class HfTokenStore {
  HfTokenStore._();
  static final HfTokenStore instance = HfTokenStore._();

  static const _key = 'hf_token';

  String? _cached;
  bool _loaded = false;

  /// Kayıtlı token (yoksa null). İlk çağrıda prefs'ten okur, sonra cache'ler.
  Future<String?> read() async {
    if (_loaded) return _cached;
    final prefs = await SharedPreferences.getInstance();
    _cached = prefs.getString(_key);
    _loaded = true;
    return _cached;
  }

  /// Token'ı kaydeder. Boş/whitespace → kaydı siler.
  Future<void> save(String token) async {
    final trimmed = token.trim();
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

  /// Kayıtlı token'ı temizler.
  Future<void> clear() => save('');
}
