import 'dart:async';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/hg_background.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../conference/conference_archive_screen.dart';
import '../conference/conference_setup_screen.dart';
import '../crunch_derisk/crunch_derisk_screen.dart';
import '../db_test/db_test_screen.dart';
import '../dual_mic_test/dual_mic_test_screen.dart';
import '../llm_translate_test/llm_translate_test_screen.dart';
import '../nllb_test/nllb_test_screen.dart';
import '../ocr_translate/ocr_translate_screen.dart';
import '../opus_mt_test/opus_mt_test_screen.dart';
import '../push_to_talk_test/push_to_talk_test_screen.dart';
import '../session_test/session_test_screen.dart';
import '../settings/settings_screen.dart';
import '../shared/hg_icons.dart';
import '../small100_test/small100_test_screen.dart';
import '../smalltalk/smalltalk_archive_screen.dart';
import '../smalltalk/smalltalk_setup_screen.dart';
import '../streaming_test/streaming_test_screen.dart';
import '../vad_test/vad_test_screen.dart';
import '../vosk_en_derisk/vosk_en_derisk_screen.dart';
import '../vosk_test/vosk_test_screen.dart';

/// Ana ekran — **Mercury** treatment (liquid-glass hand-off, 2026-06-12).
/// Editoryal/serif: Yunanca eyebrow + serif "Hermes" markası + kanatlı asa,
/// ince aksan çizgisi, italik tagline, tek glass panelde hairline-bölmeli
/// 4 mod satırı. Kaynak: `prototype/hermes-home.jsx` `MercuryHome`.
///
/// Navigasyon mevcut akışla birebir: Konferans/SmallTalk kendi setup
/// ekranlarına, klasörler arşivlere, Manuel [manualBuilder]'a, Görsel OCR'a.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.manualBuilder});

  /// Manuel Çeviri ekranını üreten builder (main.dart `TranslationTestScreen`
  /// geçer — main.dart ↔ feature circular import'undan kaçınmak için).
  final WidgetBuilder manualBuilder;

  void _push(BuildContext context, WidgetBuilder builder) {
    Navigator.of(context).push(MaterialPageRoute(builder: builder));
  }

  /// Canlı transkript modları (Konferans/SmallTalk) şu an **Vosk** motoruna
  /// dayanıyor; `vosk_flutter_2`'nin iOS implementasyonu YOK → iOS'te açılınca
  /// "platform ios is not supported" hatası veriyordu. iOS'te çirkin hata yerine
  /// nazik "yakında" mesajı göster (sherpa-onnx entegrasyonu beklemede, 2026-06-14).
  void _openLiveMode(BuildContext context, WidgetBuilder builder) {
    if (Platform.isIOS) {
      _showIosSoon(context);
      return;
    }
    _push(context, builder);
  }

  void _showIosSoon(BuildContext context) {
    final p = HgPalette.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.noir ? const Color(0xFF1C1A16) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'iOS\'te yakında',
          style: HgType.serif(20, weight: 600, color: p.text),
        ),
        content: Text(
          'Canlı transkript motoru henüz iOS\'i desteklemiyor; iOS için '
          'çevrimdışı bir streaming motoru entegre ediliyor. Bu arada Manuel '
          've Görsel Çeviri\'yi kullanabilirsin.',
          style: HgType.sans(14, color: p.sub, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Tamam',
              style: HgType.sans(14, weight: 700, color: p.accent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final modes = [
      _ModeRow(
        icon: HgIcons.conference,
        accent: p.conference,
        title: 'Konferans Modu',
        desc: 'Canlı çeviri, transkript ve yapay zekâ özeti',
        onTap: () =>
            _openLiveMode(context, (_) => const ConferenceSetupScreen()),
        onArchive: () => _push(context, (_) => const ConferenceArchiveScreen()),
        archiveTooltip: 'Konferanslarım',
      ),
      _ModeRow(
        icon: HgIcons.smalltalk,
        accent: p.smalltalk,
        title: 'SmallTalk',
        desc: 'Karşılıklı çeviri — bas konuş ya da hands-free',
        onTap: () =>
            _openLiveMode(context, (_) => const SmallTalkSetupScreen()),
        onArchive: () => _push(context, (_) => const SmallTalkArchiveScreen()),
        archiveTooltip: 'SmallTalk\'larım',
      ),
      _ModeRow(
        icon: HgIcons.manual,
        accent: p.manual,
        title: 'Manuel Çeviri',
        desc: 'Yaz, çevir, dinle — menü ve tabela',
        onTap: () => _push(context, manualBuilder),
      ),
      _ModeRow(
        icon: HgIcons.visual,
        accent: p.visual,
        title: 'Görsel Çeviri',
        desc: 'Fotoğraf çek, metni tanı, çevir',
        onTap: () => _push(context, (_) => const OcrTranslateScreen()),
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.noir
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
      child: Scaffold(
        body: HgMeshBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Hg.pad,
                        14,
                        Hg.pad,
                        16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(context, p),
                          // İnce aksan çizgisi.
                          Container(
                            height: 1,
                            margin: const EdgeInsets.only(top: 2, bottom: 18),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  p.accent.withValues(alpha: 0.65),
                                  p.accent.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              'Sözü taşıyan haberci. Bir mod seç.',
                              style: HgType.serif(
                                17,
                                weight: 500,
                                color: p.sub,
                                italic: true,
                              ),
                            ),
                          ),
                          HgGlass(
                            radius: Hg.rCard,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Column(
                              children: [
                                for (var i = 0; i < modes.length; i++)
                                  _modeRow(
                                    p,
                                    modes[i],
                                    divider: i < modes.length - 1,
                                  ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          _footer(p),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, HgPalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FittedBox(scaleDown) → dar cihazlarda otomatik küçülür, overflow
              // olmaz (cihaz-agnostik; Mehmet 2026-06-13).
              const Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: _OnlineBadge(),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hermes',
                        style: HgType.serif(
                          46,
                          weight: 600,
                          color: p.text,
                          letterSpacing: 0.5,
                          height: 0.95,
                        ),
                      ),
                      const SizedBox(width: 11),
                      HgIcon(
                        HgIcons.wings,
                        size: 28,
                        color: p.accent,
                        strokeWidth: 1.4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Geliştirici/de-risk test ekranları menüsü (final'de kaldırılacak —
        // şimdilik basit, özenli tasarım gerekmez; Mehmet 2026-06-13).
        _devMenu(context, p),
        const SizedBox(width: 10),
        // Tema toggle'ı (güneş/ay) — seçim kalıcılaştırılır (setHgThemeMode).
        ValueListenableBuilder<ThemeMode>(
          valueListenable: hgThemeMode,
          builder: (_, mode, _) => HgPressable(
            onTap: () => setHgThemeMode(
              mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
            ),
            child: HgGlass(
              radius: Hg.rPill,
              elevated: false,
              width: Hg.hit,
              height: Hg.hit,
              child: Center(
                child: Icon(
                  mode == ThemeMode.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  size: 21,
                  color: p.text,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        HgPressable(
          onTap: () => _pushSettings(context),
          child: HgGlass(
            radius: Hg.rPill,
            elevated: false,
            width: Hg.hit,
            height: Hg.hit,
            child: Center(
              child: HgIcon(
                HgIcons.settings,
                size: 23,
                color: p.text,
                strokeWidth: 1.7,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _pushSettings(BuildContext context) =>
      _push(context, (_) => const SettingsScreen());

  /// Geliştirici/de-risk test ekranları — cam science ikonu + overflow menüsü.
  /// Final sürümde tamamen kaldırılacak.
  Widget _devMenu(BuildContext context, HgPalette p) {
    return PopupMenuButton<WidgetBuilder>(
      tooltip: 'Geliştirici test ekranları',
      color: p.noir ? const Color(0xFF1C1A16) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (builder) => _push(context, builder),
      itemBuilder: (_) => [
        _devItem(p, Icons.graphic_eq, 'VAD Test (Silero)',
            (_) => const VadTestScreen()),
        _devItem(p, Icons.storage, 'DB Test (Drift + SQLite)',
            (_) => const DbTestScreen()),
        _devItem(p, Icons.headphones, 'Çift Mic Test (6r-d)',
            (_) => const DualMicTestScreen()),
        _devItem(p, Icons.touch_app, 'Bas Konuş Test (6r-e)',
            (_) => const PushToTalkTestScreen()),
        _devItem(p, Icons.record_voice_over, 'Oturum Entegrasyon (6r-h)',
            (_) => const SessionTestScreen()),
        _devItem(p, Icons.subtitles, 'Streaming Test',
            (_) => const StreamingTestScreen()),
        _devItem(p, Icons.translate, 'Vosk Türkçe Test (ASR)',
            (_) => const VoskTestScreen()),
        _devItem(p, Icons.psychology, 'LLM Çeviri (Qwen↔Gemma kıyas)',
            (_) => const LlmTranslateTestScreen()),
        _devItem(p, Icons.hub, 'NLLB Tier2 de-risk',
            (_) => const NllbTestScreen()),
        _devItem(p, Icons.bolt, 'SMaLL-100 fast de-risk',
            (_) => const Small100TestScreen()),
        _devItem(p, Icons.g_translate, 'Opus-MT de-risk',
            (_) => const OpusMtTestScreen()),
        _devItem(p, Icons.compress, 'Crunch Modeli De-risk',
            (_) => const CrunchDeriskScreen()),
        _devItem(p, Icons.record_voice_over, 'Vosk EN De-risk',
            (_) => const VoskEnDeriskScreen()),
      ],
      child: HgGlass(
        radius: Hg.rPill,
        elevated: false,
        width: Hg.hit,
        height: Hg.hit,
        child: Center(child: Icon(Icons.science, size: 21, color: p.text)),
      ),
    );
  }

  PopupMenuItem<WidgetBuilder> _devItem(
    HgPalette p,
    IconData icon,
    String label,
    WidgetBuilder builder,
  ) {
    return PopupMenuItem<WidgetBuilder>(
      value: builder,
      child: Row(
        children: [
          Icon(icon, size: 18, color: p.accent),
          const SizedBox(width: 12),
          Text(label, style: HgType.sans(14, color: p.text)),
        ],
      ),
    );
  }

  Widget _modeRow(HgPalette p, _ModeRow m, {required bool divider}) {
    return HgPressable(
      onTap: m.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: divider
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: p.hairline, width: 0.5),
                ),
              )
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Center(
                child: HgIcon(
                  m.icon,
                  size: 26,
                  color: m.accent,
                  strokeWidth: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title,
                    style: HgType.serif(
                      23,
                      weight: 600,
                      color: p.text,
                      letterSpacing: 0.2,
                      height: 1.05,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      m.desc,
                      style: HgType.sans(
                        12.5,
                        weight: 500,
                        color: p.sub,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (m.onArchive != null)
              Tooltip(
                message: m.archiveTooltip ?? 'Arşiv',
                child: HgPressable(
                  onTap: m.onArchive,
                  // 44px görünmez dokunma hedefi (ikon 17 — hand-off hit kuralı).
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: HgIcon(
                        HgIcons.folder,
                        size: 17,
                        color: p.faint,
                        strokeWidth: 1.6,
                      ),
                    ),
                  ),
                ),
              )
            else
              HgIcon(
                HgIcons.chevron,
                size: 17,
                color: p.faint,
                strokeWidth: 1.8,
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer(HgPalette p) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HgIcon(HgIcons.download, size: 14, color: p.faint, strokeWidth: 1.8),
          const SizedBox(width: 7),
          Text(
            'Modeller Ayarlar\'dan indirilir',
            style: HgType.sans(12, weight: 500, color: p.faint),
          ),
        ],
      ),
    );
  }
}

class _ModeRow {
  const _ModeRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.desc,
    required this.onTap,
    this.onArchive,
    this.archiveTooltip,
  });

  final HgIconData icon;
  final Color accent;
  final String title;
  final String desc;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final String? archiveTooltip;
}

/// Eyebrow rozeti — "ἙΡΜΗΣ · durum" — durum kelimesi desteklenen dillerde
/// fade ile döngüye girer; çevrimiçi=yeşil + "çevrimiçi" dilleri, çevrimdışı=
/// coral + "çevrimdışı" dilleri (Mehmet 2026-06-13: offline kötü değil, şık).
class _OnlineBadge extends StatefulWidget {
  const _OnlineBadge();

  @override
  State<_OnlineBadge> createState() => _OnlineBadgeState();
}

class _OnlineBadgeState extends State<_OnlineBadge> {
  // (çevrimdışı, çevrimiçi) — 10 dil (tr/en/es/fr/de/it/ar/zh/ja/ru). Online ve
  // offline listeleri eşit uzunlukta — ikisi de tüm dilleri döner.
  static const _words = [
    ('ÇEVRİMDIŞI', 'ÇEVRİMİÇİ'), // tr
    ('OFFLINE', 'ONLINE'), // en
    ('SIN CONEXIÓN', 'EN LÍNEA'), // es
    ('HORS LIGNE', 'EN LIGNE'), // fr
    ('OHNE NETZ', 'AM NETZ'), // de
    ('NON IN RETE', 'IN LINEA'), // it
    ('غير متصل', 'متصل'), // ar
    ('离线', '在线'), // zh
    ('オフライン', 'オンライン'), // ja
    ('НЕ В СЕТИ', 'В СЕТИ'), // ru
  ];

  int _i = 0;
  bool _online = false;
  Timer? _cycle;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  final Connectivity _conn = Connectivity();

  @override
  void initState() {
    super.initState();
    // Event-driven bağlantı: ağ değişince ANINDA güncellenir (poll'da takılma yok).
    // Test/eklenti yoksa platform kanalı patlamasın diye hatalar yutulur.
    unawaited(_conn.checkConnectivity().then(_apply).catchError((_) {}));
    _connSub = _conn.onConnectivityChanged.listen(_apply, onError: (_) {});
    _cycle = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _words.length);
    });
  }

  void _apply(List<ConnectivityResult> results) {
    final online = results.any((c) => c != ConnectivityResult.none);
    if (mounted && online != _online) setState(() => _online = online);
  }

  @override
  void dispose() {
    _cycle?.cancel();
    unawaited(_connSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    // Çevrimiçi=yeşil (live), çevrimdışı=coral (accent) — ikisi de şık/olumlu.
    final color = (_online ? p.live : p.accent).withValues(alpha: 0.95);
    final word = _online ? _words[_i].$2 : _words[_i].$1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ἙΡΜΗΣ · ', style: HgType.eyebrow(color)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 650),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          // Çocukları SOLA sabitle: varsayılan layoutBuilder ortalıyor → kısa
          // kelime animasyon sırasında ortada görünüp bitince sola "zıplıyor"
          // (jagged). Sola hizalayınca geçiş boyunca da sonrasında da aynı yer.
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.centerLeft,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          ),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.6),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Text(
            word,
            key: ValueKey('$word-$_online'),
            style: HgType.eyebrow(color),
          ),
        ),
      ],
    );
  }
}
