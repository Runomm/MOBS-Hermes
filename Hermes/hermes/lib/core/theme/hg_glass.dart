import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'hg_tokens.dart';

/// Liquid-glass primitifi (hand-off `<Glass>`): mesh'in üzerinde duran buzlu,
/// yarı saydam panel. Katmanlar: backdrop blur+saturate → (ops.) tint bloom →
/// üst parlama şeridi → hairline kenar; dışta yumuşak renkli gölge.
///
/// `intensity` 20–100 → blur ve dolgu opaklığı (hand-off eşlemesi birebir).
/// Varsayılan 74 = prototipin tweak state'i.
///
/// Performans (Poco/SD860): her HgGlass bir `BackdropFilter` = saveLayer.
/// Home'da az sayıda yüzey var; liste-yoğun ekranlarda (Tur 2+) gerekirse
/// `blur: false` ile düz yarı saydam dolguya düşülür (mesh statik olduğundan
/// görsel fark küçük).
class HgGlass extends StatelessWidget {
  const HgGlass({
    super.key,
    required this.child,
    this.radius = Hg.rCard,
    this.intensity = 74,
    this.tint,
    this.tintStrength = 1,
    this.elevated = true,
    this.blur = true,
    this.padding,
    this.width,
    this.height,
  });

  final Widget child;
  final double radius;

  /// 20–100; blur şiddeti + dolgu opaklığı.
  final double intensity;

  /// Mod rengiyle renkli buz (Prism kartları, tint'li paneller).
  final Color? tint;
  final double tintStrength;

  /// Dış gölge (yüzen kart hissi). Pill/ikon karoları `false` kullanır.
  final bool elevated;

  /// Gerçek backdrop blur. Kapatılırsa dolgu opaklığı artırılarak taklit edilir.
  final bool blur;

  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final br = BorderRadius.circular(radius);

    // hand-off eşlemesi: blur 7+i*0.26 px (CSS) → Flutter sigma ≈ px/2.
    final blurPx = 7 + intensity * 0.26;
    // Dolgu opaklığı.
    double fillA = dark ? 0.05 + intensity * 0.0020 : 0.30 + intensity * 0.0042;
    Color fill = Colors.white.withValues(alpha: fillA);
    if (tint != null) {
      fillA =
          (dark ? 0.14 + intensity * 0.0016 : 0.16 + intensity * 0.0012) *
          tintStrength;
      fill = tint!.withValues(alpha: fillA);
    }
    // Blur kapalıysa camın "topladığı" ışığı dolguya ekle.
    if (!blur) {
      fill = fill.withValues(alpha: (fillA + (dark ? 0.10 : 0.22)).clamp(0, 1));
    }

    final edge = dark
        ? const Color.fromRGBO(255, 255, 255, 0.16)
        : const Color.fromRGBO(255, 255, 255, 0.7);
    final glare = dark
        ? const Color.fromRGBO(255, 255, 255, 0.12)
        : const Color.fromRGBO(255, 255, 255, 0.5);

    Widget fillLayer = ColoredBox(color: fill);
    if (blur) {
      fillLayer = BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(
            sigmaX: blurPx * 0.5,
            sigmaY: blurPx * 0.5,
          ),
          inner: const ui.ColorFilter.matrix(_saturate190),
        ),
        child: fillLayer,
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: elevated
          ? BoxDecoration(
              borderRadius: br,
              boxShadow: dark
                  ? const [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.45),
                        blurRadius: 30,
                        offset: Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.35),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : const [
                      // Nötr ink gölge (eski 60,50,120 mor-mavi pasifken arka
                      // plandan ayrışıyordu — Mehmet 2026-06-13). Marka mürekkebi.
                      BoxShadow(
                        color: Color.fromRGBO(40, 38, 66, 0.10),
                        blurRadius: 30,
                        offset: Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Color.fromRGBO(40, 38, 66, 0.05),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
            )
          : null,
      child: ClipRRect(
        borderRadius: br,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(child: fillLayer),
            // Tint bloom — sol-üstten renkli "kırılma" parıltısı.
            if (tint != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: tintStrength,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.6, -1),
                          radius: 1.2,
                          colors: [
                            tint!.withValues(alpha: dark ? 0.34 : 0.28),
                            tint!.withValues(alpha: 0),
                          ],
                          stops: const [0, 0.6],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Üst parlama şeridi (top %42).
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.42,
                    widthFactor: 0.88,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            glare.withValues(alpha: glare.a * 0.7),
                            glare.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Hairline kenar.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: br,
                    border: Border.all(color: edge, width: 0.5),
                  ),
                ),
              ),
            ),
            Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ],
        ),
      ),
    );
  }

  /// Saturate(1.9) renk matrisi (CSS `saturate(190%)`).
  // s=1.9: r' = (0.213+0.787s)R + 0.715(1-s)G + 0.072(1-s)B …
  static const _saturate190 = <double>[
    1.8283, -0.6435, -0.0648, 0, 0, //
    -0.1917, 1.3565, -0.0648, 0, 0,
    -0.1917, -0.6435, 1.8352, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// Basılınca hafifçe küçülen dokunuş sarmalayıcısı (hand-off `hg-press`:
/// scale .975, 0.18s).
class HgPressable extends StatefulWidget {
  const HgPressable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<HgPressable> createState() => _HgPressableState();
}

class _HgPressableState extends State<HgPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.975 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
