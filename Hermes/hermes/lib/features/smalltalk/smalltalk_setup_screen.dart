import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/engines/translation/translation_tier.dart';
import '../../core/repositories/conversation_repository.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../push_to_talk/push_to_talk_screen.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';
import '../shared/low_ram_warning.dart';
import '../shared/models_required_gate.dart';
import 'smalltalk_screen.dart';

/// SmallTalk **kurulum sihirbazı** — 3 adım: Diller → Yöntem → Mod
/// (liquid-glass hand-off `SetupWizard`, Mercury stili, 2026-06-12).
///
/// Eski üç ekranı (SmallTalkSetupScreen seçim + SmallTalkHandsFreeSetupScreen +
/// LanguageSelectScreen[pushToTalk]) tek akışta birleştirir:
/// - **Eller serbest** → [SmallTalkScreen] (master/local/narration/quality;
///   model kapısı o ekranın içinde).
/// - **Bas-konuş** → [PushToTalkScreen] (source/target/tier; model hazır değilse
///   [ModelsRequiredGate] — merkezi indirme kuralı).
///
/// Hand-off'ta olmayan ama üründe var olan **seslendirme (narration)** tercihi
/// Yöntem adımında "Eller serbest" seçiliyken küçük bir anahtar olarak sunulur.
class SmallTalkSetupScreen extends StatefulWidget {
  const SmallTalkSetupScreen({super.key});

  @override
  State<SmallTalkSetupScreen> createState() => _SmallTalkSetupScreenState();
}

enum _Voice { handsfree, pushtotalk }

class _SmallTalkSetupScreenState extends State<SmallTalkSetupScreen> {
  static const _languages = <String, String>{
    'tr': 'Türkçe',
    'en': 'İngilizce',
    'es': 'İspanyolca',
    'de': 'Almanca',
    'fr': 'Fransızca',
  };
  static const _steps = ['Diller', 'Yöntem', 'Mod'];

  int _step = 0;
  String _master = 'tr';
  String _local = 'en';
  _Voice _voice = _Voice.handsfree;
  bool _narration = false;

  /// Eller serbest katmanı (fast/full/fullPlus).
  SessionQuality _hfQuality = SessionQuality.full;

  /// Bas-konuş çeviri katmanı.
  TranslationTier _pttTier = TranslationTier.mlkit;

  double _swapTurns = 0;

  bool get _heavySelected => _voice == _Voice.handsfree
      ? _hfQuality == SessionQuality.fullPlus
      : _pttTier == TranslationTier.nllb;

  void _cycle(bool master) {
    final keys = _languages.keys.toList();
    setState(() {
      if (master) {
        _master = keys[(keys.indexOf(_master) + 1) % keys.length];
      } else {
        _local = keys[(keys.indexOf(_local) + 1) % keys.length];
      }
    });
  }

