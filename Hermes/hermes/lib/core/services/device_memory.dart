import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

/// Düşük-RAM eşiği (MB). Bu değerin **altındaki** cihazlarda canlı "Akıllı/full
/// (NLLB)" modu seçilince OOM uyarısı gösterilir. ~11GB seçildi (Mehmet
/// 2026-06-09): 8GB Poco X3 Pro `physicalRamSize` ~7.4GB rapor eder → uyarılır;
/// 12GB+ cihazlar uyarılmaz. NLLB-600M int8 (~1.3GB) + canlı ASR eşzamanlı
/// Poco'da signal 9 (OOM) ile çöküyordu.
const int kLowRamThresholdMb = 11 * 1024; // 11264 MB ≈ 11 GB

/// Cihazın toplam fiziksel RAM'ini sorgular (`device_info_plus`). Android + iOS
/// `physicalRamSize` döndürür (MB); native kod yazmamızı gerektirmez.
class DeviceMemory {
  DeviceMemory({DeviceInfoPlugin? plugin})
      : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;

  /// Toplam fiziksel RAM (MB). Desteklenmeyen platform veya hata → `null`
  /// (bilinmiyor → çağıran uyarmaz).
  Future<int?> totalRamMb() async {
    try {
      if (Platform.isAndroid) return (await _plugin.androidInfo).physicalRamSize;
      if (Platform.isIOS) return (await _plugin.iosInfo).physicalRamSize;
    } catch (_) {
      // device_info hatası → bilinmiyor.
    }
    return null;
  }
}

/// Verilen RAM (MB) düşük-RAM eşiğinin altında mı? `null` (bilinmiyor) → `false`
/// (uyarma). Saf fonksiyon — test edilebilir.
bool isLowRam(int? totalRamMb, {int thresholdMb = kLowRamThresholdMb}) =>
    totalRamMb != null && totalRamMb < thresholdMb;
