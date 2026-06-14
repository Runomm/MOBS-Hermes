import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/engines/language_id/language_detector.dart';
import '../../core/engines/language_id/ml_kit_language_detector.dart';
import '../../core/engines/ocr/mlkit_text_recognizer.dart';
import '../../core/engines/ocr/text_recognizer_engine.dart';
import '../../core/engines/translation/translation_engine.dart';
import '../../core/engines/translation/translation_tier.dart';
import '../../core/theme/hg_glass.dart';
import '../../core/theme/hg_tokens.dart';
import '../../core/theme/hg_typography.dart';
import '../mode_entry/model_tier_selector.dart';
import '../shared/hg_icons.dart';
import '../shared/hg_widgets.dart';

/// Görüntü kaynağından metin alma fonksiyonu — test için enjekte edilebilir.
/// Üretimde `image_picker` ile kamera/galeri; testte sabit yol döner.
/// `null` = kullanıcı iptal etti.
typedef ImagePickFn = Future<String?> Function(ImageSource source);

/// Seçilen katman için [TranslationEngine] üreten fabrika — test için enjekte
/// edilebilir. Üretimde [createTranslationEngine].
typedef TranslationEngineFactory =
    TranslationEngine Function(TranslationTier tier, {String? hfToken});

/// **Görsel Çeviri** modu — **Lens overhaul** (2026-06-12, Mehmet feature isteği).
///
/// Akış: kaynak→hedef dil seç (kaynak "otomatik" olabilir) → fotoğraf çek veya
/// galeriden seç → [TextRecognizerEngine] görüntüdeki metin **bloklarını** kutu
/// koordinatlarıyla tanır → foto üstünde her blok **tıklanabilir** çizilir →
/// dokunulan bloğun metni çevrilir (Google Lens tarzı: çeviri kutunun üstüne
/// bindirilir + altta sonuç kartı). Auto kaynakta dil blok bazında tespit edilir.
///
/// Tüm bağımlılıklar enjekte edilebilir (test için Fake'ler).
class OcrTranslateScreen extends StatefulWidget {
  const OcrTranslateScreen({
    super.key,
    this.recognizer,
    this.detector,
    this.engineFactory,
    this.pickImage,
  });

  /// OCR motoru (default: [MlKitTextRecognizer]).
  final TextRecognizerEngine? recognizer;

  /// Kaynak dil "otomatik" seçiliyse kullanılan dil tespiti
  /// (default: [MlKitLanguageDetector]).
  final LanguageDetector? detector;

  /// Çeviri motoru fabrikası (default: [createTranslationEngine]).
  final TranslationEngineFactory? engineFactory;

  /// Görüntü seçme fonksiyonu (default: [ImagePicker]).
  final ImagePickFn? pickImage;

  @override
  State<OcrTranslateScreen> createState() => _OcrTranslateScreenState();
}

class _OcrTranslateScreenState extends State<OcrTranslateScreen> {
  /// Faz 1 desteklenen diller (MLKit çeviri). `auto` yalnız kaynak için.
  static const Map<String, String> _languages = {
    'tr': 'Türkçe',
    'en': 'İngilizce',
    'es': 'İspanyolca',
    'de': 'Almanca',
    'fr': 'Fransızca',
  };

  static const String _auto = 'auto';

  late final TextRecognizerEngine _recognizer =
      widget.recognizer ?? MlKitTextRecognizer();
  late final LanguageDetector _detector =
      widget.detector ?? MlKitLanguageDetector();
  late final TranslationEngineFactory _engineFactory =
      widget.engineFactory ?? createTranslationEngine;
  late final ImagePickFn _pickImage = widget.pickImage ?? _defaultPick;

  final ImagePicker _imagePicker = ImagePicker();

  String _source = _auto;
  String _target = 'tr';

  TranslationTier _tier = kManualDefaultTier;
  String? _hfToken;
  bool _modelReady = true; // MLKit hep hazır

  bool _busy = false;
  String? _imagePath;
  List<OcrBlock> _blocks = const [];
  Size? _imageSize;

  /// Seçili blok + çevirisi (Lens overlay + sonuç kartı).
  int? _selectedBlock;
  String? _blockSource;
  String? _blockTranslation;
  String? _detectedLabel; // auto tespit edilen dil rozeti

  bool get _valid => _source == _auto || _source != _target;
  bool get _canPick => _valid && !_busy && _modelReady;

