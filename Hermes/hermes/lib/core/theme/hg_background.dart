import 'package:flutter/material.dart';

import 'hg_tokens.dart';

/// Cihaz arka planı — katmanlı radyal-gradient **mesh** (hand-off `meshCSS`) +
/// üzerinde yavaşça sürüklenen 4 renkli blob (`MeshOverlay` + `hg-drift-0..3`
/// keyframe'leri: 17–23s ease-in-out sonsuz ileri-geri).
///
/// Reduce-motion (MediaQuery.disableAnimations) açıksa bloblar çapa noktasında
/// sabit durur — hand-off `prefers-reduced-motion` kuralı.
///
/// **ISINMA FIX (2026-06-14, iOS):** Drift animasyonu varsayılan KAPALI. Sebep:
/// animasyonlu mesh her karede yeniden boyanır; arkasında duran tüm [HgGlass]
/// `BackdropFilter` katmanları da her karede yeniden blur'lanmak zorunda kalır.
/// iPhone 17 Pro Max **120Hz ProMotion** ile bu sürekli GPU blur'u cihazı
/// ısıtıyordu (NLLB/Gemma inmeden bile). Statik mesh ile blur yalnız içerik
/// değişince yeniden hesaplanır → ısı/şarj büyük ölçüde düşer. `hg_glass.dart`
/// zaten "mesh statik olduğundan görsel fark küçük" varsayıyordu. Dekoratif drift
/// gerekirse tek tek `motion: true` ile açılabilir.
class HgMeshBackground extends StatefulWidget {
  const HgMeshBackground({super.key, this.child, this.motion = false});

  final Widget? child;

  /// Drift animasyonu (decoratif). Açılırsa bloblar yavaşça sürüklenir —
  /// **dikkat:** sürekli blur yeniden hesabı ısı yaratır (yukarıdaki nota bak).
  final bool motion;

  @override
  State<HgMeshBackground> createState() => _HgMeshBackgroundState();
}

class _HgMeshBackgroundState extends State<HgMeshBackground>
    with TickerProviderStateMixin {
  // hg-drift-0..3 süreleri (sn). alternate → repeat(reverse:true).
  static const _durations = [17, 20, 23, 19];

  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = [
      for (final s in _durations)
        AnimationController(vsync: this, duration: Duration(seconds: s)),
    ];
    _anims = [
      for (final c in _ctrls)
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = widget.motion && !MediaQuery.disableAnimationsOf(context);
    for (final c in _ctrls) {
      if (animate && !c.isAnimating) {
        c.repeat(reverse: true);
      } else if (!animate && c.isAnimating) {
        c.stop();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MeshPainter(p, _anims),
        child: widget.child ?? const SizedBox.expand(),
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.p, this.anims)
      : super(repaint: Listenable.merge(anims));

  final HgPalette p;
  final List<Animation<double>> anims;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final full = Offset.zero & size;

    // Taban: radial-gradient(150% 130% at 50% -12%, c0 0%, c1 55%, c2 100%).
    final base = p.noir
        ? const [Color(0xFF18161D), Color(0xFF100E14), Color(0xFF08070B)]
        : const [Color(0xFFFCFBFF), Color(0xFFF2F0FA), Color(0xFFECEAF6)];
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -1.24), // 50% / -12%
          radius: 1.5,
          colors: base,
          stops: const [0, 0.55, 1],
        ).createShader(full),
    );

    // Statik köşe blobları (meshCSS; ilk yazılan üstte → tersten çiz).
    final statics = p.noir
        ? [
            _StaticBlob(p.second, 0.08, 0.06, 0.94, 0.52, 0.46),
            _StaticBlob(p.accent, 0.12, 0.84, 0.90, 0.60, 0.54),
            _StaticBlob(p.second, 0.10, 0.86, 0.14, 0.50, 0.42),
            _StaticBlob(p.accent, 0.20, 0.16, 0.08, 0.56, 0.46),
          ]
        : [
            _StaticBlob(p.visual, 0.16, 0.46, 0.46, 0.48, 0.38),
            _StaticBlob(p.accent, 0.22, 0.04, 0.95, 0.52, 0.46),
            _StaticBlob(p.smalltalk, 0.24, 0.84, 0.92, 0.58, 0.52),
            _StaticBlob(p.second, 0.30, 0.92, 0.10, 0.52, 0.42),
            _StaticBlob(p.accent, 0.34, 0.12, 0.05, 0.56, 0.46),
          ];
    for (final b in statics) {
      final rect = Rect.fromCenter(
        center: Offset(b.cx * w, b.cy * h),
        width: 2 * b.rx * w,
        height: 2 * b.ry * h,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            // CSS: renk %0'da tam, %60'ta transparan.
            colors: [
              b.color.withValues(alpha: b.alpha),
              b.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.6],
          ).createShader(rect),
      );
    }

    // Drift blobları (MeshOverlay + hg-drift keyframe'leri). CSS translate
    // yüzdesi blob'un KENDİ boyutuna göre; from=(-50,-50) merkezde demek.
    final drifters = [
      _Drifter(p.accent, p.noir ? 0.30 : 0.30, 0.32, 0.20, 400, 0.78, 0.38,
          1.18),
      _Drifter(p.second, p.noir ? 0.16 : 0.26, 0.70, 0.34, 380, -0.42, 0.68,
          1.12),
      _Drifter(p.smalltalk, p.noir ? 0.13 : 0.24, 0.58, 0.78, 430, 0.32,
          -0.28, 1.20),
      _Drifter(p.visual, p.noir ? 0.13 : 0.20, 0.24, 0.72, 380, -0.38, -0.20,
          1.15),
    ];
    for (var i = 0; i < drifters.length; i++) {
      final d = drifters[i];
      final t = anims[i].value;
      final scale = 1 + (d.scaleTo - 1) * t;
      final r = d.size / 2 * scale;
      final center = Offset(
        d.cx * w + d.dx * d.size * t,
        d.cy * h + d.dy * d.size * t,
      );
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = p.noir ? BlendMode.screen : BlendMode.srcOver
          ..shader = RadialGradient(
            colors: [
              d.color.withValues(alpha: d.alpha),
              d.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.7],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.p != p;
}

class _StaticBlob {
  const _StaticBlob(this.color, this.alpha, this.cx, this.cy, this.rx, this.ry);
  final Color color;
  final double alpha;
  final double cx, cy; // merkez (ekran oranı)
  final double rx, ry; // yarıçap (genişlik/yükseklik oranı)
}

class _Drifter {
  const _Drifter(this.color, this.alpha, this.cx, this.cy, this.size, this.dx,
      this.dy, this.scaleTo);
  final Color color;
  final double alpha;
  final double cx, cy; // çapa (ekran oranı)
  final double size; // dp (CSS px)
  final double dx, dy; // hedef ofset (blob boyutu oranı, from→to farkı)
  final double scaleTo;
}
