import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:vad/vad.dart';

/// Akışkan (streaming) ses kaynağı — konuşma BİTMEDEN periyodik **partial**
/// ses tamponu yayar; böylece tüketici (Whisper) konuşurken canlı transkript
/// üretebilir (Step 7 streaming, Mehmet feedback: "susmayı bekleme, chunk'lı").
///
/// Mimari: `record.startStream` sürekli ham PCM16/16kHz/mono → aynı stream
/// hem Silero VAD'e (konuşma sınırları) hem kendi tamponuma beslenir.
/// - Konuşma aktifken her [partialInterval] → o ana kadarki tampon `partials`.
/// - VAD konuşma sonu (sessizlik) → tam tampon `finals` (canonical VAD samples).
/// - Misfire → tampon atılır.
///
/// Whisper gerçek streaming yapmaz; partial = büyüyen tamponun yeniden
/// transkripti (tüketici tarafında). Bu sınıf sadece SES sağlar, transkript
/// etmez.
class StreamingMicAudioInput {
  StreamingMicAudioInput({
    AudioRecorder? recorder,
    VadHandler? vadHandler,
    this.partialInterval = const Duration(seconds: 2),
    this.maxSegmentDuration = const Duration(seconds: 5),
    this.preRollDuration = const Duration(milliseconds: 400),
  })  : _recorder = recorder ?? AudioRecorder(),
        _vad = vadHandler ?? VadHandler.create(isDebug: false);

  final AudioRecorder _recorder;
  final VadHandler _vad;

  /// Konuşma sürerken partial yayma aralığı.
  final Duration partialInterval;

  /// Konuşmacı susmasa bile bir segment bu süreye ulaşınca commit edilir
  /// (final yayılır) ve yeni segmente geçilir — uzun kesintisiz konuşma tek
  /// dev partial olarak kalmasın, belirli aralıklarla commit'lensin
  /// (Mehmet: "susmamı beklemeden belirli aralıklarla commite devam etsin").
  final Duration maxSegmentDuration;

  /// Konuşma tespit edilmeden ÖNCEKİ sesin tutulduğu pre-roll süresi. VAD
  /// onSpeechStart'tan önceki ~ms'lik PCM, segment başına eklenir; ilk kelimenin
  /// ilk yarısının kaçması böyle önlenir (Mehmet 2026-06-01: "ilk kelimeyi
  /// kaçırıyor"). Streaming kendi tamponunu onSpeechStart'tan sonra doldurduğu
  /// için VAD'in kendi pre-pad'i bu yola yetmez — ayrı ring buffer şart.
  final Duration preRollDuration;

  /// 16kHz mono PCM16 → segment bayt eşiği.
  int get _maxSegmentBytes =>
      (maxSegmentDuration.inMilliseconds * 16000 ~/ 1000) * 2;

