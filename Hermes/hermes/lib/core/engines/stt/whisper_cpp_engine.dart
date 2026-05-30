import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'stt_engine.dart';

/// whisper.cpp tabanlı STT motoru.
/// - Tiny modeli APK içine asset olarak gömülü (fast mode).
/// - Small modeli ilk seçildiğinde Hugging Face'ten indirilir (accurate mode).
/// Sonrasında her şey offline çalışır.
class WhisperCppEngine implements SttEngine {
  final WhisperController _controller = WhisperController();
  SttSpeedMode _speedMode = SttSpeedMode.fast;
  bool _initialized = false;

  WhisperModel get _model => switch (_speedMode) {
        SttSpeedMode.fast => WhisperModel.tiny,
        SttSpeedMode.accurate => WhisperModel.small,
      };

  @override
  String get engineName => 'whisper.cpp (${_model.modelName})';

  @override
  bool get isOfflineCapable => true;

  @override
  SttSpeedMode get speedMode => _speedMode;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    final targetPath = await _controller.getPath(_model);

    // Model dosya sisteminde varsa atla
    if (File(targetPath).existsSync()) {
      _initialized = true;
      return;
    }

    // Önce asset'ten yüklemeyi dene (tiny için APK içinde)
    final assetPath = 'assets/models/ggml-${_model.modelName}.bin';
    try {
      final bytes = await rootBundle.load(assetPath);
      await File(targetPath).writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      debugPrint('Whisper modeli asset\'ten yüklendi: $assetPath');
    } catch (_) {
      // Asset bulunamadıysa Hugging Face'ten indir (small için)
      debugPrint('Asset bulunamadı, indiriliyor: ${_model.modelName}');
      await _controller.downloadModel(_model);
    }

    _initialized = true;
  }

  @override
  Future<String> transcribeFile(
    String audioPath, {
    String language = 'auto',
  }) async {
    if (!_initialized) await initialize();

    final result = await _controller.transcribe(
      model: _model,
      audioPath: audioPath,
      lang: language,
    );

    final text = result?.transcription.text;
    if (text == null) {
      throw Exception('Whisper transkript üretemedi.');
    }
    return text.trim();
  }

  @override
  Future<void> setSpeedMode(SttSpeedMode mode) async {
    if (_speedMode == mode) return;
    _speedMode = mode;
    _initialized = false; // Yeni model için yeniden init gerekiyor
  }

  @override
  Future<void> dispose() async {
    // WhisperController'da dispose method'u yok; no-op.
  }
}
