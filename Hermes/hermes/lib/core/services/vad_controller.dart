import 'dart:async';

import 'package:vad/vad.dart';

/// Mikrofondan sürekli ses akışını dinleyip "konuşma başladı / bitti" gibi
/// utterance event'leri yayan kontrolcü.
///
/// Konuşma Modu'nun (sürekli çift yönlü çeviri) altyapı taşı.
/// Strategy Pattern: ileride Silero dışı bir VAD motoru çıkarsa
/// (örn. WebRTC VAD, custom RMS), bu arayüz değişmeden swap edilebilir.
abstract class VadController {
  /// Tüm utterance event'leri tek bir broadcast stream üzerinden gelir.
  Stream<VadUtteranceEvent> get events;

  /// Şu an dinliyor mu?
  bool get isListening;

  /// Mikrofon dinlemeyi başlat. Gerekirse paketin modelini yükler.
  Future<void> start();

  /// Dinlemeyi geçici olarak duraklat (kaynaklar tutulur, hızlı resume).
  Future<void> pause();

  /// Dinlemeyi tamamen durdur ve mikrofonu serbest bırak.
  Future<void> stop();

  Future<void> dispose();
}

/// VadController tarafından yayınlanan event tipleri.
sealed class VadUtteranceEvent {
  const VadUtteranceEvent();
}

/// Konuşma başlangıcı ilk tespit edildi (min frame threshold geçilmedi henüz).
class VadSpeechStart extends VadUtteranceEvent {
  const VadSpeechStart();
}

/// Konuşma min frame eşiğini geçti, gerçekten konuşma kabul edildi.
class VadRealSpeechStart extends VadUtteranceEvent {
  const VadRealSpeechStart();
}

/// Konuşma bitti, [samples] sözcenin tüm ses verisini içerir.
/// Float32 normalized PCM samples, 16 kHz mono.
class VadSpeechEnd extends VadUtteranceEvent {
  const VadSpeechEnd(this.samples);
  final List<double> samples;

  /// Sözcenin saniye cinsinden uzunluğu (16 kHz varsayımıyla).
  double get durationSeconds => samples.length / 16000.0;
}

/// VAD yanlış pozitif: konuşma kısa kaldı, min frame'i geçemedi.
class VadMisfire extends VadUtteranceEvent {
  const VadMisfire();
}

/// VAD hatası (init veya runtime).
class VadErrorEvent extends VadUtteranceEvent {
  const VadErrorEvent(this.message);
  final String message;
}

/// Silero VAD ONNX modeli ile çalışan VadController implementasyonu.
/// Model `assets/models/silero_vad_legacy.onnx` olarak APK'ya gömülüdür;
/// internet bağlantısı gerekmez.
class SileroVadController implements VadController {
  SileroVadController({this.modelVersion = 'v4'})
      : assert(modelVersion == 'v4' || modelVersion == 'v5');

  final String modelVersion;

  late final VadHandler _handler = VadHandler.create(isDebug: false);
  final _controller = StreamController<VadUtteranceEvent>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  bool _isListening = false;
  bool _wired = false;

  @override
  Stream<VadUtteranceEvent> get events => _controller.stream;

  @override
  bool get isListening => _isListening;

  void _wireHandlers() {
    if (_wired) return;
    _wired = true;

    _subs.add(_handler.onSpeechStart.listen((_) {
      _controller.add(const VadSpeechStart());
    }));
    _subs.add(_handler.onRealSpeechStart.listen((_) {
      _controller.add(const VadRealSpeechStart());
    }));
    _subs.add(_handler.onSpeechEnd.listen((samples) {
      _controller.add(VadSpeechEnd(samples));
    }));
    _subs.add(_handler.onVADMisfire.listen((_) {
      _controller.add(const VadMisfire());
    }));
    _subs.add(_handler.onError.listen((msg) {
      _controller.add(VadErrorEvent(msg));
    }));
  }

  @override
  Future<void> start() async {
    _wireHandlers();
    await _handler.startListening(
      model: modelVersion,
      // Modeli CDN yerine APK içindeki asset'ten yükle (offline-first).
      baseAssetPath: 'assets/models/',
    );
    _isListening = true;
  }

  @override
  Future<void> pause() async {
    await _handler.pauseListening();
    _isListening = false;
  }

  @override
  Future<void> stop() async {
    await _handler.stopListening();
    _isListening = false;
  }

  @override
  Future<void> dispose() async {
    _isListening = false;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _handler.dispose();
    await _controller.close();
  }
}
