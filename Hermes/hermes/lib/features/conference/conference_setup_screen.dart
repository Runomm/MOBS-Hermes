import 'package:flutter/material.dart';

import '../../core/engines/translation/translation_tier.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';
import '../shared/low_ram_warning.dart';
import 'conference_screen.dart';

/// Konferans Modu kurulum sihirbazı (K1) — liquid-glass Mercury stili
/// (2026-06-12 restyle; SmallTalk wizard'ıyla aynı kalıp).
///
/// 3 adım: Diller (konuşmacı + çeviri) → Seslendirme (kulaklık/altyazı) →
/// Kalite (Hızlı=MLKit / Akıllı=NLLB). "Başlat" → [ConferenceScreen]
/// (model kapısı + ısınma o ekranda).
class ConferenceSetupScreen extends StatefulWidget {
  const ConferenceSetupScreen({super.key});

  @override
  State<ConferenceSetupScreen> createState() => _ConferenceSetupScreenState();
}

class _ConferenceSetupScreenState extends State<ConferenceSetupScreen> {
  static const _languages = <String, String>{
    'tr': 'Türkçe',
    'en': 'İngilizce',
    'es': 'İspanyolca',
    'de': 'Almanca',
    'fr': 'Fransızca',
  };
  static const _steps = ['Diller', 'Seslendirme', 'Kalite'];

  int _step = 0;
  String _source = 'en';
  String _target = 'tr';
  bool _ttsEnabled = false;
  TranslationTier _tier = TranslationTier.mlkit;
  double _swapTurns = 0;

  void _cycle(bool source) {
    final keys = _languages.keys.toList();
    setState(() {
      if (source) {
        _source = keys[(keys.indexOf(_source) + 1) % keys.length];
      } else {
        _target = keys[(keys.indexOf(_target) + 1) % keys.length];
      }
    });
  }

  void _swap() => setState(() {
    _swapTurns += 0.5;
    final t = _source;
    _source = _target;
    _target = t;
  });

