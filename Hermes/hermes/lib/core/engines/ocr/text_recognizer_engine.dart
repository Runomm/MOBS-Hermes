import 'dart:ui';

/// Strategy Pattern arayüzü — görüntüden metin tanıma (OCR) motoru.
///
/// Uygulama yalnızca bu arayüzü tanır, hangi motor olduğunu (ML Kit, Tesseract…)
/// bilmez. Yeni motor eklemek için:
/// 1. Bu sınıfı implement eden bir sınıf yaz (örn. `TesseractTextRecognizer`)
/// 2. Çağıran katmanda motor referansını değiştir
///
/// Görsel Çeviri modu bu motoru kullanır: foto/galeri → [recognize] → çeviri.
abstract class TextRecognizerEngine {
  /// Motorun adı (UI'da gösterim ve loglama için).
  String get engineName;

  /// Motor internet bağlantısı olmadan çalışabilir mi?
  bool get isOfflineCapable;

  /// [imagePath]'teki görüntüden metni tanır. Metin bulunamazsa
  /// `fullText` boş bir [OcrResult] döner (hata fırlatmaz).
  Future<OcrResult> recognize(String imagePath);

  /// Kaynakları serbest bırakır (native recognizer'ı kapatır).
  Future<void> dispose();
}

/// OCR sonucu — tüm metin + satır bazlı parçalar + (Lens overhaul) blok bazlı
/// metin kutuları + görüntü piksel boyutu.
///
/// [blocks] + [imageSize] **Görsel Çeviri Lens akışı** içindir: fotoğraf üstünde
/// her metin bloğu tıklanabilir bir kutu olarak çizilir, dokunulan blok çevrilir.
/// [lines] eski satır listesini (canlı overlay) korur; [fullText] tüm metni.
class OcrResult {
  const OcrResult({
    required this.fullText,
    this.lines = const [],
    this.blocks = const [],
    this.imageSize,
  });

  /// Tanınan tüm metin (satırlar birleşik).
  final String fullText;

  /// Satır bazlı parçalar (okuma sırasıyla).
  final List<OcrLine> lines;

  /// Blok bazlı metin kutuları (Lens overhaul — tıklanabilir alan seçimi).
  final List<OcrBlock> blocks;

  /// Tanımanın yapıldığı görüntünün piksel boyutu (kutuları ekrana ölçeklemek
  /// için). `null` = boyut alınamadı (kutu overlay'i çizilmez, metin yine gelir).
  final Size? imageSize;

  bool get isEmpty => fullText.trim().isEmpty;

  static const OcrResult empty = OcrResult(fullText: '');
}

/// Tanınan tek bir metin satırı.
class OcrLine {
  const OcrLine(this.text);

  final String text;
}

/// Tanınan bir metin bloğu + görüntü piksel uzayındaki sınır kutusu (Lens).
class OcrBlock {
  const OcrBlock({required this.text, required this.boundingBox});

  final String text;

  /// Görüntü piksel koordinatlarında sınır kutusu.
  final Rect boundingBox;
}