  /// 16kHz mono PCM16 → pre-roll bayt eşiği.
  int get _maxPreRollBytes =>
      (preRollDuration.inMilliseconds * 16000 ~/ 1000) * 2;

  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
  );

  final _partialController = StreamController<List<double>>.broadcast();
  final _finalController = StreamController<List<double>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Konuşma sürerken büyüyen tamponun anlık transkripti için (kaynak-only).
  Stream<List<double>> get partials => _partialController.stream;

  /// Bitmiş utterance — tam pipeline (çeviri/DB/TTS) için.
  Stream<List<double>> get finals => _finalController.stream;

  Stream<String> get errors => _errorController.stream;

  StreamSubscription<Uint8List>? _pcmSub;
  StreamController<Uint8List>? _toVad;
  final List<StreamSubscription<Object?>> _vadSubs = [];
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  // Konuşma aktif olmasa da dönen son ~preRollDuration kadar ham PCM.
  final List<int> _preRoll = [];
  Timer? _partialTimer;
  bool _speechActive = false;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    if (!await _recorder.hasPermission()) {
      _errorController.add('Mikrofon izni reddedildi.');
      return;
    }
    _wireVad();

    // record → tek stream; hem VAD'e forward hem tampona accumulate.
    final toVad = StreamController<Uint8List>();
    _toVad = toVad;
    final raw = await _recorder.startStream(_config);
    _pcmSub = raw.listen(
      (chunk) {
        toVad.add(chunk);
        // Pre-roll ring buffer'ı her zaman güncelle (konuşma başlamadan önceki
        // sesi yakalamak için), son _maxPreRollBytes kadar tut.
        _preRoll.addAll(chunk);
        final over = _preRoll.length - _maxPreRollBytes;
        if (over > 0) _preRoll.removeRange(0, over);

        if (_speechActive) {
          _buffer.add(chunk);
          // Segment max süreye ulaştıysa konuşma sürse bile commit + yeni segment.
          if (_buffer.length >= _maxSegmentBytes) _commitSegment();
        }
      },
      onError: (Object e) => _errorController.add('PCM stream: $e'),
    );

    await _vad.startListening(
      model: 'v4',
      baseAssetPath: 'assets/models/', // offline (APK asset)
      audioStream: toVad.stream,
    );
    _running = true;
  }

  void _wireVad() {
    // stop() abonelikleri iptal etmez (VAD handler yaşamaya devam eder);
    // stop→start döngüsünde tekrar eklenirse her event çift işlenir
    // (örn. _beginSpeech ×2 → pre-roll segmente iki kez girer).
    if (_vadSubs.isNotEmpty) return;
    _vadSubs.add(_vad.onSpeechStart.listen((_) => _beginSpeech()));
    _vadSubs.add(_vad.onSpeechEnd.listen(_endSpeech));
    _vadSubs.add(_vad.onVADMisfire.listen((_) => _discardSpeech()));
    _vadSubs.add(_vad.onError.listen(_errorController.add));
  }

  void _beginSpeech() {
    _speechActive = true;
    _buffer.clear();
    // Segmenti pre-roll ile başlat → konuşma onset'inin (ilk kelimenin başı)
    // VAD tetiklenmeden önceki kısmı da transkripte girer.
    if (_preRoll.isNotEmpty) {
      _buffer.add(Uint8List.fromList(_preRoll));
    }
    _partialTimer?.cancel();
    _partialTimer = Timer.periodic(partialInterval, (_) => _emitPartial());
  }

  void _emitPartial() {
    if (!_speechActive) return;
    final samples = _pcm16ToFloat32(_buffer.toBytes());
    if (samples.isNotEmpty) _partialController.add(samples);
  }

  /// Segmenti commit et: tampondaki sesi final olarak yay + tamponu sıfırla
  /// (yeni segment). Hem max-süre dolunca hem konuşma bitince çağrılır.
  void _commitSegment() {
    final bytes = _buffer.takeBytes(); // döndürür + temizler
    if (bytes.isEmpty) return;
    final samples = _pcm16ToFloat32(bytes);
    if (samples.isNotEmpty) _finalController.add(samples);
  }

  void _endSpeech(List<double> _) {
    // Kalan segmenti commit et (kendi tamponumuzdan — VAD samples'ı değil,
    // çünkü mid-speech commit'lerle tutarlı olsun), sonra partial'ı durdur.
    _commitSegment();
    _stopPartials();
  }

  void _discardSpeech() {
    _stopPartials();
  }

  void _stopPartials() {
    _speechActive = false;
    _partialTimer?.cancel();
    _partialTimer = null;
    _buffer.clear();
  }

  Future<void> stop() async {
    _stopPartials();
    _preRoll.clear();
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _vad.stopListening();
    await _toVad?.close();
    _toVad = null;
    await _recorder.stop();
    _running = false;
  }

  Future<void> dispose() async {
    await stop();
    for (final s in _vadSubs) {
      await s.cancel();
    }
    _vadSubs.clear();
    await _vad.dispose();
    await _recorder.dispose();
    await _partialController.close();
    await _finalController.close();
    await _errorController.close();
  }

  static List<double> _pcm16ToFloat32(Uint8List bytes) {
    final n = bytes.length ~/ 2;
    final out = List<double>.filled(n, 0.0);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}
