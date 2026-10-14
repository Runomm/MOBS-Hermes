import 'package:flutter/material.dart';

import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import 'hg_icons.dart';

/// Sola-kaydır-sil satırı (Mehmet 2026-06-19: pop-up onay yerine user-friendly).
///
/// Sola kaydırınca satır sola kayar, arkadan **kırmızı** eylem paneli açılır:
/// **çöp kutusu** (bas → sil) + **sarı geri-al oku** (bas → vazgeç, satır geri
/// kayar). Onay dialogu yok; geri-al güvenliği yerinde.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
  });

  final Widget child;

  /// Çöp kutusuna basılınca çağrılır (asıl silme + liste yenileme orada).
  final Future<void> Function() onDelete;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  static const double _revealW = 116;
  bool _revealed = false;

  void _close() => setState(() => _revealed = false);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -120 && !_revealed) {
          setState(() => _revealed = true);
        } else if (v > 120 && _revealed) {
          _close();
        }
      },
      child: Stack(
        children: [
          // Arka plan: kırmızı eylem paneli (sağda geri-al + çöp).
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  color: const Color(0xFFE5484D),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Sarı "geri al" oku — vazgeç (silme).
                      _action(
                        icon: HgIcons.refresh,
                        color: const Color(0xFFF5C542),
                        onTap: _close,
                      ),
                      const SizedBox(width: 6),
                      // Çöp kutusu — sil.
                      _action(
                        icon: HgIcons.trash,
                        color: Colors.white,
                        onTap: () async {
                          await widget.onDelete();
                          if (mounted) _close();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Ön plan: kayan satır içeriği.
          AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: _revealed
                ? Offset(
                    -_revealW / MediaQuery.of(context).size.width,
                    0,
                  )
                : Offset.zero,
            child: widget.child,
          ),
        ],
      ),
    );
  }

  Widget _action({
    required HgIconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return HgPressable(
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: HgIcon(icon, size: 24, color: color, strokeWidth: 2),
        ),
      ),
    );
  }
}

/// Liste başında gösterilen küçük ipucu: "Silmek için sola kaydırın".
class SwipeDeleteHint extends StatelessWidget {
  const SwipeDeleteHint({super.key});

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          HgIcon(HgIcons.back, size: 13, color: p.faint, strokeWidth: 2),
          const SizedBox(width: 6),
          Text(
            'Silmek için kaydı sola kaydırın',
            style: HgType.sans(12, color: p.faint),
          ),
        ],
      ),
    );
  }
}
