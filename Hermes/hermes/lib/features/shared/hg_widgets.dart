import 'package:flutter/material.dart';

import '../../core/theme/hg_background.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import 'hg_icons.dart';

/// Liquid-glass paylaşılan ekran bileşenleri (hand-off `hermes-screens.jsx` /
/// `hermes-conversation.jsx` ortak parçaları). Tüm restyle'lı ekranlar bunları
/// kullanır — değerler prototipten birebir.

/// Ekran iskeleti: mesh arka plan + SafeArea + 22px yatay padding'li kolon.
/// [scroll] true → içerik kaydırılabilir; false → Column (Spacer kullanılabilir).
class HgScreen extends StatelessWidget {
  const HgScreen({
    super.key,
    required this.child,
    this.scroll = true,
    this.padded = true,
  });

  final Widget child;
  final bool scroll;

  /// false → child padding'i kendisi yönetir (canlı akış ekranları).
  final bool padded;

  @override
  Widget build(BuildContext context) {
    Widget body = padded
        ? Padding(
            padding: const EdgeInsets.fromLTRB(Hg.pad, 14, Hg.pad, 16),
            child: child,
          )
        : child;
    if (scroll) {
      body = LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: IntrinsicHeight(child: body),
          ),
        ),
      );
    }
    return Scaffold(
      body: HgMeshBackground(child: SafeArea(child: body)),
    );
  }
}

/// 42px cam geri pill'i.
class HgBackButton extends StatelessWidget {
  const HgBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return HgPressable(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: HgGlass(
        radius: 20,
        elevated: false,
        width: 42,
        height: 42,
        child: Center(
          child: HgIcon(HgIcons.back, size: 22, color: p.text, strokeWidth: 2),
        ),
      ),
    );
  }
}

/// Sans başlıklı nav header (geri pill + 22/800 başlık + alt satır).
class HgNavHeader extends StatelessWidget {
  const HgNavHeader({super.key, required this.title, this.sub, this.right});

  final String title;
  final String? sub;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const HgBackButton(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: HgType.sans(
                    22,
                    weight: 800,
                    color: p.text,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(sub!, style: HgType.sans(12.5, color: p.sub)),
                  ),
              ],
            ),
          ),
          ?right,
        ],
      ),
    );
  }
}

/// Serif canlı-akış üst barı (LiveTopBar/ConfTopBar): geri + serif başlık +
/// alt satır + opsiyonel durum pill'i.
class HgSerifTopBar extends StatelessWidget {
  const HgSerifTopBar({
    super.key,
    required this.title,
    required this.sub,
    this.label,
    this.dotColor,
    this.onBack,
  });

  final String title;
  final String sub;
  final String? label;
  final Color? dotColor;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return Row(
      children: [
        HgBackButton(onTap: onBack),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: HgType.serif(22, weight: 600, color: p.text, height: 1),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(sub, style: HgType.sans(12, color: p.sub)),
              ),
            ],
          ),
        ),
        if (label != null)
          HgGlass(
            radius: 13,
            elevated: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dotColor != null) ...[
                  HgDot(color: dotColor!),
                  const SizedBox(width: 7),
                ],
                Text(
                  label!,
                  style: HgType.sans(12.5, weight: 600, color: p.text),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Serif bölüm başlığı (`SerifTitle`).
class HgSerifTitle extends StatelessWidget {
  const HgSerifTitle(this.text, {super.key, this.size = 30});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return Text(
      text,
      style: HgType.serif(
        size,
        weight: 600,
        color: p.text,
        letterSpacing: 0.2,
        height: 1.05,
      ),
    );
  }
}

/// Parlayan durum noktası.
class HgDot extends StatelessWidget {
  const HgDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.22), spreadRadius: 3),
        ],
      ),
    );
  }
}

/// Birincil CTA — diagonal gradient (accent → visual) + renkli glow + beyaz metin.
class HgGradientButton extends StatelessWidget {
  const HgGradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.from,
    this.to,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget? icon;

