import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'core/engines/stt/stt_engine.dart';
import 'core/engines/stt/whisper_cpp_engine.dart';
import 'core/engines/translation/google_mlkit_engine.dart';
import 'core/engines/translation/translation_engine.dart';
import 'core/engines/translation/translation_tier.dart';
import 'core/engines/tts/native_tts_engine.dart';
import 'core/engines/tts/tts_engine.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/hg_glass.dart';
import 'core/theme/hg_tokens.dart';
import 'core/theme/hg_typography.dart';
import 'features/shared/hg_icons.dart';
import 'features/shared/hg_widgets.dart';
import 'features/home/home_screen.dart';
import 'features/mode_entry/model_tier_selector.dart';
import 'features/splash/splash_screen.dart';

void main() async {
  // Crash guard (Mehmet 2026-06-13: "hata oluşsa bile app crash olmamalı"):
  // build/widget hatalarında kırmızı çökme ekranı yerine dostça mesaj göster.
  // (Native OOM/signal-9'u Dart yakalayamaz — onu RAM disiplini azaltır.)
  ErrorWidget.builder = (details) => const _FriendlyError();

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Kayıtlı tema modunu yükle (hızlı — prefs). Ağır `FlutterGemma.initialize`
      // runApp'ten ÖNCE DEĞİL: splash sırasında yapılır → ilk kare (animasyonlu
      // splash) hemen çizilir, uzun siyah ekran olmaz (Mehmet 2026-06-13).
      await loadHgThemeMode();
      // Tüm Hermes modları portrait — tasarım gereği landscape lock zorunlu.
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      );
      runApp(const HermesApp());
    },
    (error, stack) {
      // Yakalanmamış async hata — logla, çökme yerine yut.
      debugPrint('Hermes: yakalanmamış hata: $error');
    },
  );
}

/// Build/widget hatasında kırmızı çökme kutusu yerine gösterilen dostça ekran.
class _FriendlyError extends StatelessWidget {
  const _FriendlyError();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF100E14),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFE2674A),
              size: 42,
            ),
            SizedBox(height: 16),
            Text(
              'Cihazınız şu anda tam kapasite çalışıyor.\n\n'
              'Lütfen biraz sonra tekrar deneyin veya arka planda çalışan '
              'diğer uygulamaları kapatın.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFF2ECDC),
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HermesApp extends StatelessWidget {
  const HermesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // hgThemeMode: Home'daki geçici güneş/ay toggle'ı (liquid-glass Noir
    // denemesi). Varsayılan açık; kalıcılaştırma UI restyle bitince.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: hgThemeMode,
      builder: (_, mode, _) => MaterialApp(
        title: 'Hermes',
        debugShowCheckedModeBanner: false,
        theme: hermesLightTheme,
        darkTheme: hermesNoirTheme,
        themeMode: mode,
        // Overscroll'da mor glow/stretch yanıp sönmesi (Mehmet 2026-06-13: "çok
        // çirkin") → kaldırıldı; liquid-glass'te çıplak glow yeri yok.
        scrollBehavior: const _NoGlowScrollBehavior(),
        // Gündüz/gece geçişi yumuşak (Mehmet 2026-06-14: "bir anda yanıp sönmesin").
        // _ThemeFade eski temayı anlık görüntüleyip üstte yavaşça soldurur.
        builder: (context, child) =>
            _ThemeFade(child: child ?? const SizedBox.shrink()),
        home: SplashScreen(
          next: HomeScreen(manualBuilder: (_) => const TranslationTestScreen()),
        ),
      ),
    );
  }
}

/// Tema (gündüz↔gece) değişiminde **yumuşak crossfade**. [hgThemeMode] değişince
/// MaterialApp yeni temayla yeniden çizilir; bu da renkleri **anında** çevirir
/// (HgPalette `Theme.brightness`'tan türer → tween yok → "yanıp sönme"). Çözüm:
/// değişim ANINDA eski kareyi `toImageSync` ile yakala, üstte göster, yeni tema
/// altta çizilirken eski görüntüyü ~0.5s solarak kaldır → göz için yavaş geçiş.
class _ThemeFade extends StatefulWidget {
  const _ThemeFade({required this.child});
  final Widget child;
  @override
  State<_ThemeFade> createState() => _ThemeFadeState();
}

