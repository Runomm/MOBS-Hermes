import 'package:flutter/material.dart';

import '../../core/services/device_memory.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import 'hg_icons.dart';

/// Canlı "Akıllı/full (NLLB)" modu seçilmeden önce çağrılır. Cihaz RAM'i düşükse
/// (bkz. [kLowRamThresholdMb]) bir uyarı dialogu gösterir ve kullanıcının
/// kararını döndürür: `true` = yine de devam, `false` = vazgeç.
///
/// RAM yüksek veya bilinmiyorsa **dialog göstermez, `true` döner** (akış normal).
/// NLLB-600M (~1.3GB) + canlı ASR eşzamanlı düşük-RAM cihazda OOM (signal 9) ile
/// çöküyordu (Poco X3 Pro 8GB) — bu uyarı sürpriz çökme yerine bilinçli seçim sağlar.
Future<bool> confirmHeavyTierOnLowRam(
  BuildContext context, {
  DeviceMemory? memory,
}) async {
  final totalMb = await (memory ?? DeviceMemory()).totalRamMb();
  if (!isLowRam(totalMb)) return true; // yeterli RAM / bilinmiyor → uyarma
  if (!context.mounted) return false;

  final gb = (totalMb! / 1024).toStringAsFixed(1);
  final p = HgPalette.of(context);
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      contentPadding: EdgeInsets.zero,
      content: HgGlass(
        radius: 24,
        tint: p.manual,
        tintStrength: 0.5,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                HgIcon(
                  HgIcons.warning,
                  size: 22,
                  color: p.manual,
                  strokeWidth: 1.9,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cihaz belleği düşük',
                    style: HgType.serif(20, weight: 600, color: p.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Bu cihazın RAM\'i ~$gb GB. "Akıllı (NLLB)" çeviri + ses tanıma '
              'birlikte belleği aşıp uygulamayı çökertebilir. Düşük bellekli '
              'cihazlarda "Hızlı" önerilir.\n\nYine de "Akıllı" kullanılsın mı?',
              style: HgType.sans(14, color: p.sub, height: 1.45),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                HgPressable(
                  onTap: () => Navigator.of(ctx).pop(false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Text(
                      'İptal',
                      style: HgType.sans(14, weight: 700, color: p.sub),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                HgPressable(
                  onTap: () => Navigator.of(ctx).pop(true),
                  child: HgGlass(
                    radius: 13,
                    elevated: false,
                    tint: p.manual,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      'Yine de kullan',
                      style: HgType.sans(14, weight: 700, color: p.text),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return proceed ?? false; // dışına dokunup kapatma → vazgeç
}