  /// Gradient uçları; verilmezse palet accent → visual.
  final Color? from;
  final Color? to;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final a = from ?? p.accent;
    final b = to ?? p.visual;
    return HgPressable(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [a, b],
          ),
          boxShadow: [
            BoxShadow(
              color: a.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              Text(
                label,
                style: HgType.sans(
                  16,
                  weight: 700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// İkincil buton — cam zemin, ortalanmış kalın etiket.
class HgGlassButton extends StatelessWidget {
  const HgGlassButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return HgPressable(
      onTap: onTap,
      child: HgGlass(
        radius: 16,
        elevated: false,
        height: 50,
        child: Center(
          child: Text(
            label,
            style: HgType.sans(14.5, weight: 700, color: p.text),
          ),
        ),
      ),
    );
  }
}

/// Mod-renkli dolu ikon karosu (`linear-gradient(140deg, ac, ac@0.72)`).
class HgIconTile extends StatelessWidget {
  const HgIconTile({
    super.key,
    required this.accent,
    required this.child,
    this.size = 50,
    this.radius = 15,
  });

  final Color accent;
  final Widget child;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.72)],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1),
        ),
      ),
      child: Center(child: child),
    );
  }
}

/// Canlı ekolayzer (hg-eq: scaleY 0.35↔1, 0.9s, bar başına gecikme).
class HgEqualizer extends StatefulWidget {
  const HgEqualizer({
    super.key,
    required this.color,
    this.bars = 5,
    this.height = 22,
    this.running = true,
  });

  final Color color;
  final int bars;
  final double height;
  final bool running;

  @override
  State<HgEqualizer> createState() => _HgEqualizerState();
}

class _HgEqualizerState extends State<HgEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.running) _c.repeat();
  }

  @override
  void didUpdateWidget(HgEqualizer old) {
    super.didUpdateWidget(old);
    if (widget.running && !_c.isAnimating) _c.repeat();
    if (!widget.running && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < widget.bars; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            _bar(i),
          ],
        ],
      ),
    );
  }

  Widget _bar(int i) {
    // Faz kaydırmalı sinüs ~ CSS keyframe (0.35↔1).
    final t = (_c.value - i * 0.111) % 1.0;
    final s =
        0.35 +
        0.65 * (0.5 - 0.5 * (t < 0.5 ? (1 - 4 * t) : (4 * t - 3)).clamp(-1, 1));
    return Opacity(
      opacity: widget.running ? 1 : 0.3,
      child: Container(
        width: 3.5,
        height: widget.height * (widget.running ? s : 0.35),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 168px dairesel başlat butonu + nabız halkaları (warmup fazı).
class HgWarmupCircle extends StatefulWidget {
  const HgWarmupCircle({
    super.key,
    required this.icon,
    required this.label,
    this.warming = false,
    this.onTap,
    this.accent,
  });

  final HgIconData icon;
  final String label;
  final bool warming;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  State<HgWarmupCircle> createState() => _HgWarmupCircleState();
}

class _HgWarmupCircleState extends State<HgWarmupCircle>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didUpdateWidget(HgWarmupCircle old) {
    super.didUpdateWidget(old);
    if (widget.warming && !_spin.isAnimating) _spin.repeat();
    if (!widget.warming && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final a = widget.accent ?? p.accent;
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(a, 0),
          _ring(a, 0.5),
          HgPressable(
            onTap: widget.warming ? null : widget.onTap,
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [a, p.visual],
                ),
                boxShadow: [
                  BoxShadow(
                    color: a.withValues(alpha: 0.5),
                    blurRadius: 44,
                    offset: const Offset(0, 18),
                  ),
                ],
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.warming)
                    RotationTransition(
                      turns: _spin,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 3,
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: 10,
                            height: 3,
                            child: ColoredBox(color: Colors.white),
                          ),
                        ),
                      ),
                    )
                  else
                    HgIcon(
                      widget.icon,
                      size: 46,
                      color: Colors.white,
                      strokeWidth: 1.8,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    widget.label,
                    style: HgType.sans(
                      13,
                      weight: 700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(Color a, double delay) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) {
        final t = (_pulse.value + delay) % 1.0;
        return Transform.scale(
          scale: 1 + 0.5 * t,
          child: Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: a.withValues(alpha: 0.25 * (1 - t)),
            ),
          ),
        );
      },
    );
  }
}

