import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'audio_input.dart';

/// Bas Konuş Modu'nun `AudioInput` implementasyonu (6r-e).
///
/// Ders Modu'nun aksine VAD KULLANMAZ — utterance sınırını buton belirler:
/// `pressTalk()` ile ham PCM yakalama başlar, `releaseTalk()` ile durur ve
/// toplanan tüm samples **tek** bir [AudioUtteranceEvent] olarak yayılır
/// (tasarım doc §2.3 + §4.2: "buton boundary = utterance boundary").
///
/// ### AudioInput interface'ine oturuşu (Mehmet onayı 2026-05-31, Seçenek A)
/// Base interface'in `start/pause/stop/dispose` semantiği burada "arm/disarm"a
/// indirgenir:
/// - [start]: mikrofon iznini doğrula + input'u **hazırla** (henüz yakalama yok).
/// - [pause]: aktif yakalamayı iptal et + disarm (yeni `pressTalk` yok sayılır).
/// - [stop]/[dispose]: simetrik temizlik.
///
/// Buton state'i base interface'de olmadığı için iki **ek** metot eklenir
/// ([pressTalk]/[releaseTalk]); bunları Bas Konuş ekranı doğrudan bu concrete
/// tipte çağırır. Manager bu metotlardan habersizdir — sadece `utterances`
/// stream'ini dinler ve `AudioUtteranceEvent.source`'a göre yön çevirir.
///
/// `source` parametresi hangi ekran yarısının basıldığını taşır:
/// `primary` = alt yarı (kullanıcı, kaynak dil), `secondary` = üst yarı
/// (karşı taraf, hedef dil).
class PushToTalkAudioInput implements AudioInput {
  PushToTalkAudioInput({PttRecorder? recorder})
      : _recorder = recorder ?? RecordPttRecorder();

  final PttRecorder _recorder;

  final _controller = StreamController<AudioUtteranceEvent>.broadcast();

  /// `start()` çağrıldı mı — yakalamaya izin verilir mi?
  bool _armed = false;

  /// Şu an buton basılı ve PCM akıyor mu?
  bool _capturing = false;

  /// Aktif yakalamanın hangi yarıdan geldiği (release anında event'e yazılır).
  AudioSource _activeSource = AudioSource.primary;

  StreamSubscription<Uint8List>? _pcmSub;

  /// Yakalanan ham PCM16 byte'ları biriktiren tampon.
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: false);

  @override
  Stream<AudioUtteranceEvent> get utterances => _controller.stream;

  /// Input "armed" (start çağrıldı, stop/pause çağrılmadı). Bas Konuş'ta
  /// "sürekli dinleme" yok; bu bayrak yakalamaya izin verilip verilmediğini
  /// gösterir.
  @override
  bool get isListening => _armed;

  @override
  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Mikrofon izni reddedildi (Bas Konuş Modu)');
    }
    _armed = true;
  }

  @override
  Future<void> pause() async {
    await _abortCapture();
    _armed = false;
  }

  @override
  Future<void> stop() async {
    await _abortCapture();
    _armed = false;
  }

  @override
  Future<void> dispose() async {
    await _abortCapture();
    _armed = false;
    await _recorder.dispose();
    await _controller.close();
  }

  /// Buton basıldı → [side] yarısı için ham PCM yakalamayı başlat.
  /// Arm değilse (start çağrılmamış / pause'lu) veya zaten yakalıyorsa no-op.
  Future<void> pressTalk(AudioSource side) async {
    if (!_armed || _capturing) return;
    _capturing = true;
    _activeSource = side;
    _pcmBuffer.clear();

    final stream = await _recorder.startStream();
    // pressTalk await sırasında releaseTalk gelmiş olabilir (hızlı tap).
    if (!_capturing) {
      await _recorder.stop();
      return;
    }
    _pcmSub = stream.listen(_pcmBuffer.add);
  }

  /// Buton bırakıldı → yakalamayı durdur, toplanan PCM'i tek utterance olarak
  /// yay. Yakalama yoksa no-op; hiç byte toplanmadıysa sessizce atla.
  Future<void> releaseTalk() async {
    if (!_capturing) return;
    _capturing = false;

    await _recorder.stop();
    await _pcmSub?.cancel();
    _pcmSub = null;

    final bytes = _pcmBuffer.takeBytes();
    if (bytes.isEmpty) return;

    _controller.add(
      AudioUtteranceEvent(
        samples: _pcm16ToFloat32(bytes),
        source: _activeSource,
        detectedAt: DateTime.now(),
      ),
    );
  }

  /// Devam eden yakalamayı utterance yaymadan iptal et (pause/stop/dispose).
  Future<void> _abortCapture() async {
    if (!_capturing) return;
    _capturing = false;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _recorder.stop();
    _pcmBuffer.clear();
  }

  /// PCM16 little-endian byte'ları [-1, 1] normalized Float32 samples'a çevirir
  /// (WavWriter'ın ve VAD katmanının beklediği format). Tek sayıda byte kalırsa
  /// son yarım sample atılır.
  static List<double> _pcm16ToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final out = List<double>.filled(sampleCount, 0.0);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < sampleCount; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}

/// Ham PCM stream sağlayan kayıt soyutlaması — `PushToTalkAudioInput`'u
/// `record` paketinin native plugin'inden bağımsız test edebilmek için.
abstract class PttRecorder {
  /// Mikrofon izni var mı (yoksa kullanıcıdan ister).
  Future<bool> hasPermission();

  /// 16 kHz mono PCM16 ham byte stream'i başlat.
  Future<Stream<Uint8List>> startStream();

  /// Yakalamayı durdur.
  Future<void> stop();

  Future<void> dispose();
}

/// `record` paketini saran varsayılan implementasyon.
class RecordPttRecorder implements PttRecorder {
  RecordPttRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  /// Whisper'ın native rate'i: 16 kHz mono, 16-bit PCM.
  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
  );

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream() => _recorder.startStream(_config);

  @override
  Future<void> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}
