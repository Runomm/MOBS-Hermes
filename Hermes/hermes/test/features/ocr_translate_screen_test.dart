import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/engines/language_id/language_detector.dart';
import 'package:hermes/core/engines/ocr/text_recognizer_engine.dart';
import 'package:hermes/core/engines/translation/translation_engine.dart';
import 'package:hermes/features/ocr_translate/ocr_translate_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OCR ekran orkestrasyonu (tanı → dil tespiti → çevir → göster) Fake'lerle
/// test edilir. Native ML Kit/image_picker çağrılmaz.
class _FakeRecognizer implements TextRecognizerEngine {
  _FakeRecognizer(this.result);
  final OcrResult result;

  @override
  String get engineName => 'fake-ocr';
  @override
  bool get isOfflineCapable => true;
  @override
  Future<OcrResult> recognize(String imagePath) async => result;
  @override
  Future<void> dispose() async {}
}

class _FakeDetector implements LanguageDetector {
  _FakeDetector(this.code);
  final String? code;

  @override
  String get engineName => 'fake-langid';
  @override
  bool get isOfflineCapable => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<LanguageDetectionResult?> detect(String text,
      {double minConfidence = 0.6}) async {
    if (code == null) return null;
    return LanguageDetectionResult(languageCode: code!, confidence: 0.9);
  }

  @override
  Future<void> dispose() async {}
}

class _FakeEngine implements TranslationEngine {
  @override
  String get engineName => 'fake-translate';
  @override
  bool get isOfflineCapable => true;
  @override
  Future<void> ensureModelLoaded(String fromCode, String toCode) async {}
  @override
  Future<String> translate(String text, String fromCode, String toCode,
          {List<TranslationTurn> context = const []}) async =>
      'ÇEVİRİ($fromCode→$toCode): $text';
  @override
  Future<bool> isLanguageReady(String code) async => true;
  @override
  int estimatedDownloadSizeMb(String code) => 30;
  @override
  Future<void> downloadLanguage(String code) async {}
  @override
  Future<void> deleteLanguage(String code) async {}
  @override
  Future<void> dispose() async {}
}

/// HgScreen mesh drift animasyonu sonsuzdur → pumpAndSettle settle olmaz.
/// Reduce-motion açıkken bloblar statik durur (tasarımın prefers-reduced-motion
/// kuralı) → test deterministik olur.
Widget _noAnim(BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // ModelTierSelector readiness MLKit dil-paketini sorar (native kanal) →
    // testte mock yoksa MissingPluginException fırlatır. "İndirilmiş" varsay →
    // _modelReady=true, fotoğraf seçimi açık.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('google_mlkit_on_device_translator'),
      (call) async => true,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('google_mlkit_on_device_translator'),
      null,
    );
  });

  testWidgets('blok dokununca otomatik dil tespitiyle çevrilip gösterilir',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: _noAnim,
      home: OcrTranslateScreen(
        recognizer: _FakeRecognizer(const OcrResult(
          fullText: 'Hello world',
          blocks: [
            OcrBlock(text: 'Hello world', boundingBox: Rect.fromLTWH(10, 10, 80, 30)),
          ],
          imageSize: Size(100, 100),
        )),
        detector: _FakeDetector('en'), // otomatik → en
        engineFactory: (tier, {hfToken}) => _FakeEngine(),
        pickImage: (source) async => '/fake/path.jpg',
      ),
    ));
    await tester.pumpAndSettle();

    // 1) Foto seç → bloklar yüklenir (henüz çeviri yok).
    await tester.tap(find.text('Galeri'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ocr-block-0')), findsOneWidget);
    expect(find.textContaining('ÇEVİRİ('), findsNothing);

    // 2) Bloğa dokun → en→tr çeviri (kutu overlay + sonuç kartı).
    await tester.tap(find.byKey(const ValueKey('ocr-block-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ÇEVİRİ(en→tr): Hello world'), findsWidgets);
    expect(find.text('Hello world'), findsOneWidget); // sonuç kartı orijinali
  });

  testWidgets('boş OCR sonucu bilgi dialog\'u gösterir', (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: _noAnim,
      home: OcrTranslateScreen(
        recognizer: _FakeRecognizer(OcrResult.empty),
        detector: _FakeDetector('en'),
        engineFactory: (tier, {hfToken}) => _FakeEngine(),
        pickImage: (source) async => '/fake/path.jpg',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Galeri'));
    await tester.pumpAndSettle();

    expect(find.textContaining('metin algılanamadı'), findsOneWidget);
  });

  testWidgets('blok dili tespit edilemezse kaynak dil uyarısı verir',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: _noAnim,
      home: OcrTranslateScreen(
        recognizer: _FakeRecognizer(const OcrResult(
          fullText: '12345 @#%',
          blocks: [
            OcrBlock(text: '12345 @#%', boundingBox: Rect.fromLTWH(5, 5, 50, 20)),
          ],
          imageSize: Size(60, 40),
        )),
        detector: _FakeDetector(null), // tespit edilemedi
        engineFactory: (tier, {hfToken}) => _FakeEngine(),
        pickImage: (source) async => '/fake/path.jpg',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Galeri'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ocr-block-0')));
    await tester.pumpAndSettle();

    expect(find.textContaining('dili belirlenemedi'), findsOneWidget);
  });

  testWidgets('kullanıcı iptal ederse (path null) hiçbir şey olmaz',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: _noAnim,
      home: OcrTranslateScreen(
        recognizer:
            _FakeRecognizer(const OcrResult(fullText: 'x')),
        detector: _FakeDetector('en'),
        engineFactory: (tier, {hfToken}) => _FakeEngine(),
        pickImage: (source) async => null, // iptal
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fotoğraf çek'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('ÇEVİRİ('), findsNothing);
  });
}