  Future<String?> _defaultPick(ImageSource source) async {
    // maxWidth/maxHeight KRİTİK (iOS OCR kalitesi, 2026-06-14):
    // (1) iPhone 48MP foto ML Kit'i boğar → metin algılanamaz/saçmalar; ~2400px'e
    //     küçültmek doğruluğu belirgin artırır.
    // (2) image_picker küçültürken yeniden kodlar ve EXIF rotasyonunu PİKSELLERE
    //     işler → ML Kit metni "yan" okuyup saçmalamaz (kök neden buydu). Ham
    //     fromFilePath rotasyon meta'sını tutarsız uyguluyordu.
    final file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (file == null) return null;
    // EXIF rotasyonunu PİKSELLERE işle (dik) → ML Kit koordinatları ile
    // gösterim/boyut aynı yönde olur, kutucuklar 90° dönük çizilmez (iOS fix).
    return _uprightPath(file.path);
  }

  @override
  void dispose() {
    _recognizer.dispose();
    _detector.dispose();
    super.dispose();
  }

  Future<void> _onPick(ImageSource source) async {
    if (!_canPick) return;
    final path = await _pickImage(source);
    if (path == null || !mounted) return; // iptal
    await _runOcr(path);
  }

  /// [path]'teki görüntüyü EXIF yönelimine göre döndürüp dik kaydeder; yeni
  /// dosyanın yolunu döner. Çözülemezse orijinali döner. Yalnız üretim picker'ı
  /// ([_defaultPick]) çağırır → enjekte edilen test picker'ı IO'ya girmez.
  Future<String> _uprightPath(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return path;
      final baked = img.bakeOrientation(decoded); // EXIF → piksel, meta sıfırlanır
      final out = '$path.upright.jpg';
      await File(out).writeAsBytes(img.encodeJpg(baked, quality: 90));
      return out;
    } catch (_) {
      return path;
    }
  }

  /// Fotoğrafı OCR'la → blokları + boyutu yükle (henüz çevirmez).
  Future<void> _runOcr(String path) async {
    setState(() {
      _busy = true;
      _imagePath = path;
      _blocks = const [];
      _imageSize = null;
      _selectedBlock = null;
      _blockSource = null;
      _blockTranslation = null;
      _detectedLabel = null;
    });
    String? info;
    try {
      final ocr = await _recognizer.recognize(path);
      if (!mounted) return;
      if (ocr.isEmpty || ocr.blocks.isEmpty) {
        info = 'Görüntüde metin algılanamadı.';
        setState(() => _imagePath = null);
        return;
      }
      setState(() {
        _blocks = ocr.blocks;
        _imageSize = ocr.imageSize;
      });
    } catch (e) {
      info = 'Tanıma başarısız: $e';
      if (mounted) setState(() => _imagePath = null);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (info != null) unawaited(_showInfo(info));
      }
    }
  }

  /// Dokunulan bloğu çevir (auto kaynakta dil blok bazında tespit edilir).
  Future<void> _onTapBlock(int i) async {
    if (_busy || !_modelReady) return;
    final block = _blocks[i];
    setState(() {
      _busy = true;
      _selectedBlock = i;
      _blockSource = block.text.trim();
      _blockTranslation = null;
      _detectedLabel = null;
    });
    String? info;
    try {
      String? from = _source == _auto ? null : _source;
      String? detectedLabel;
      if (from == null) {
        final res = await _detector.detect(block.text, minConfidence: 0.5);
        final code = res?.languageCode;
        if (code == null || !_languages.containsKey(code)) {
          info = 'Bloğun dili belirlenemedi. Kaynak dili elle seç.';
          return;
        }
        from = code;
        detectedLabel = _languages[code];
      }
      if (from == _target) {
        // Kaynak = hedef → çeviriye gerek yok.
        if (mounted) {
          setState(() {
            _blockTranslation = block.text.trim();
            _detectedLabel = detectedLabel;
          });
        }
        return;
      }
      final engine = _engineFactory(_tier, hfToken: _hfToken);
      try {
        await engine.ensureModelLoaded(from, _target);
        final translated = await engine.translate(block.text, from, _target);
        if (!mounted) return;
        setState(() {
          _blockTranslation = translated.trim();
          _detectedLabel = detectedLabel;
        });
      } finally {
        await engine.dispose();
      }
    } catch (e) {
      info = 'Çeviri başarısız: $e';
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (info != null) unawaited(_showInfo(info));
      }
    }
  }

  Future<void> _showInfo(String message) {
    final p = HgPalette.of(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        contentPadding: EdgeInsets.zero,
        content: HgGlass(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message, style: HgType.sans(15, color: p.text, height: 1.4)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: HgPressable(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: HgGlass(
                    radius: 13,
                    elevated: false,
                    tint: p.visual,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    child: Text(
                      'Tamam',
                      style: HgType.sans(14, weight: 700, color: p.text),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _swap() {
    if (_source == _auto) return;
    setState(() {
      final t = _source;
      _source = _target;
      _target = t;
    });
  }

  Future<void> _pickLang(bool isSource) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OcrLangSheet(
        languages: _languages,
        includeAuto: isSource,
        selected: isSource ? _source : _target,
        title: isSource ? 'Kaynak dil' : 'Hedef dil',
        onPick: (code) {
          Navigator.pop(ctx);
          setState(() {
            if (isSource) {
              _source = code;
            } else {
              _target = code;
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final size = _imageSize;
    final path = _imagePath;
    final hasImage =
        path != null && size != null && size.width > 0 && size.height > 0;
    // Fotoğraf çekilene kadar boş preview yer kaplamaz (Mehmet 2026-06-13);
    // çekilince fotoğraf tüm ekranı kaplar, kontroller şeffaf üstte durur.
    return hasImage ? _photoView(p, path, size) : _setupView(p);
  }

  String get _sub => _source == _auto
      ? 'Otomatik algıla → ${_languages[_target]}'
      : '${_languages[_source]} → ${_languages[_target]}';

  /// Fotoğraf seçili değil — sade kurulum (büyük boş preview YOK).
  Widget _setupView(HgPalette p) {
    return HgScreen(
      scroll: false,
      padded: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Hg.pad, 14, Hg.pad, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HgNavHeader(title: 'Görsel Çeviri', sub: _sub),
            _langBar(p),
            if (!_valid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Kaynak ve hedef dil farklı olmalı.',
                  style: HgType.sans(12.5, color: p.manual),
                ),
              ),
            const SizedBox(height: 12),
            _tierSelector(p),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HgIcon(
                      HgIcons.camera,
                      size: 46,
                      color: p.visual.withValues(alpha: 0.85),
                      strokeWidth: 1.5,
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Text(
                        'Çevirmek için bir fotoğraf çek veya galeriden seç.',
                        textAlign: TextAlign.center,
                        style: HgType.sans(14, color: p.sub, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _captureButtons(p),
          ],
        ),
      ),
    );
  }

  /// Fotoğraf seçili — tüm ekran fotoğraf; kontroller şeffaf cam, fotoğrafın
  /// üstünde (üst: başlık+dil+motor, alt: sonuç+çek/galeri). Bloklar fotoğrafta.
  Widget _photoView(HgPalette p, String path, Size size) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1) Tam ekran fotoğraf + tıklanabilir bloklar.
          LayoutBuilder(
            builder: (context, c) {
              final sx = c.maxWidth / size.width;
              final sy = c.maxHeight / size.height;
              final scale = sx < sy ? sx : sy;
              final w = size.width * scale;
              final h = size.height * scale;
              final dx = (c.maxWidth - w) / 2;
              final dy = (c.maxHeight - h) / 2;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Colors.black),
                    ),
                  ),
                  for (var i = 0; i < _blocks.length; i++)
                    _blockBox(p, i, scale, dx, dy),
                  if (_busy)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.3),
                        child: Center(
                          child: CircularProgressIndicator(color: p.visual),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // 2) Üst şeffaf kontroller (başlık + dil + motor) — daha şeffaf (glass
          // 42), kenarlara yakın, küçük (Mehmet 2026-06-13).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const HgBackButton(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _sub,
                            style: HgType.sans(12.5, weight: 600, color: p.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _langBar(p, glass: 42),
                    const SizedBox(height: 8),
                    _tierSelector(p, intensity: 42),
                  ],
                ),
              ),
            ),
          ),
          // 3) Alt şeffaf kontroller (sonuç + çek/galeri) — kenara/aşağı yakın.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_blockTranslation != null) ...[
                      _resultCard(p, glass: 42),
                      const SizedBox(height: 10),
                    ],
                    _captureButtons(p, compact: true, glass: 42),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tierSelector(HgPalette p, {double intensity = 74}) =>
      ModelTierSelector(
        initialTier: _tier,
        // Kaynak "otomatik" ise isTierReady ArgumentError'ı yutar → o yön çalışma
        // anına bırakılır; hedef paketi yine de kontrol edilir.
        sourceLang: _source == _auto ? null : _source,
        targetLang: _target,
        accent: p.visual,
        intensity: intensity,
        onChanged: (tier, token, ready) => setState(() {
          _tier = tier;
          _hfToken = token;
          _modelReady = ready;
        }),
      );

  Widget _captureButtons(HgPalette p, {bool compact = false, double glass = 74}) {
    final h = compact ? 46.0 : 54.0;
    return Row(
      children: [
        Expanded(
          child: HgGradientButton(
            label: 'Fotoğraf çek',
            from: p.visual,
            to: p.conference,
            height: h,
            icon: HgIcon(
              HgIcons.camera,
              size: compact ? 16 : 18,
              color: Colors.white,
              strokeWidth: 1.8,
            ),
            onTap: _canPick ? () => _onPick(ImageSource.camera) : null,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: compact ? 84 : 96,
          child: HgPressable(
            onTap: _canPick ? () => _onPick(ImageSource.gallery) : null,
            child: HgGlass(
              radius: 16,
              elevated: false,
              intensity: glass,
              height: h,
              child: Center(
                child: Text(
                  'Galeri',
                  style: HgType.sans(
                    compact ? 14 : 15,
                    weight: 700,
                    color: p.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tek metin bloğu — tıklanabilir kutu; seçiliyse çeviri overlay'iyle dolu.
  Widget _blockBox(HgPalette p, int i, double scale, double dx, double dy) {
    final b = _blocks[i];
    final r = b.boundingBox;
    final selected = _selectedBlock == i;
    final translated = selected && _blockTranslation != null;
    return Positioned(
      left: dx + r.left * scale,
      top: dy + r.top * scale,
      width: r.width * scale,
      height: r.height * scale,
      child: GestureDetector(
        key: ValueKey('ocr-block-$i'),
        onTap: () => _onTapBlock(i),
        child: Container(
          decoration: BoxDecoration(
            color: translated
                ? p.visual
                : p.visual.withValues(alpha: selected ? 0.30 : 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: p.visual.withValues(alpha: translated ? 1 : 0.7),
              width: translated ? 0 : 1.2,
            ),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: translated
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _blockTranslation!,
                    textAlign: TextAlign.center,
                    style: HgType.sans(
                      13,
                      weight: 700,
                      color: Colors.white,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _langBar(HgPalette p, {double glass = 74}) {
    Widget pill(String label, String value, bool isSource) {
      final name = value == _auto ? 'Otomatik algıla' : _languages[value];
      return Expanded(
        child: HgPressable(
          onTap: () => _pickLang(isSource),
          child: HgGlass(
            radius: 16,
            elevated: false,
            intensity: glass,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                    name ?? value,
                    style: HgType.sans(15.5, weight: 700, color: p.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill('Kaynak', _source, true),
        const SizedBox(width: 10),
        HgPressable(
          onTap: _swap,
          child: HgGlass(
            radius: 14,
            elevated: false,
            intensity: glass,
            width: 38,
            height: 38,
            child: Center(
              child: HgIcon(
                HgIcons.swap,
                size: 18,
                color: _source == _auto ? p.faint : p.sub,
                strokeWidth: 1.9,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        pill('Hedef', _target, false),
      ],
    );
  }

  Widget _resultCard(HgPalette p, {double glass = 74}) {
    final src = _blockSource ?? '';
    final translated = _blockTranslation ?? '';
    return HgGlass(
      radius: 20,
      tint: p.visual,
      intensity: glass,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _detectedLabel != null
                ? 'ORİJİNAL · ${_detectedLabel!} (otomatik)'
                : 'ORİJİNAL',
            style: HgType.sans(
              11,
              weight: 600,
              color: p.faint,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            src,
            style: HgType.sans(13.5, color: p.sub, height: 1.35),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ÇEVİRİ · ${_languages[_target]}',
                  style: HgType.sans(
                    11,
                    weight: 600,
                    color: p.faint,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              HgPressable(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: translated));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kopyalandı'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: HgIcon(
                    HgIcons.copy,
                    size: 16,
                    color: p.faint,
                    strokeWidth: 1.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            translated,
            style: HgType.sans(18, weight: 700, color: p.text, height: 1.4),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Görsel Çeviri dil seçimi alt sayfası (kaynak için "otomatik" dahil).
class _OcrLangSheet extends StatelessWidget {
  const _OcrLangSheet({
    required this.languages,
    required this.includeAuto,
    required this.selected,
    required this.title,
    required this.onPick,
  });

  final Map<String, String> languages;
  final bool includeAuto;
  final String selected;
  final String title;
  final ValueChanged<String> onPick;

  static const String _auto = 'auto';

  @override
  Widget build(BuildContext context) {
    final p = HgPalette.of(context);
    final entries = <MapEntry<String, String>>[
      if (includeAuto) const MapEntry(_auto, 'Otomatik algıla'),
      ...languages.entries,
    ];
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
                _row(
                  p,
                  entries[i].key,
                  entries[i].value,
                  i < entries.length - 1,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(HgPalette p, String code, String name, bool divider) {
    final isSel = code == selected;
    return HgPressable(
      onTap: () => onPick(code),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: divider
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: p.hairline, width: 0.5),
                ),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: HgType.sans(
                  15.5,
                  weight: isSel ? 700 : 600,
                  color: isSel ? p.visual : p.text,
                ),
              ),
            ),
            if (isSel)
              HgIcon(HgIcons.check, size: 16, color: p.visual, strokeWidth: 2.6),
          ],
        ),
      ),
    );
  }
}
