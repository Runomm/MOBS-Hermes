import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:vad/vad.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import '../../models/vosk_model_manager.dart';
import '../../models/vosk_models.dart';

/// Bir VAD-segmentinin **iki dilde** Vosk transkripti + akustik güven skorları.
///
/// Hands-free SmallTalk (S3): tek mikrofon, kimin (master/local) konuştuğu
/// bilinmiyor. Aynı ses iki tanıyıcıya verilir; **doğru dildeki tanıyıcının
/// ortalama kelime güveni (Vosk `conf`) belirgin daha yüksektir** → orkestratör
/// buna göre yönlendirir. (MLKit Language ID kullanılamaz: her Vosk modeli ses
/// neyse de kendi dilinde metin üretir; çıktı dili her zaman model dilidir.)
class DualTranscript {
  const DualTranscript({
    required this.masterText,
    required this.masterConf,
    required this.localText,
    required this.localConf,
  });

  final String masterText;
  final double masterConf;
  final String localText;
  final double localConf;
}

/// Hands-free çift-tanıyıcı kaynağı için soyutlama (orkestratör testi için).
abstract class DualTranscriber {
  Stream<String> get partials;
  Stream<DualTranscript> get finals;
  Future<void> load();
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// Hands-free için **çift Vosk tanıyıcı** streaming kontrolcüsü (S3, 2026-06-05).
///
/// Tek mic PCM16/16kHz akışı (`record.startStream`) hem VAD'e (konuşma sınırları)
/// hem **iki `Recognizer`**'a (master dili + local dili) `acceptWaveformBytes` ile
/// beslenir. VAD konuşma sonunda her iki tanıyıcıdan `getFinalResult` alınır
/// (kelime güveniyle) → [finals]'a `DualTranscript` yayılır, tanıyıcılar reset'lenir.
/// Konuşma sürerken [partials] canlı (uzun/dolu olan tanıyıcının kısmi metni).
///
/// `SpeechService` KULLANILMAZ — sabit EventChannel adları yüzünden iki
/// SpeechService aynı anda çalışamaz; doğrudan `Recognizer` API'si kullanılır
/// (`VoskSttEngine` kalıbı).
class DualVoskStreamingController implements DualTranscriber {
  DualVoskStreamingController({
    required this.masterLang,
    required this.localLang,
    AudioRecorder? recorder,
    VadHandler? vadHandler,
    this.partialInterval = const Duration(milliseconds: 900),
  })  : _recorder = recorder ?? AudioRecorder(),
        _vad = vadHandler ?? VadHandler.create(isDebug: false);

  final String masterLang;
  final String localLang;
  final AudioRecorder _recorder;
  final VadHandler _vad;
  final Duration partialInterval;

  static const int _sampleRate = 16000;
  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: _sampleRate,
    numChannels: 1,
  );

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _masterModel;
  Model? _localModel;
  Recognizer? _masterRec;
  Recognizer? _localRec;

  final _partials = StreamController<String>.broadcast();
  final _finals = StreamController<DualTranscript>.broadcast();
  final _errors = StreamController<String>.broadcast();

  @override
  Stream<String> get partials => _partials.stream;
  @override
  Stream<DualTranscript> get finals => _finals.stream;
  Stream<String> get errors => _errors.stream;

  StreamSubscription<Uint8List>? _pcmSub;
  StreamController<Uint8List>? _toVad;
  final List<StreamSubscription<Object?>> _vadSubs = [];
  Timer? _partialTimer;
  bool _speechActive = false;
  bool _running = false;
  // getFinalResult/reset sırasında gelen chunk'ları beslememek için kilit.
  bool _harvesting = false;

  bool get isRunning => _running;

  /// İki dilin Vosk modeli de inmiş mi? (warmup indirme kapısı kararı)
  static Future<bool> modelsReady(String masterLang, String localLang) async {
    for (final lang in {masterLang, localLang}) {
      if (!VoskModels.supports(lang)) return false;
      if (!await VoskModelManager.forLang(lang).isDownloaded()) return false;
    }
    return true;
  }

  /// Modelleri + tanıyıcıları yükle (mic izni dahil). Dinleme başlamaz.
  @override
  Future<void> load() async {
    for (final lang in {masterLang, localLang}) {
      if (!VoskModels.supports(lang)) {
        throw StateError('Vosk bu dili desteklemiyor: $lang');
      }
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) throw StateError('Mikrofon izni reddedildi.');

    _masterModel = await _vosk.createModel(
        await VoskModelManager.forLang(masterLang).modelPath());
    _masterRec = await _vosk.createRecognizer(
        model: _masterModel!, sampleRate: _sampleRate);
    await _masterRec!.setWords(words: true);

    // Aynı dilse ikinci modeli yeniden yükleme (örn. master=local olmaz ama
    // savunma); farklıysa ayrı model + recognizer.
    _localModel = masterLang == localLang
        ? _masterModel
        : await _vosk.createModel(
            await VoskModelManager.forLang(localLang).modelPath());
    _localRec = await _vosk.createRecognizer(
        model: _localModel!, sampleRate: _sampleRate);
    await _localRec!.setWords(words: true);
  }