/// Bitti/hata fazlarının 64px sonuç karosu.
class HgResultTile extends StatelessWidget {
  const HgResultTile({
    super.key,
    required this.icon,
    required this.accent,
    this.filled = true,
  });

  final HgIconData icon;
  final Color accent;

  /// true → gradient dolu (başarı); false → tintli zemin (uyarı).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent.withValues(alpha: 0.7)],
              )
            : null,
        color: filled ? null : accent.withValues(alpha: dark ? 0.26 : 0.16),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.4),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Center(
        child: HgIcon(
          icon,
          size: 32,
          color: filled ? Colors.white : accent,
          strokeWidth: filled ? 2.6 : 2,
        ),
      ),
    );
  }
}

/// İstatistik camı (done fazı): serif 26 sayılar + ayraçlı sütunlar.
class HgStatGlass extends StatelessWidget {
  const HgStatGlass({super.key, required this.stats});

  /// (etiket, değer) çiftleri.
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return HgGlass(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++)
            Expanded(
              child: Container(
                decoration: i > 0
                    ? BoxDecoration(
                        border: Border(
                          left: BorderSide(color: p.hairline, width: 0.5),
                        ),
                      )
                    : null,
                child: Column(
                  children: [
                    Text(
                      stats[i].$2,
                      style: HgType.serif(26, weight: 600, color: p.text),
                    ),
                    const SizedBox(height: 1),
                    Text(stats[i].$1, style: HgType.sans(11.5, color: p.sub)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hazırlık kontrol listesi camı (gate fazı): ad + alt satır + ✓ / etiket.
class HgChecklistGlass extends StatelessWidget {
  const HgChecklistGlass({super.key, required this.rows});

  /// (başlık, alt satır, hazır mı; hazır değilse sağda gösterilecek etiket).
  final List<(String, String, bool, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return HgGlass(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: i < rows.length - 1
                  ? BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: p.hairline, width: 0.5),
                      ),
                    )
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].$1,
                          style: HgType.sans(14.5, weight: 600, color: p.text),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            rows[i].$2,
                            style: HgType.sans(12, color: p.sub),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (rows[i].$3)
                    HgIcon(
                      HgIcons.check,
                      size: 18,
                      color: p.live,
                      strokeWidth: 2.4,
                    )
                  else
                    Text(
                      (rows[i].$4 ?? 'EKSİK').toUpperCase(),
                      style: HgType.sans(
                        12,
                        weight: 700,
                        color: rows[i].$4 != null ? p.faint : p.manual,
                        letterSpacing: 0.3,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Uyarı camı (tintli, ikon + zengin metin).
class HgWarnGlass extends StatelessWidget {
  const HgWarnGlass({
    super.key,
    required this.icon,
    required this.child,
    this.accent,
  });

  final HgIconData icon;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final a = accent ?? p.manual;
    return HgGlass(
      radius: 16,
      tint: a,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HgIcon(icon, size: 20, color: a, strokeWidth: 1.9),
          const SizedBox(width: 11),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Seçilebilir radyo kartı (wizard ChoiceCard).
class HgChoiceCard extends StatelessWidget {
  const HgChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
    required this.selected,
    required this.onTap,
    this.tag,
    this.accent,
  });

  final HgIconData icon;
  final String title;
  final String desc;
  final String? tag;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final dark = p.noir;
    final a = accent ?? p.accent;
    return HgPressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? a.withValues(alpha: 0.85) : Colors.transparent,
            width: 2,
          ),
        ),
        child: HgGlass(
          radius: 18,
          tint: selected ? a : null,
          elevated: selected,
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selected)
                HgIconTile(
                  accent: a,
                  child: HgIcon(
                    icon,
                    size: 26,
                    color: Colors.white,
                    strokeWidth: 1.8,
                  ),
                )
              else
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color.fromRGBO(40, 38, 66, 0.06),
                  ),
                  child: Center(
                    child: HgIcon(icon, size: 26, color: a, strokeWidth: 1.8),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: HgType.sans(
                              17.5,
                              weight: 700,
                              color: p.text,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        if (tag != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              color: a.withValues(alpha: dark ? 0.22 : 0.14),
                            ),
                            child: Text(
                              tag!.toUpperCase(),
                              style: HgType.sans(
                                10.5,
                                weight: 700,
                                color: a,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        desc,
                        style: HgType.sans(12.5, color: p.sub, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              HgRadio(selected: selected, accent: a),
            ],
          ),
        ),
      ),
    );
  }
}

/// Radyo göstergesi (seçili → dolu + check).
class HgRadio extends StatelessWidget {
  const HgRadio({super.key, required this.selected, required this.accent});

  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? accent : Colors.transparent,
        border: Border.all(
          color: selected
              ? accent
              : (p.noir
                    ? Colors.white.withValues(alpha: 0.24)
                    : const Color.fromRGBO(40, 38, 66, 0.2)),
          width: 2,
        ),
      ),
      child: selected
          ? const Center(
              child: HgIcon(
                HgIcons.check,
                size: 13,
                color: Colors.white,
                strokeWidth: 3,
              ),
            )
          : null,
    );
  }
}