  void _prev() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _next() async {
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    if (_source == _target) return;
    // Düşük-RAM cihazda NLLB + canlı ASR eşzamanlı OOM riski (F1) → uyar.
    if (_tier == TranslationTier.nllb) {
      final proceed = await confirmHeavyTierOnLowRam(context);
      if (!proceed || !mounted) return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConferenceScreen(
          sourceLanguage: _source,
          targetLanguage: _target,
          ttsEnabled: _ttsEnabled,
          tier: _tier,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _prev();
      },
      child: HgScreen(
        scroll: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(p),
            _progress(p),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: const Cubic(0.2, 0.7, 0.2, 1),
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween(
                    begin: const Offset(0.07, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: switch (_step) {
                  0 => _stepLanguages(p),
                  1 => _stepNarration(p),
                  _ => _stepQuality(p),
                },
              ),
            ),
            const SizedBox(height: 18),
            HgGradientButton(
              label: _step < 2 ? 'Devam' : 'Başlat',
              from: p.conference,
              icon: HgIcon(
                _step < 2 ? HgIcons.chevron : HgIcons.play,
                size: _step < 2 ? 18 : 16,
                color: Colors.white,
                strokeWidth: 2.4,
              ),
              onTap: _source == _target && _step == 0 ? null : _next,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(HgPalette p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          HgBackButton(onTap: _prev),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KONFERANS · KURULUM',
                  style: HgType.sans(
                    11,
                    weight: 600,
                    color: p.conference.withValues(alpha: 0.95),
                    letterSpacing: 2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Adım ${_step + 1} / 3 · ${_steps[_step]}',
                    style: HgType.sans(12.5, color: p.sub),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress(HgPalette p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: p.noir
                      ? Colors.white.withValues(alpha: 0.12)
                      : const Color.fromRGBO(40, 38, 66, 0.1),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 400),
                  curve: const Cubic(0.2, 0.7, 0.2, 1),
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 400),
                    curve: const Cubic(0.2, 0.7, 0.2, 1),
                    widthFactor: i <= _step ? 1 : 0,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [p.conference, p.visual],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepLanguages(HgPalette p) {
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HgSerifTitle('Hangi diller?'),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 20),
          child: Text(
            'Konuşmacının dilini ve çeviri dilini seç.',
            style: HgType.sans(13.5, color: p.sub, height: 1.4),
          ),
        ),
        Stack(
          children: [
            Column(
              children: [
                _langCard(p, 'Konuşmacı', _source, () => _cycle(true)),
                const SizedBox(height: 12),
                _langCard(p, 'Çeviri', _target, () => _cycle(false)),
              ],
            ),
            Positioned(
              right: 22,
              top: 0,
              bottom: 0,
              child: Center(
                child: HgPressable(
                  onTap: _swap,
                  child: HgGlass(
                    radius: 16,
                    width: 46,
                    height: 46,
                    intensity: 88,
                    child: Center(
                      child: AnimatedRotation(
                        turns: _swapTurns,
                        duration: const Duration(milliseconds: 400),
                        curve: const Cubic(0.2, 0.7, 0.2, 1),
                        child: HgIcon(
                          HgIcons.arrows,
                          size: 22,
                          color: p.conference,
                          strokeWidth: 1.9,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_source == _target)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'İki dil farklı olmalı.',
              style: HgType.sans(13, color: p.manual, weight: 600),
            ),
          ),
      ],
    );
  }

  Widget _langCard(HgPalette p, String role, String code, VoidCallback onTap) {
    return HgPressable(
      onTap: onTap,
      child: HgGlass(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: p.conference.withValues(alpha: p.noir ? 0.22 : 0.14),
              ),
              child: Center(
                child: Text(
                  code.toUpperCase(),
                  style: HgType.sans(
                    14,
                    weight: 800,
                    color: p.conference,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.toUpperCase(),
                    style: HgType.sans(
                      11.5,
                      weight: 600,
                      color: p.faint,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      _languages[code]!,
                      style: HgType.serif(
                        23,
                        weight: 600,
                        color: p.text,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 52),
              child: Text(
                'değiştir',
                style: HgType.sans(12, weight: 600, color: p.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepNarration(HgPalette p) {
    return SingleChildScrollView(
      key: const ValueKey(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HgSerifTitle('Seslendirme'),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            child: Text(
              'Çeviri kulaklığa sesli okunsun mu? İstersen sadece ekranda '
              'altyazı olarak görürsün.',
              style: HgType.sans(13.5, color: p.sub, height: 1.4),
            ),
          ),
          HgChoiceCard(
            icon: HgIcons.headphone,
            title: 'Kulaklığa seslendir',
            tag: 'Sesli',
            desc: 'Çeviri kulaklığına sesli olarak okunur.',
            selected: _ttsEnabled,
            accent: p.conference,
            onTap: () => setState(() => _ttsEnabled = true),
          ),
          const SizedBox(height: 13),
          HgChoiceCard(
            icon: HgIcons.screen,
            title: 'Sadece altyazı',
            tag: 'Sessiz',
            desc: 'Sessiz — çeviri yalnız ekranda akar.',
            selected: !_ttsEnabled,
            accent: p.conference,
            onTap: () => setState(() => _ttsEnabled = false),
          ),
        ],
      ),
    );
  }

  Widget _stepQuality(HgPalette p) {
    return SingleChildScrollView(
      key: const ValueKey(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HgSerifTitle('Kalite'),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            child: Text(
              'Canlı çeviri motoru. Tam çeviri + özet her durumda oturum '
              'sonunda üretilir.',
              style: HgType.sans(13.5, color: p.sub, height: 1.4),
            ),
          ),
          HgQualityCard(
            icon: HgIcons.bolt,
            title: 'Hızlı',
            meta: 'ML Kit · anında, hafif — düşük gecikme',
            selected: _tier == TranslationTier.mlkit,
            onTap: () => setState(() => _tier = TranslationTier.mlkit),
          ),
          const SizedBox(height: 11),
          HgQualityCard(
            icon: HgIcons.layers,
            title: 'Akıllı',
            meta: 'NLLB · çevrimdışı NMT, daha kaliteli',
            selected: _tier == TranslationTier.nllb,
            onTap: () => setState(() => _tier = TranslationTier.nllb),
          ),
          if (_tier == TranslationTier.nllb) ...[
            const SizedBox(height: 13),
            HgWarnGlass(
              icon: HgIcons.warning,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Yüksek RAM kullanımı. ',
                      style: HgType.sans(12.5, weight: 700, color: p.text),
                    ),
                    TextSpan(
                      text:
                          'Düşük bellekli cihazlarda yavaşlayabilir ya da durabilir.',
                      style: HgType.sans(12.5, color: p.text, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