  @override
  Future<void> start() async {
    if (_running) return;
    if (!await _recorder.hasPermission()) {
      _errors.add('Mikrofon izni reddedildi.');
      return;
    }
    _wireVad();
    final toVad = StreamController<Uint8List>();
    _toVad = toVad;
    final raw = await _recorder.startStream(_config);
    _pcmSub = raw.listen(
      (chunk) {
        toVad.add(chunk);
        if (!_harvesting) {
          unawaited(_masterRec?.acceptWaveformBytes(chunk));
          unawaited(_localRec?.acceptWaveformBytes(chunk));
        }
      },
      onError: (Object e) => _errors.add('PCM stream: $e'),
    );
    await _vad.startListening(
      model: 'v4',
      baseAssetPath: 'assets/models/',
      audioStream: toVad.stream,
    );
    _running = true;
  }

  void _wireVad() {
    // stop() abonelikleri iptal etmez (VAD handler yaşamaya devam eder);
    // stop→start döngüsünde tekrar eklenirse her event çift işlenir.
    if (_vadSubs.isNotEmpty) return;
    _vadSubs.add(_vad.onSpeechStart.listen((_) => _beginSpeech()));
    _vadSubs.add(_vad.onSpeechEnd.listen((_) => unawaited(_harvest())));
    _vadSubs.add(_vad.onVADMisfire.listen((_) => unawaited(_discard())));
    _vadSubs.add(_vad.onError.listen(_errors.add));
  }

  void _beginSpeech() {
    _speechActive = true;
    _partialTimer?.cancel();
    _partialTimer = Timer.periodic(partialInterval, (_) => _emitPartial());
  }

  Future<void> _emitPartial() async {
    if (!_speechActive || _harvesting) return;
    final m = _text(await _masterRec?.getPartialResult(), 'partial');
    final l = _text(await _localRec?.getPartialResult(), 'partial');
    // Konuşmacı henüz bilinmiyor → daha dolu (uzun) kısmiyi göster.
    final live = m.length >= l.length ? m : l;
    if (live.trim().isNotEmpty && !_partials.isClosed) _partials.add(live);
  }

  Future<void> _harvest() async {
    _stopPartials();
    if (_masterRec == null || _localRec == null) return;
    _harvesting = true;
    try {
      final mJson = await _masterRec!.getFinalResult();
      final lJson = await _localRec!.getFinalResult();
      await _masterRec!.reset();
      await _localRec!.reset();
      final dual = DualTranscript(
        masterText: _text(mJson, 'text'),
        masterConf: _avgConf(mJson),
        localText: _text(lJson, 'text'),
        localConf: _avgConf(lJson),
      );
      if (!_finals.isClosed &&
          (dual.masterText.trim().isNotEmpty ||
              dual.localText.trim().isNotEmpty)) {
        _finals.add(dual);
      }
    } catch (e) {
      _errors.add('harvest: $e');
    } finally {
      _harvesting = false;
    }
  }

  Future<void> _discard() async {
    _stopPartials();
    _harvesting = true;
    try {
      await _masterRec?.reset();
      await _localRec?.reset();
    } catch (_) {/* yoksay */} finally {
      _harvesting = false;
    }
  }

  void _stopPartials() {
    _speechActive = false;
    _partialTimer?.cancel();
    _partialTimer = null;
  }

  @override
  Future<void> stop() async {
    _stopPartials();
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _vad.stopListening();
    await _toVad?.close();
    _toVad = null;
    await _recorder.stop();
    _running = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    for (final s in _vadSubs) {
      await s.cancel();
    }
    _vadSubs.clear();
    await _vad.dispose();
    await _recorder.dispose();
    await _masterRec?.dispose();
    if (!identical(_localRec, _masterRec)) await _localRec?.dispose();
    _masterRec = null;
    _localRec = null;
    _masterModel?.dispose();
    if (!identical(_localModel, _masterModel)) _localModel?.dispose();
    _masterModel = null;
    _localModel = null;
    if (!_partials.isClosed) await _partials.close();
    if (!_finals.isClosed) await _finals.close();
    if (!_errors.isClosed) await _errors.close();
  }

  /// Vosk JSON'dan [key] ('text'|'partial') düz metnini ayıkla.
  String _text(String? json, String key) {
    if (json == null) return '';
    try {
      final m = jsonDecode(json);
      if (m is Map && m[key] is String) return (m[key] as String).trim();
    } catch (_) {/* ham döndürme */}
    return '';
  }

  /// `result` dizisindeki kelime `conf`'larının ortalaması (akustik güven).
  /// Yoksa 0. Doğru dildeki tanıyıcı belirgin daha yüksek skorlar.
  double _avgConf(String? json) {
    if (json == null) return 0;
    try {
      final m = jsonDecode(json);
      if (m is Map && m['result'] is List) {
        final words = m['result'] as List;
        if (words.isEmpty) return 0;
        var sum = 0.0;
        var n = 0;
        for (final w in words) {
          if (w is Map && w['conf'] is num) {
            sum += (w['conf'] as num).toDouble();
            n++;
          }
        }
        return n == 0 ? 0 : sum / n;
      }
    } catch (_) {/* yoksay */}
    return 0;
  }
}
