import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../audio/streaming_mic_audio_input.dart';
import '../../audio/wav_writer.dart';
import 'stt_engine.dart';
import 'vosk_streaming_controller.dart';
import 'whisper_cpp_engine.dart';

/// Konferans Modu için **Whisper tabanlı** [StreamingTranscriber] — iOS'te Vosk
/// olmadığından (`vosk_flutter_2`'nin iOS implementasyonu yok) Konferans canlı
/// transkriptini Whisper chunk'larıyla üretir (2026-06-19 iOS kurtarma:
/// Konferans iOS'te açıldı).
///
/// Konferans **tek kaynak dilli** → dil tespiti GEREKMEZ (hands-free'nin
/// [WhisperLangIdTranscriber]'ından bu yönüyle daha basit). [StreamingMicAudioInput]
/// finals (VAD ile bölünmüş utterance) → WAV → `Whisper(language)` → [finals]'a
/// düz metin. Whisper gerçek streaming yapmaz → **canlı partial yayılmaz**
/// ([partials] boş kalır; Konferans UI "dinleniyor" gösterir, çeviri yine final'de).
///
/// Native değil (mic + whisper.cpp) ama gerçek mic/whisper'a bağlı olduğundan
/// unit test'i orkestratör seviyesinde (sahte transcriber) yapılır; burada
/// bağımlılıklar enjekte edilebilir.
class WhisperStreamingTranscriber implements StreamingTranscriber {
  WhisperStreamingTranscriber({
    StreamingMicAudioInput? mic,
    WhisperCppEngine? whisper,
    WavWriter wavWriter = const WavWriter(),
    Future<Directory> Function() temporaryDirectory = getTemporaryDirectory,
  })  : _mic = mic ?? StreamingMicAudioInput(),
        _whisper = whisper ?? WhisperCppEngine(),
        _wavWriter = wavWriter,
        _temporaryDirectory = temporaryDirectory;

  final StreamingMicAudioInput _mic;
  final WhisperCppEngine _whisper;
  final WavWriter _wavWriter;
  final Future<Directory> Function() _temporaryDirectory;

  String _language = 'auto';

  final _partials = StreamController<String>.broadcast();
  final _finals = StreamController<String>.broadcast();

  StreamSubscription<List<double>>? _finalSub;
  Future<void> _queue = Future<void>.value();

  @override
  Stream<String> get partials => _partials.stream;
  @override
  Stream<String> get finals => _finals.stream;

  /// Konferans (doğruluk önceliği) Whisper small cihazda hazır mı? (warmup
  /// indirme kapısı — Vosk yerine iOS'te bu kontrol edilir).
  static Future<bool> whisperReady() async {
    final path = await WhisperController().getPath(WhisperModel.small);
    return File(path).existsSync();
  }

  @override
  Future<void> load(String language) async {
    _language = language;
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) throw StateError('Mikrofon izni reddedildi.');
    // Konferans = doğruluk önceliği → Whisper small.
    await _whisper.setSpeedMode(SttSpeedMode.accurate);
    await _whisper.initialize();
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
          dir.path, 'conference_${DateTime.now().microsecondsSinceEpoch}.wav');
      wav = await _wavWriter.writeMono16kHz(samples, path);
      final text =
          (await _whisper.transcribeFile(wav.path, language: _language)).trim();
      if (text.isEmpty || _finals.isClosed) return;
      _finals.add(text);
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
    if (!_partials.isClosed) await _partials.close();
    if (!_finals.isClosed) await _finals.close();
  }
}