class _ThemeFadeState extends State<_ThemeFade>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850), // Mehmet 2026-06-14: biraz daha yavaş
  );
  ui.Image? _snapshot;

  @override
  void initState() {
    super.initState();
    hgThemeMode.addListener(_onThemeChange);
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() {
          _snapshot?.dispose();
          _snapshot = null;
        });
      }
    });
  }

  /// Tema değişti — yeni MaterialApp build'i bu kareye işlenmeden ÖNCE (notify
  /// senkron, rebuild ertelenmiş) eski temayı yakala.
  void _onThemeChange() {
    final boundary =
        _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.attached) return;
    try {
      // Tam DPR (ProMotion 3×) gereksiz pahalı → 2×'le sınırla (geçişte fark yok).
      final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
      final img = boundary.toImageSync(pixelRatio: dpr > 2.0 ? 2.0 : dpr);
      setState(() {
        _snapshot?.dispose();
        _snapshot = img;
      });
      _ctrl.forward(from: 0);
    } catch (_) {
      // Yakalama başarısızsa animasyonsuz geç (çökme yok).
    }
  }

  @override
  void dispose() {
    hgThemeMode.removeListener(_onThemeChange);
    _ctrl.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return Stack(
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        if (snap != null)
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: Tween<double>(begin: 1, end: 0).animate(
                  CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
                ),
                child: RawImage(image: snap, fit: BoxFit.cover),
              ),
            ),
          ),
      ],
    );
  }
}

/// Material overscroll göstergesini (glow + stretch) tamamen kapatır.
class _NoGlowScrollBehavior extends MaterialScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class TranslationTestScreen extends StatefulWidget {
  const TranslationTestScreen({super.key});

  @override
  State<TranslationTestScreen> createState() => _TranslationTestScreenState();
}

class _TranslationTestScreenState extends State<TranslationTestScreen> {
  final TextEditingController _inputController = TextEditingController(
    text: 'Hello world, how are you today?',
  );

  // Strategy Pattern motorları — çeviri katmanı seçilebilir (MLKit / NLLB).
  TranslationEngine _translationEngine = GoogleMLKitEngine();
  TranslationTier _tier = kManualDefaultTier;
  String? _hfToken;
  final SttEngine _sttEngine = WhisperCppEngine();
  final TtsEngine _ttsEngine = NativeOsTtsEngine();
  final AudioRecorder _recorder = AudioRecorder();

  String _fromCode = 'en';
  String _toCode = 'tr';
  String _result = '';
  String _status = 'Hazır';

  bool _isRecording = false;
  bool _isBusy = false; // transcribe veya translate sürerken
  bool _isSpeaking = false;
  bool _autoSpeak = true; // çeviri biter bitmez otomatik seslendir

  String? _currentRecordingPath;

  /// Dil kodu → cihazda paket indirilmiş mi?
  /// null = henüz sorulmadı (yükleniyor).
  final Map<String, bool?> _languageReady = {};

  static const Map<String, String> _languages = {
    'en': 'İngilizce',
    'tr': 'Türkçe',
    'es': 'İspanyolca',
    'fr': 'Fransızca',
    'de': 'Almanca',
    'it': 'İtalyanca',
  };

  @override
  void initState() {
    super.initState();
    // Açılışta her dilin indirilmiş olup olmadığını öğren.
    for (final code in _languages.keys) {
      _languageReady[code] = null;
    }
    unawaited(_refreshLanguageStates());
  }