/// Kompakt kalite kartı (wizard QualityCard).
class HgQualityCard extends StatelessWidget {
  const HgQualityCard({
    super.key,
    required this.icon,
    required this.title,
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final HgIconData icon;
  final String title;
  final String meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return HgPressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? p.accent.withValues(alpha: 0.85)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: HgGlass(
          radius: 16,
          tint: selected ? p.accent : null,
          elevated: selected,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              HgIcon(
                icon,
                size: 24,
                color: selected ? p.accent : p.sub,
                strokeWidth: 1.9,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: HgType.sans(
                        16.5,
                        weight: 700,
                        color: p.text,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(meta, style: HgType.sans(12, color: p.sub)),
                    ),
                  ],
                ),
              ),
              HgRadio(selected: selected, accent: p.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segment kontrol (Manuel "Hızlı/Akıllı" chip'leri).
class HgSegmented extends StatelessWidget {
  const HgSegmented({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
    this.accent,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final a = accent ?? p.accent;
    return HgGlass(
      radius: 16,
      elevated: false,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: HgPressable(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: i == selectedIndex
                        ? a.withValues(alpha: p.noir ? 0.3 : 0.2)
                        : Colors.transparent,
                  ),
                  child: Center(
                    child: Text(
                      options[i],
                      style: HgType.sans(
                        13.5,
                        weight: 700,
                        color: i == selectedIndex ? a : p.sub,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dil pill çubuğu (Manuel/Görsel): kaynak + swap + hedef.
class HgLangBar extends StatelessWidget {
  const HgLangBar({
    super.key,
    required this.source,
    required this.target,
    required this.onSwap,
  });

  final String source;
  final String target;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    Widget pill(String label, String value) => Expanded(
      child: HgGlass(
        radius: 16,
        elevated: false,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: HgType.sans(
                11,
                weight: 600,
                color: p.faint,
                letterSpacing: 0.3,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                value,
                style: HgType.sans(15.5, weight: 700, color: p.text),
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        pill('Kaynak', source),
        const SizedBox(width: 10),
        HgPressable(
          onTap: onSwap,
          child: HgGlass(
            radius: 14,
            elevated: false,
            width: 40,
            height: 40,
            child: Center(
              child: HgIcon(
                HgIcons.swap,
                size: 19,
                color: p.sub,
                strokeWidth: 1.9,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        pill('Hedef', target),
      ],
    );
  }
}
