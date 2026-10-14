import 'package:flutter/material.dart';

import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import 'hg_icons.dart';

/// Genel onay dialog'u (liquid-glass) — arşivde/oturum sonunda **silme** gibi
/// geri alınamaz işlemler için (Mehmet 2026-06-19). `true` = onaylandı.
///
/// [destructive] true ise onay butonu uyarı renginde (`p.manual`).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Sil',
  String cancelLabel = 'Vazgeç',
  bool destructive = true,
}) async {
  final p = HgPalette.of(context);
  final accent = destructive ? p.manual : p.accent;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      contentPadding: EdgeInsets.zero,
      content: HgGlass(
        radius: 24,
        tint: accent,
        tintStrength: 0.5,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                HgIcon(
                  destructive ? HgIcons.trash : HgIcons.warning,
                  size: 22,
                  color: accent,
                  strokeWidth: 1.9,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: HgType.serif(20, weight: 600, color: p.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message,
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
                      cancelLabel,
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
                    tint: accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      confirmLabel,
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
  return ok ?? false;
}
