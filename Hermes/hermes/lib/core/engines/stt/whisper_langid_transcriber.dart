import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../audio/streaming_mic_audio_input.dart';
import '../../audio/wav_writer.dart';
import '../language_id/language_detector.dart';
import '../language_id/ml_kit_language_detector.dart';
import 'dual_vosk_streaming_controller.dart';
import 'stt_engine.dart';
import 'whisper_cpp_engine.dart';

/// Hands-free **full mod** transcriber'ı (2026-06-05): Whisper `language:auto` +
/// MLKit Language ID.
///
/// **Neden Whisper:** Vosk tek-dilli (her model kendi dilinde yazar → MLKit
/// ayırt edemez). Whisper **çok dilli**; `auto` ile konuşulanı GERÇEK dilde
/// yazar → çıktıya MLKit Language ID uygulanınca master/local güvenilir ayrılır.
///
/// [DualTranscriber] uygular: tek transkripti algılanan dile göre master VEYA
/// local slot'una (conf 1.0) koyar, diğeri boş → mevcut [SmallTalkStreamingSession]
/// yönlendirmesi (güven skoru) değişmeden çalışır. Whisper streaming yapmaz →
/// canlı partial yok (UI "dinleniyor" gösterir).
class WhisperLangIdTranscriber implements DualTranscriber {
  WhisperLangIdTranscriber({
    required this.masterLang,
    required this.localLang,
    StreamingMicAudioInput? mic,
    WhisperCppEngine? whisper,
    LanguageDetector? detector,
    WavWriter wavWriter = const WavWriter(),
    Future<Directory> Function() temporaryDirectory = getTemporaryDirectory,
  })  : _mic = mic ?? StreamingMicAudioInput(),
        _whisper = whisper ?? WhisperCppEngine(),
        _detector = detector ?? MlKitLanguageDetector(),
        _wavWriter = wavWriter,
        _temporaryDirectory = temporaryDirectory;

  final String masterLang;
  final String localLang;
  final StreamingMicAudioInput _mic;
  final WhisperCppEngine _whisper;
  final LanguageDetector _detector;
  final WavWriter _wavWriter;
  final Future<Directory> Function() _temporaryDirectory;

  final _partials = StreamController<String>.broadcast();
  final _finals = StreamController<DualTranscript>.broadcast();

  StreamSubscription<List<double>>? _finalSub;
  Future<void> _queue = Future<void>.value();

  @override
  Stream<String> get partials => _partials.stream;
  @override
  Stream<DualTranscript> get finals => _finals.stream;

  /// Full mod için Whisper small modeli cihazda hazır mı? (warmup gate)
  static Future<bool> whisperReady() async {
    final path = await WhisperController().getPath(WhisperModel.small);
    return File(path).existsSync();
  }

  /// Algılanan dile göre slot kararı (saf/test edilebilir).
  /// 1 = master, -1 = local, 0 = belirsiz (drop).
  static int slotFor(String? detected, String masterLang, String localLang) {
    if (detected == null) return 0;
    if (detected == masterLang) return 1;
    if (detected == localLang) return -1;
    return 0;
  }

  @override
  Future<void> load() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) throw StateError('Mikrofon izni reddedildi.');
    // Full mod = doğruluk önceliği → Whisper small.
    await _whisper.setSpeedMode(SttSpeedMode.accurate);
    await Future.wait([_whisper.initialize(), _detector.initialize()]);
  }

  @override
  Future<void> start() async {
    _finalSub = _mic.finals.listen((samples) {
      if (samples.isEmpty) return;
      _queue = _queue.then((_) => _process(samples));
    });
    await _mic.start();
  }

  Future<void> _process(List<double> samples) async {
    File? wav;
    try {
      final dir = await _temporaryDirectory();
      final path = p.join(
          dir.path, 'smalltalk_${DateTime.now().microsecondsSinceEpoch}.wav');
      wav = await _wavWriter.writeMono16kHz(samples, path);
      final text = (await _whisper.transcribeFile(wav.path, language: 'auto'))
          .trim();
      if (text.isEmpty) return;

      final det = await _detector.detect(text, minConfidence: 0.0);
      final slot = slotFor(det?.languageCode, masterLang, localLang);
      if (slot == 0 || _finals.isClosed) return;
      _finals.add(slot == 1
          ? DualTranscript(
              masterText: text, masterConf: 1, localText: '', localConf: 0)
          : DualTranscript(
              masterText: '', masterConf: 0, localText: text, localConf: 1));
    } catch (_) {
      // sessiz geç (orkestratör seviyesinde görünür hata yok)
    } finally {
      if (wav != null) {
        unawaited(wav.delete().catchError((_) => wav!));
      }
    }
  }

  @override
  Future<void> stop() async {
    await _finalSub?.cancel();
    _finalSub = null;
    await _mic.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _mic.dispose();
    await _whisper.dispose();
    await _detector.dispose();
    if (!_partials.isClosed) await _partials.close();
    if (!_finals.isClosed) await _finals.close();
  }
}
