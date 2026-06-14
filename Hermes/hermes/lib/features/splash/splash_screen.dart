import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../core/services/ram_manager.dart';
import '../../core/theme/hg_background.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../shared/hg_icons.dart';

/// Açılış (splash) ekranı — düz siyah yerine şık animasyonlu giriş (Mehmet
/// 2026-06-13). Logo fade+scale ile belirir, altta ince yükleniyor şeridi.
///
/// Aynı anda NLLB **arka planda** RAM'e alınır ([RamManager.preloadNllb]) — en
/// çok kullanılan motor. Kullanıcı NLLB'nin yüklenmesini BEKLEMEZ: splash kısa
/// (~1.7s) gösterilir, ardından [next]'e geçilir; NLLB yüklemesi arkada sürer.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  /// Splash sonrası açılacak ekran (Home).
  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  /// Ağır başlatma splash GÖRÜNÜRKEN, arka planda yapılır (uzun siyah ekran
  /// olmaz; navigasyon init'i beklemez — crunch çok sonra). Splash ~1.7s.
  Future<void> _boot() async {
    unawaited(_initEngines());
    await Future.delayed(const Duration(milliseconds: 1700));
    _goNext();
  }

  Future<void> _initEngines() async {
    try {
      // LLM (özet) için gerekli; arka planda hazırlanır.
      await FlutterGemma.initialize();
    } catch (_) {
      // init başarısızsa uygulama yine açılır; LLM kullanımı kendi hatasını verir.
    }
    // NLLB'yi arka planda RAM'e al — beklenmez.
    unawaited(RamManager.preloadNllb());
  }

  void _goNext() {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => widget.next,
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    final scale = Tween<double>(begin: 0.86, end: 1).animate(
      CurvedAnimation(parent: _intro, curve: Curves.easeOutBack),
    );
    return Scaffold(
      body: HgMeshBackground(
        child: Center(
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ἙΡΜΗΣ',
                    style: HgType.eyebrow(p.accent.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hermes',
                        style: HgType.serif(
                          54,
                          weight: 600,
                          color: p.text,
                          letterSpacing: 0.5,
                          height: 0.95,
                        ),
                      ),
                      const SizedBox(width: 12),
                      HgIcon(
                        HgIcons.wings,
                        size: 32,
                        color: p.accent,
                        strokeWidth: 1.4,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sözü taşıyan haberci',
                    style: HgType.serif(
                      16,
                      weight: 500,
                      color: p.sub,
                      italic: true,
                    ),
                  ),
                  const SizedBox(height: 34),
                  _loadingBar(p),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// İnce, soldan sağa kayan parıltı şeridi (yükleniyor hissi).
  Widget _loadingBar(HgPalette p) {
    return SizedBox(
      width: 140,
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: p.hairline),
            ),
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _pulse.value;
                return Align(
                  alignment: Alignment(-1 + 2 * t, 0),
                  child: FractionallySizedBox(
                    widthFactor: 0.4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            p.accent.withValues(alpha: 0),
                            p.accent,
                            p.accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