  void _swap() => setState(() {
    _swapTurns += 0.5;
    final t = _master;
    _master = _local;
    _local = t;
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
    if (_master == _local) return; // savunma; UI zaten engeller
    // iOS savunma: "Hızlı" (Vosk×2) tier'ı iOS'te kurulumda gizli — yine de
    // seçili kalmışsa (örn. eski state) Tam'a düşür ki Vosk başlatılmasın.
    if (Platform.isIOS && _hfQuality == SessionQuality.fast) {
      _hfQuality = SessionQuality.full;
    }
    // F1 — ağır katman (NLLB) düşük-RAM cihazda OOM uyarısı.
    if (_heavySelected) {
      final proceed = await confirmHeavyTierOnLowRam(context);
      if (!proceed || !mounted) return;
    }
    if (_voice == _Voice.handsfree) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SmallTalkScreen(
            masterLang: _master,
            localLang: _local,
            narrationEnabled: _narration,
            quality: _hfQuality,
          ),
        ),
      );
      return;
    }
    // Bas-konuş: model kapısı (merkezi indirme — eksikse Ayarlar'a yönlendir).
    final ready = await isTierReady(_pttTier, _master, _local);
    if (!mounted) return;
    if (!ready) {
      final missing = _pttTier == TranslationTier.nllb
          ? ['NLLB-600M']
          : [
              '${_languages[_master]} (ML Kit)',
              '${_languages[_local]} (ML Kit)',
            ];
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PttModelsGateScreen(missing: missing),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PushToTalkScreen(
          sourceLanguage: _master,
          targetLanguage: _local,
          tier: _pttTier,
          hfToken: null,
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
                  1 => _stepMethod(p),
                  _ => _stepQuality(p),
                },
              ),
            ),
            const SizedBox(height: 18),
            HgGradientButton(
              label: _step < 2 ? 'Devam' : 'Başlat',
              icon: HgIcon(
                _step < 2 ? HgIcons.chevron : HgIcons.play,
                size: _step < 2 ? 18 : 16,
                color: Colors.white,
                strokeWidth: 2.4,
              ),
              onTap: _master == _local && _step == 0 ? null : _next,
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
                  'SMALLTALK · KURULUM',
                  style: HgType.sans(
                    11,
                    weight: 600,
                    color: p.accent.withValues(alpha: 0.95),
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
                        gradient: LinearGradient(colors: [p.accent, p.visual]),
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
            'Sen (master) ve karşı taraf (local) için dilleri seç.',
            style: HgType.sans(13.5, color: p.sub, height: 1.4),
          ),
        ),
        Stack(
          children: [
            Column(
              children: [
                _langCard(p, 'Sen · master', _master, () => _cycle(true)),
                const SizedBox(height: 12),
                _langCard(
                  p,
                  'Karşı taraf · local',
                  _local,
                  () => _cycle(false),
                ),
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
                          color: p.accent,
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
        if (_master == _local)
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
                color: p.accent.withValues(alpha: p.noir ? 0.22 : 0.14),
              ),
              child: Center(
                child: Text(
                  code.toUpperCase(),
                  style: HgType.sans(
                    14,
                    weight: 800,
                    color: p.accent,
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

  Widget _stepMethod(HgPalette p) {
    return SingleChildScrollView(
      key: const ValueKey(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HgSerifTitle('Nasıl konuşacaksınız?'),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            child: Text(
              'Etkileşim yöntemini seç — istediğin zaman değiştirebilirsin.',
              style: HgType.sans(13.5, color: p.sub, height: 1.4),
            ),
          ),
          HgChoiceCard(
            icon: HgIcons.sparkle,
            title: 'Eller serbest',
            tag: 'Otomatik',
            desc:
                'Telefon ikinizi de dinler, çeviriyi otomatik seslendirir. Butona basmak yok.',
            selected: _voice == _Voice.handsfree,
            onTap: () => setState(() => _voice = _Voice.handsfree),
          ),
          const SizedBox(height: 13),
          HgChoiceCard(
            icon: HgIcons.screen,
            title: 'Bas-konuş',
            tag: 'Sırayla',
            desc: 'Ekran ikiye bölünür; konuşmak için kendi yarına basılı tut.',
            selected: _voice == _Voice.pushtotalk,
            accent: p.smalltalk,
            onTap: () => setState(() => _voice = _Voice.pushtotalk),
          ),
          if (_voice == _Voice.handsfree) ...[
            const SizedBox(height: 13),
            HgGlass(
              radius: 16,
              elevated: false,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
              child: Row(
                children: [
                  HgIcon(
                    HgIcons.headphone,
                    size: 20,
                    color: p.sub,
                    strokeWidth: 1.8,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Karşının çevirisi kulaklığına seslendirilsin',
                      style: HgType.sans(13, color: p.text, height: 1.35),
                    ),
                  ),
                  Switch(
                    value: _narration,
                    activeTrackColor: p.accent,
                    onChanged: (v) => setState(() => _narration = v),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepQuality(HgPalette p) {
    final handsfree = _voice == _Voice.handsfree;
    return SingleChildScrollView(
      key: const ValueKey(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HgSerifTitle('Kalite'),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            child: Text(
              'Hız mı, doğruluk mu? İstediğin zaman değiştirebilirsin.',
              style: HgType.sans(13.5, color: p.sub, height: 1.4),
            ),
          ),
          if (handsfree) ...[
            // "Hızlı" hands-free tier'ı Vosk×2'ye dayanır; `vosk_flutter_2`'nin
            // iOS implementasyonu yok → iOS'te gizle (yalnız Whisper tabanlı
            // Tam/Tam+ kalır; varsayılan zaten `full`).
            if (!Platform.isIOS) ...[
              HgQualityCard(
                icon: HgIcons.bolt,
                title: 'Hızlı',
                meta: 'Vosk + ML Kit · en düşük gecikme',
                selected: _hfQuality == SessionQuality.fast,
                onTap: () => setState(() => _hfQuality = SessionQuality.fast),
              ),
              const SizedBox(height: 11),
            ],
            HgQualityCard(
              icon: HgIcons.target,
              title: 'Tam',
              meta: 'Whisper + ML Kit · dengeli (önerilen)',
              selected: _hfQuality == SessionQuality.full,
              onTap: () => setState(() => _hfQuality = SessionQuality.full),
            ),
            const SizedBox(height: 11),
            HgQualityCard(
              icon: HgIcons.layers,
              title: 'Tam+',
              meta: 'Whisper + NLLB · en yüksek doğruluk',
              selected: _hfQuality == SessionQuality.fullPlus,
              onTap: () => setState(() => _hfQuality = SessionQuality.fullPlus),
            ),
            if (Platform.isIOS)
              Padding(
                padding: const EdgeInsets.only(top: 11),
                child: Text(
                  'Hızlı mod iOS\'te yakında — canlı çevrimdışı motor '
                  'entegrasyonu sürüyor.',
                  style: HgType.sans(12, color: p.faint, height: 1.4),
                ),
              ),
          ] else ...[
            HgQualityCard(
              icon: HgIcons.bolt,
              title: 'Hızlı',
              meta: 'ML Kit · anında',
              selected: _pttTier == TranslationTier.mlkit,
              onTap: () => setState(() => _pttTier = TranslationTier.mlkit),
            ),
            const SizedBox(height: 11),
            HgQualityCard(
              icon: HgIcons.layers,
              title: 'Akıllı',
              meta: 'NLLB · en kaliteli çevrimdışı çeviri',
              selected: _pttTier == TranslationTier.nllb,
              onTap: () => setState(() => _pttTier = TranslationTier.nllb),
            ),
          ],
          if (_heavySelected) ...[
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

/// Bas-konuş model kapısı ekranı (mesh + [ModelsRequiredGate]).
class _PttModelsGateScreen extends StatelessWidget {
  const _PttModelsGateScreen({required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return HgScreen(
      scroll: false,
      child: ModelsRequiredGate(
        missing: missing,
        // Ayarlar'dan dönünce kullanıcı "Geri" ile sihirbaza döner ve Başlat'a
        // yeniden basar (kontrol orada tekrarlanır).
        onRecheck: () async {},
      ),
    );
  }
}
