import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'text_recognizer_engine.dart';

/// Google ML Kit On-Device Text Recognition ile çalışan [TextRecognizerEngine].
///
/// Cihaz-içi, tamamen offline. Latin alfabesi modeli APK'ya gömülüdür (ek
/// indirme yok) — Erasmus/turist senaryosundaki Avrupa dilleri (tr/en/es/de/fr…)
/// için yeterli. Latin-dışı alfabeler (Yunanca, Kiril, CJK) ayrı script modeli
/// ister; gerekirse sonra [TextRecognitionScript] seçimi eklenir.
class MlKitTextRecognizer implements TextRecognizerEngine {
  MlKitTextRecognizer()
      : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  @override
  String get engineName => 'Google ML Kit OCR';

  @override
  bool get isOfflineCapable => true;

  @override
  Future<OcrResult> recognize(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final recognized = await _recognizer.processImage(input);

    final lines = <OcrLine>[
      for (final block in recognized.blocks)
        for (final line in block.lines) OcrLine(line.text),
    ];
    // Lens overhaul: blok kutuları (boş metinli blokları atla) + görüntü boyutu.
    final blocks = <OcrBlock>[
      for (final block in recognized.blocks)
        if (block.text.trim().isNotEmpty)
          OcrBlock(text: block.text, boundingBox: block.boundingBox),
    ];
    return OcrResult(
      fullText: recognized.text,
      lines: lines,
      blocks: blocks,
      imageSize: await _imageSize(imagePath),
    );
  }

  /// Görüntünün piksel boyutunu çöz (kutuları ekrana ölçeklemek için).
  /// Başarısız olursa `null` — overlay çizilmez ama metin yine döner.
  static Future<ui.Size?> _imageSize(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = ui.Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    await _recognizer.close();
  }
}