  Future<void> _refreshLanguageStates() async {
    for (final code in _languages.keys) {
      try {
        final ready = await _translationEngine.isLanguageReady(code);
        if (!mounted) return;
        setState(() => _languageReady[code] = ready);
      } catch (_) {
        if (!mounted) return;
        setState(() => _languageReady[code] = false);
      }
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    unawaited(_translationEngine.dispose());
    unawaited(_sttEngine.dispose());
    unawaited(_ttsEngine.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  // ---------- TRANSLATE ----------

  Future<void> _translate(String text) async {
    if (text.isEmpty) return;

    setState(() {
      _isBusy = true;
      _status = 'Çeviriliyor (ilk seferde model indirilebilir)…';
      _result = '';
    });

    try {
      final translated = await _translationEngine.translate(
        text,
        _fromCode,
        _toCode,
      );
      if (!mounted) return;
      setState(() {
        _result = translated;
        _status =
            '${_translationEngine.engineName} · '
            '${_translationEngine.isOfflineCapable ? "offline" : "online"}';
        _isBusy = false;
      });

      if (_autoSpeak) {
        unawaited(_speak(translated));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = '';
        _status = 'Çeviri hatası: $e';
        _isBusy = false;
      });
    }
  }

  Future<void> _onTranslatePressed() =>
      _translate(_inputController.text.trim());

  /// Çeviri katmanı değişince motoru yeniden kur (MLKit ↔ NLLB).
  void _onTierChanged(TranslationTier tier, String? token, bool ready) {
    if (tier == _tier && token == _hfToken) return;
    final old = _translationEngine;
    setState(() {
      _tier = tier;
      _hfToken = token;
      _translationEngine = createTranslationEngine(tier, hfToken: token);
    });
    unawaited(old.dispose());
    unawaited(_refreshLanguageStates());
  }

  // ---------- TTS ----------

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    try {
      setState(() {
        _isSpeaking = true;
        _status = '${_ttsEngine.engineName} · seslendiriliyor…';
      });
      await _ttsEngine.speak(text, _toCode);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'TTS hatası: $e');
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _onSpeakPressed() async {
    if (_isSpeaking) {
      await _ttsEngine.stop();
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    } else {
      await _speak(_result);
    }
  }

  // ---------- RECORD + TRANSCRIBE ----------

  Future<void> _onMicPressed() async {
    if (_isRecording) {
      await _stopRecordingAndProcess();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _status = 'Mikrofon izni reddedildi.');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/hermes_rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(const RecordConfig(), path: path);

      _currentRecordingPath = path;
      setState(() {
        _isRecording = true;
        _status = 'Dinleniyor… Konuş ve tekrar dokun.';
        _result = '';
      });
    } catch (e) {
      setState(() {
        _isRecording = false;
        _status = 'Kayıt başlatılamadı: $e';
      });
    }
  }

  Future<void> _stopRecordingAndProcess() async {
    try {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _isBusy = true;
        _status = 'Transkript ediliyor… (Whisper)';
      });

      final audioPath = path ?? _currentRecordingPath;
      if (audioPath == null || !File(audioPath).existsSync()) {
        setState(() {
          _isBusy = false;
          _status = 'Kayıt dosyası bulunamadı.';
        });
        return;
      }

      final transcript = await _sttEngine.transcribeFile(
        audioPath,
        language: _fromCode,
      );

      if (!mounted) return;
      setState(() {
        _inputController.text = transcript;
        _status = 'Transkript hazır, çeviriliyor…';
      });

      // Otomatik çeviri
      await _translate(transcript);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = 'Transkript hatası: $e';
      });
    }
  }

  /// Kaynak ↔ hedef dilini değiştir (her ikisinin durumu zaten biliniyor).
  void _swapLangs() {
    setState(() {
      final t = _fromCode;
      _fromCode = _toCode;
      _toCode = t;
    });
  }

  /// Dil seçimi: 6 dilin liquid-glass alt sayfası (ready/indir göstergeli).
  Future<void> _pickLanguage(bool isSource) async {
    final selected = isSource ? _fromCode : _toCode;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LangPickerSheet(
        languages: _languages,
        ready: _languageReady,
        sizeMbOf: _translationEngine.estimatedDownloadSizeMb,
        selected: selected,
        title: isSource ? 'Kaynak dil' : 'Hedef dil',
        onPick: (code) {
          Navigator.pop(ctx);
          unawaited(_handleLanguageChange(isSource, code));
        },
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    // Scroll YOK (TextField + IntrinsicHeight çakışmasından kaçın); sonuç alanı
    // Expanded ile kalan dikey alanı doldurur → ekran yukarı toplanmaz, alt boş
    // kalmaz (Mehmet 2026-06-13).
    return HgScreen(
      scroll: false,
      padded: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Hg.pad, 14, Hg.pad, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HgNavHeader(title: 'Manuel Çeviri', sub: 'Yaz, çevir, dinle'),
            _langBar(p),
            const SizedBox(height: 12),
            ModelTierSelector(
              initialTier: _tier,
              sourceLang: _fromCode,
              targetLang: _toCode,
              onChanged: _onTierChanged,
              accent: p.manual,
            ),
            const SizedBox(height: 13),
            _inputCard(p),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(child: _translateButton(p)),
                const SizedBox(width: 11),
                _micButton(p),
              ],
            ),
            const SizedBox(height: 13),
            Expanded(child: _resultArea(p)),
            const SizedBox(height: 12),
            _autoSpeakRow(p),
            const SizedBox(height: 6),
            Text(
              _status,
              style: HgType.sans(12, color: p.faint, height: 1.35),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Dil pill çubuğu — kaynak + swap + hedef (pill'e dokun → dil seç).
  Widget _langBar(HgPalette p) {
    Widget pill(String label, String code, bool isSource) {
      final ready = _languageReady[code];
      return Expanded(
        child: HgPressable(
          onTap: () => _pickLanguage(isSource),
          child: HgGlass(
            radius: 16,
            elevated: false,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Expanded(
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
                          _languages[code] ?? code,
                          style: HgType.sans(15.5, weight: 700, color: p.text),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (ready == true)
                  HgIcon(HgIcons.check, size: 15, color: p.live, strokeWidth: 2.4)
                else if (ready == false)
                  HgIcon(
                    HgIcons.download,
                    size: 15,
                    color: p.faint,
                    strokeWidth: 1.9,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill('Kaynak', _fromCode, true),
        const SizedBox(width: 10),
        HgPressable(
          onTap: _swapLangs,
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
        pill('Hedef', _toCode, false),
      ],
    );
  }

  Widget _inputCard(HgPalette p) {
    return HgGlass(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // Tek çerçeve: TextField'in tema kaynaklı kendi kutusu (fill/border)
      // kapatıldı → HgGlass içinde "2 iç içe kutu" görünümü biter (Mehmet 06-13).
      child: TextField(
        controller: _inputController,
        maxLines: 4,
        minLines: 3,
        enabled: !_isRecording && !_isBusy,
        style: HgType.sans(16, weight: 600, color: p.text, height: 1.4),
        cursorColor: p.manual,
        decoration: InputDecoration(
          isCollapsed: true,
          filled: false,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          hintText: 'Çevrilecek metin (yaz veya konuş)',
          hintStyle: HgType.sans(15, color: p.faint),
        ),
      ),
    );
  }

  Widget _translateButton(HgPalette p) {
    final disabled = _isBusy || _isRecording;
    return HgGradientButton(
      label: _isBusy && !_isRecording ? 'Çeviriliyor…' : 'Çevir',
      from: p.manual,
      to: p.visual,
      onTap: disabled ? null : _onTranslatePressed,
    );
  }

  Widget _micButton(HgPalette p) {
    return HgPressable(
      onTap: _isBusy ? null : _onMicPressed,
      child: HgGlass(
        radius: 16,
        elevated: false,
        width: 54,
        height: 54,
        tint: _isRecording ? p.visual : null,
        child: Center(
          child: HgIcon(
            _isRecording ? HgIcons.stop : HgIcons.mic,
            size: 22,
            color: _isRecording ? p.visual : p.manual,
            strokeWidth: 1.9,
          ),
        ),
      ),
    );
  }

  /// Sonuç alanı — kalan dikey alanı doldurur (Expanded içinde). Boşken soluk
  /// yer tutucu, doluyken kaydırılabilir çeviri + Dinle.
  Widget _resultArea(HgPalette p) {
    final empty = _result.isEmpty;
    return HgGlass(
      radius: 20,
      tint: empty ? null : p.manual,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ÇEVİRİ',
            style: HgType.sans(
              11.5,
              weight: 600,
              color: p.faint,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: empty
                ? Center(
                    child: Text(
                      'Çeviri burada görünür',
                      style: HgType.sans(15, color: p.faint),
                    ),
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      _result,
                      style: HgType.sans(
                        18,
                        weight: 700,
                        color: p.text,
                        height: 1.4,
                      ),
                    ),
                  ),
          ),
          if (!empty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: HgPressable(
                onTap: _isBusy ? null : _onSpeakPressed,
                child: HgGlass(
                  radius: 14,
                  elevated: false,
                  intensity: 84,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HgIcon(
                        _isSpeaking ? HgIcons.stop : HgIcons.speaker,
                        size: 18,
                        color: _isSpeaking ? p.visual : p.manual,
                        strokeWidth: 1.8,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isSpeaking ? 'Durdur' : 'Dinle',
                        style: HgType.sans(14, weight: 700, color: p.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _autoSpeakRow(HgPalette p) {
    return Row(
      children: [
        Switch(
          value: _autoSpeak,
          onChanged: (v) => setState(() => _autoSpeak = v),
          activeThumbColor: p.manual,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Çeviri biter bitmez seslendir',
            style: HgType.sans(13, color: p.sub),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Dili seçer. İndirme YAPMAZ (Mehmet 2026-06-09: indirmeler yalnız Ayarlar'dan).
  /// Dil yüklü değilse kısa bir snackbar ile kullanıcıyı Ayarlar'a yönlendirir;
  /// `ModelTierSelector` da "Ayarları Aç" gösterir.
  Future<void> _handleLanguageChange(bool isSource, String code) async {
    setState(() {
      if (isSource) {
        _fromCode = code;
      } else {
        _toCode = code;
      }
    });
    final ready = _languageReady[code] ?? false;
    if (!ready && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_languages[code] ?? code} yüklü değil — Ayarlar → Çeviri '
            'Dilleri\'nden indirin.',
          ),
        ),
      );
    }
  }
}

/// Dil seçimi alt sayfası — liquid-glass liste, her satır ready/indir göstergeli.
class _LangPickerSheet extends StatelessWidget {
  const _LangPickerSheet({
    required this.languages,
    required this.ready,
    required this.sizeMbOf,
    required this.selected,
    required this.title,
    required this.onPick,
  });

  final Map<String, String> languages;
  final Map<String, bool?> ready;
  final int Function(String code) sizeMbOf;
  final String selected;
  final String title;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final entries = languages.entries.toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Hg.pad, 0, Hg.pad, 16),
        child: HgGlass(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: p.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(title, style: HgType.serif(22, weight: 600, color: p.text)),
              const SizedBox(height: 6),
              for (var i = 0; i < entries.length; i++)
                _row(p, entries[i].key, entries[i].value, i < entries.length - 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(HgPalette p, String code, String name, bool divider) {
    final isReady = ready[code] == true;
    final isUnknown = ready[code] == null;
    final isSel = code == selected;
    return HgPressable(
      onTap: () => onPick(code),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: divider
            ? BoxDecoration(
                border: Border(bottom: BorderSide(color: p.hairline, width: 0.5)),
              )
            : null,
        child: Row(
          children: [
            HgIcon(
              isReady
                  ? HgIcons.check
                  : isUnknown
                  ? HgIcons.refresh
                  : HgIcons.download,
              size: 17,
              color: isReady ? p.live : p.faint,
              strokeWidth: 2,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: HgType.sans(
                  15.5,
                  weight: isSel ? 700 : 600,
                  color: isSel ? p.manual : p.text,
                ),
              ),
            ),
            if (!isReady && !isUnknown)
              Text(
                '~${sizeMbOf(code)}MB',
                style: HgType.sans(12, color: p.faint),
              ),
            if (isSel) ...[
              const SizedBox(width: 8),
              HgIcon(HgIcons.check, size: 16, color: p.manual, strokeWidth: 2.6),
            ],
          ],
        ),
      ),
    );
  }
}
