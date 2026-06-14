import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/engines/translation/llm_translation_engine.dart';
import '../../core/engines/translation/translation_tier.dart';
import '../../core/models/nllb_model_manager.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../settings/settings_screen.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';

/// Çeviri motoru seçici — gösterilecek katmanlar [tiers] ile belirlenir
/// (varsayılan **MLKit + NLLB**). Her katman için yalnızca "hazır mı" gösterilir;
/// **indirme YAPILMAZ** (Mehmet 2026-06-09: tüm indirmeler Ayarlar'dan). Model
/// eksikse "Ayarları Aç" ile [SettingsScreen]'e yönlendirir; dönünce yeniden
/// kontrol eder. Seçilen katmanın hazırlığı [onChanged] ile bildirilir (parent
/// "Devam"ı gate'ler).
///
/// Ders/Konferans, Bas Konuş, SmallTalk, Manuel ve Görsel Çeviri'de kullanılır.
class ModelTierSelector extends StatefulWidget {
  const ModelTierSelector({
    super.key,
    required this.initialTier,
    required this.onChanged,
    this.sourceLang,
    this.targetLang,
    this.tiers = const [TranslationTier.mlkit, TranslationTier.nllb],
    this.accent,
    this.intensity = 74,
  });

  final TranslationTier initialTier;

  /// Seçili segment + "Ayarları Aç" aksanı (verilmezse palet accent).
  final Color? accent;

  /// Cam yoğunluğu (20–100). Foto üstü overlay'de düşük → daha şeffaf.
  final double intensity;

  /// Hazırlık için dil çifti (MLKit dil-paketi başına kontrol eder).
  /// `null` (örn. OCR "otomatik algıla") → o yön çalışma anına bırakılır.
  final String? sourceLang;
  final String? targetLang;

  /// Gösterilecek katmanlar. Varsayılan: Hızlı(MLKit) + Akıllı(NLLB).
  final List<TranslationTier> tiers;

  /// (seçili katman, hfToken=null, hazır mı). İndirme Ayarlar'a taşındığından
  /// token artık burada toplanmaz — geriye uyum için imza korunur (null geçilir).
  final void Function(TranslationTier tier, String? hfToken, bool ready)
  onChanged;

  @override
  State<ModelTierSelector> createState() => _ModelTierSelectorState();
}

class _ModelTierSelectorState extends State<ModelTierSelector> {
  late final List<TranslationTier> _tiers = widget.tiers.isEmpty
      ? [TranslationTier.mlkit]
      : widget.tiers;

  late TranslationTier _tier = _tiers.contains(widget.initialTier)
      ? widget.initialTier
      : _tiers.first;
  final NllbModelManager _nllbMgr = NllbModelManager();

  bool _checking = false;
  bool _downloaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant ModelTierSelector old) {
    super.didUpdateWidget(old);
    // Dil çifti değişince (özellikle MLKit dil-paketi) hazırlığı yeniden kontrol et.
    if (old.sourceLang != widget.sourceLang ||
        old.targetLang != widget.targetLang) {
      unawaited(_refresh());
    }
  }

  /// Seçili katmanın hazırlığını kontrol et + parent'ı bilgilendir.
  /// MLKit dahil HER katman gerçek dosya/paket kontrolünden geçer (yanlış "hazır" yok).
  Future<void> _refresh() async {
    setState(() => _checking = true);
    final bool ready;
    if (_tier == TranslationTier.nllb) {
      ready = await _nllbMgr.allDownloaded();
    } else if (_tier == TranslationTier.mlkit) {
      ready = await isTierReady(
        TranslationTier.mlkit,
        widget.sourceLang,
        widget.targetLang,
      );
    } else {
      // LLM (gemma/qwen) — readiness token gerektirmez.
      ready = await LlmTranslationEngine(
        _tier == TranslationTier.gemma ? LlmModelDef.gemma : LlmModelDef.qwen,
      ).isLanguageReady('en');
    }
    if (!mounted) return;
    setState(() {
      _downloaded = ready;
      _checking = false;
    });
    widget.onChanged(_tier, null, ready);
  }

  void _pick(TranslationTier tier) {
    if (tier == _tier) return;
    setState(() {
      _tier = tier;
      _downloaded = false;
    });
    unawaited(_refresh());
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final a = widget.accent ?? p.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ÇEVİRİ MOTORU',
          style: HgType.sans(
            11,
            weight: 600,
            color: p.faint,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 7),
        HgGlass(
          radius: 16,
          elevated: false,
          intensity: widget.intensity,
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (final t in _tiers) Expanded(child: _segment(p, a, t)),
            ],
          ),
        ),
        const SizedBox(height: 9),
        _statusArea(p, a),
      ],
    );
  }

  Widget _segment(HgPalette p, Color a, TranslationTier t) {
    final selected = t == _tier;
    return HgPressable(
      onTap: () => _pick(t),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: selected
              ? a.withValues(alpha: p.noir ? 0.3 : 0.2)
              : Colors.transparent,
        ),
        child: Column(
          children: [
            Text(
              t.label,
              style: HgType.sans(
                13.5,
                weight: 700,
                color: selected ? a : p.sub,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              t.hint,
              textAlign: TextAlign.center,
              style: HgType.sans(10, color: p.faint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusArea(HgPalette p, Color a) {
    if (_checking) {
      return Text(
        'kontrol ediliyor…',
        style: HgType.sans(12, color: p.faint),
      );
    }
    if (_downloaded) {
      return Row(
        children: [
          HgIcon(HgIcons.check, size: 15, color: p.live, strokeWidth: 2.4),
          const SizedBox(width: 5),
          Text(
            'Model hazır.',
            style: HgType.sans(12.5, weight: 600, color: p.live),
          ),
        ],
      );
    }
    // İnmemiş → indirme Ayarlar'da. Yönlendir.
    return HgWarnGlass(
      icon: HgIcons.download,
      accent: a,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Model yüklü değil — indirme Ayarlar\'da.',
              style: HgType.sans(12.5, color: p.text, height: 1.35),
            ),
          ),
          const SizedBox(width: 10),
          HgPressable(
            onTap: _openSettings,
            child: HgGlass(
              radius: 12,
              elevated: false,
              intensity: 84,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Ayarları Aç',
                style: HgType.sans(12.5, weight: 700, color: a),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
