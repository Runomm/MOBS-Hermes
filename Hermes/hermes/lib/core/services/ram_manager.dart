import '../engines/translation/llm_translation_engine.dart';
import '../engines/translation/nllb_translation_engine.dart';

/// RAM disiplini (Mehmet 2026-06-13): SD860/8GB cihazda NLLB (~1.3GB) + özet
/// LLM (~1GB) aynı anda RAM'e sığmaz → OOM. Strateji:
/// - Açılışta NLLB daima RAM'e ([preloadNllb]) — en çok kullanılan motor.
/// - Offline LLM özeti gerekince NLLB boşalt → LLM çalıştır → LLM boşalt → NLLB
///   sessizce geri yükle ([withLlmRam]). Kullanıcı NLLB'nin geri yüklendiğini
///   görmez.
/// - Acil/elle temizlik: [freeAll] (kullanıcı "RAM'i boşalt" butonu + hata yolu).
class RamManager {
  RamManager._();

  /// Açılışta NLLB'yi arka planda RAM'e al (best-effort; inmemişse atlar).
  static Future<void> preloadNllb() => NllbTranslationEngine.preloadShared();

  /// [fn] bir offline LLM işidir (özet). Önce NLLB'yi RAM'den boşaltır, işi
  /// çalıştırır, ardından LLM'i boşaltıp NLLB'yi sessizce geri yükler.
  static Future<T> withLlmRam<T>(Future<T> Function() fn) async {
    await NllbTranslationEngine.unloadShared();
    try {
      return await fn();
    } finally {
      // LLM'i bırak, NLLB'yi geri al (bir sonraki çeviri beklemesin).
      try {
        await LlmHost.instance.unload();
      } catch (_) {}
      try {
        await NllbTranslationEngine.preloadShared();
      } catch (_) {}
    }
  }

  /// Canlı oturum (STT + çeviri) başlamadan önce "temiz başlangıç" (Mehmet
  /// 2026-06-13): yalnız özet LLM'ini boşalt (NLLB resident kalır — canlı çeviri
  /// onu kullanabilir). Önceki işten artakalan LLM RAM'ini geri verir → OOM azalır.
  static Future<void> freeForLiveSession() async {
    try {
      await LlmHost.instance.unload();
    } catch (_) {}
  }

  /// Tüm ağır modelleri RAM'den boşalt — kullanıcı "RAM'i boşalt" + hata yolu.
  static Future<void> freeAll() async {
    try {
      await LlmHost.instance.unload();
    } catch (_) {}
    try {
      await NllbTranslationEngine.unloadShared();
    } catch (_) {}
  }
}
