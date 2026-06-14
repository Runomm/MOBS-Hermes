import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Hermes'in standart liste/seçim kartı (Faz 4 tasarım dili).
///
/// Ana ekran mod kartları, setup seçim kartları vb. tek tip yüzey kullanır:
/// beyaz zemin + ince kenarlık + 12px radius + renkli ikon-rozet + başlık/alt
/// başlık + opsiyonel sağ aksiyon (trailing).
class HermesCard extends StatelessWidget {
  const HermesCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Kartın vurgu rengi (ikon rozeti + varsayılan trailing tonu).
  final Color accent;

  final VoidCallback? onTap;

  /// Sağdaki özel aksiyon. Verilmezse chevron gösterilir.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: HermesColors.surface,
        border: Border.all(color: HermesColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: HermesColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: HermesColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else
                  const Icon(
                    Icons.chevron_right,
                    color: HermesColors.textFaint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
