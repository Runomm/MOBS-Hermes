import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import '../../models/vosk_model_manager.dart';
import '../../models/vosk_models.dart';
import 'stt_engine.dart';

/// Vosk tabanlı STT motoru — dil başına ayrı model (Apache-2.0, offline).
///
/// Whisper bazı dillerde (özellikle Türkçe) zayıf; Vosk o dillerde belirgin
/// daha doğru (2026-06-01 de-risk ✅). Bu motor `SttEngine` Strategy'sini
/// implement eder; [HybridSttEngine] router'ı dilin Vosk modeli varsa+inmişse
/// buraya, yoksa Whisper'a yönlendirir.
///
/// Model bellekte tek dil için tutulur (her biri ~50MB RAM; hepsini birden
/// yüklemek OOM riski). Dil değişince eski model/recognizer dispose edilir,
/// yenisi yüklenir. Pipeline sıralı (tek transcribe/seferinde) olduğu için
/// ek kilit gerekmiyor.
class VoskSttEngine implements SttEngine {
  static const int _sampleRate = 16000;

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();

  String? _loadedLang;
  Model? _model;
  Recognizer? _recognizer;
  SttSpeedMode _speedMode = SttSpeedMode.fast;

  @override
  String get engineName =>
      'Vosk${_loadedLang != null ? " ($_loadedLang)" : ""}';

  @override
  bool get isOfflineCapable => true;

  @override
  SttSpeedMode get speedMode => _speedMode;

  /// Vosk bu dili işleyebilir mi? (model var VE cihaza inmiş)
  Future<bool> canHandle(String language) async {
    if (!VoskModels.supports(language)) return false;
    return VoskModelManager.forLang(language).isDownloaded();
  }

  @override
  Future<void> initialize() async {
    // Model dile göre tembel yüklenir (transcribeFile içinde).
  }

  @override
  Future<String> transcribeFile(
    String audioPath, {
    String language = 'auto',
  }) async {
    if (!VoskModels.supports(language)) {
      throw StateError('Vosk bu dili desteklemiyor: $language');
    }
    await _ensureModel(language);

    final bytes = await File(audioPath).readAsBytes();
    // WavWriter 44-byte canonical header yazıyor; ham PCM16 için atla.
    final pcm = bytes.length > 44
        ? Uint8List.sublistView(bytes, 44)
        : bytes;

    // Büyük buffer'ı parça parça besle (native tarafı zorlamamak için).
    const chunkSize = 8000;
    for (var i = 0; i < pcm.length; i += chunkSize) {
      final end = (i + chunkSize < pcm.length) ? i + chunkSize : pcm.length;
      await _recognizer!.acceptWaveformBytes(
        Uint8List.sublistView(pcm, i, end),
      );
    }

    final resultJson = await _recognizer!.getFinalResult();
    await _recognizer!.reset(); // sonraki utterance için temizle
    return _extractText(resultJson);
  }

  /// İstenen dilin modelini yükle (gerekirse eskiyi bırak).
  Future<void> _ensureModel(String language) async {
    if (_loadedLang == language && _recognizer != null) return;

    await _recognizer?.dispose();
    _recognizer = null;
    _model?.dispose();
    _model = null;
    _loadedLang = null;

    final manager = VoskModelManager.forLang(language);
    if (!await manager.isDownloaded()) {
      throw StateError('Vosk $language modeli inmemiş');
    }

    final path = await manager.modelPath();
    _model = await _vosk.createModel(path);
    _recognizer = await _vosk.createRecognizer(
      model: _model!,
      sampleRate: _sampleRate,
    );
    _loadedLang = language;
  }

  /// Vosk JSON sonucundan ({"text":"..."}) düz metni ayıkla.
  String _extractText(String resultJson) {
    try {
      final decoded = jsonDecode(resultJson);
      if (decoded is Map && decoded['text'] is String) {
        return (decoded['text'] as String).trim();
      }
    } catch (_) {
      // JSON değilse ham döndür (savunmacı).
    }
    return resultJson.trim();
  }

  @override
  Future<void> setSpeedMode(SttSpeedMode mode) async {
    // Vosk small tek model — hız/doğruluk ayrımı yok. State'i interface
    // uyumu için saklarız (router Whisper'a yönlendirirken anlamlı).
    _speedMode = mode;
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.dispose();
    _recognizer = null;
    _model?.dispose();
    _model = null;
    _loadedLang = null;
  }
}
