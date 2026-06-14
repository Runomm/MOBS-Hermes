import 'dart:async';

import 'package:flutter/services.dart';

/// Android `MediaRecorder.AudioSource` sabitleri. 6r-d faz1 deneyi: aynı `MIC`
/// kaynağıyla açılan iki `AudioRecord`'u audio policy tek input client'a
/// birleştiriyor olabilir; her mic'e **farklı** kaynak vererek policy'nin iki
/// ayrı concurrent route tahsis edip etmediğini test ediyoruz.
enum DualMicSource {
  mic(1, 'MIC'),
  voiceRecognition(6, 'VOICE_RECOGNITION'),
  voiceCommunication(7, 'VOICE_COMMUNICATION'),
  camcorder(5, 'CAMCORDER'),
  unprocessed(9, 'UNPROCESSED');

  const DualMicSource(this.androidValue, this.label);

  final int androidValue;
  final String label;
}

/// 6r-d faz1 — native `HermesDualMicPlugin`'in Dart köprüsü.
///
/// İki mikrofonu eş zamanlı açar ve her birinin ham **PCM16 / 16kHz / mono**
/// chunk'larını ayrı bir `Stream<Uint8List>` olarak yayar. Bu katman **sadece
/// transport**: VAD veya endpoint mantığı yok. Faz2'de `DualMicAudioInput`
/// (`AudioInput` implementasyonu) bu iki stream'i alıp her birine ayrı
/// `VadHandler.startListening(audioStream:)` bağlayacak.
///
/// Kanallar native tarafla birebir eşleşir:
/// - MethodChannel `hermes/dual_mic` — `start` / `stop` / `isDualCaptureSupported`
/// - EventChannel `hermes/dual_mic/primary` — kulaklık mic PCM
/// - EventChannel `hermes/dual_mic/secondary` — telefon dahili mic PCM
class DualMicChannel {
  DualMicChannel({
    MethodChannel? methodChannel,
    EventChannel? primaryChannel,
    EventChannel? secondaryChannel,
  })  : _method = methodChannel ?? const MethodChannel('hermes/dual_mic'),
        _primaryChannel =
            primaryChannel ?? const EventChannel('hermes/dual_mic/primary'),
        _secondaryChannel = secondaryChannel ??
            const EventChannel('hermes/dual_mic/secondary');

  final MethodChannel _method;
  final EventChannel _primaryChannel;
  final EventChannel _secondaryChannel;

  bool _running = false;
  bool get isRunning => _running;

  /// Kulaklık mikrofonu (Voice Translator'da sağ taraf). `start` sonrası dolar.
  Stream<Uint8List> get primaryPcm =>
      _primaryChannel.receiveBroadcastStream().map(_asBytes);

  /// Telefon dahili mikrofonu (Voice Translator'da sol taraf).
  Stream<Uint8List> get secondaryPcm =>
      _secondaryChannel.receiveBroadcastStream().map(_asBytes);

  /// Concurrent capture'ın bu cihazda *muhtemelen* desteklenip desteklenmediği
  /// (API seviyesi göstergesi — kesin kanıt cihaz testi).
  Future<bool> isDualCaptureSupported() async {
    final result = await _method.invokeMethod<bool>('isDualCaptureSupported');
    return result ?? false;
  }

  /// Çift yakalamayı başlat. [preferBluetooth] true ise native taraf kulaklık
  /// seçiminde BT SCO'yu öne alır (Mehmet tercihi); aksi halde USB/kablolu
  /// öncelikli, BT fallback.
  ///
  /// Native taraftan dönen tanılama bilgisini döndürür:
  /// `dualCaptureSupported`, `primaryDevice`, `secondaryDevice`, `scoStarted`.
  Future<DualMicStartInfo> start({
    bool preferBluetooth = false,
    DualMicSource primarySource = DualMicSource.mic,
    DualMicSource secondarySource = DualMicSource.mic,
  }) async {
    final raw = await _method.invokeMapMethod<String, dynamic>(
      'start',
      {
        'preferBluetooth': preferBluetooth,
        'primarySource': primarySource.androidValue,
        'secondarySource': secondarySource.androidValue,
      },
    );
    _running = true;
    return DualMicStartInfo.fromMap(raw ?? const {});
  }

  Future<void> stop() async {
    await _method.invokeMethod<void>('stop');
    _running = false;
  }

  Uint8List _asBytes(dynamic event) {
    if (event is Uint8List) return event;
    if (event is List<int>) return Uint8List.fromList(event);
    return Uint8List(0);
  }
}

/// `start` çağrısının native tanılama çıktısı (cihaz testi teşhisi için).
class DualMicStartInfo {
  const DualMicStartInfo({
    required this.dualCaptureSupported,
    required this.primaryDevice,
    required this.secondaryDevice,
    required this.scoStarted,
    required this.primarySource,
    required this.secondarySource,
  });

  factory DualMicStartInfo.fromMap(Map<String, dynamic> map) {
    return DualMicStartInfo(
      dualCaptureSupported: map['dualCaptureSupported'] as bool? ?? false,
      primaryDevice: map['primaryDevice'] as String? ?? '—',
      secondaryDevice: map['secondaryDevice'] as String? ?? '—',
      scoStarted: map['scoStarted'] as bool? ?? false,
      primarySource: map['primarySource'] as String? ?? '—',
      secondarySource: map['secondarySource'] as String? ?? '—',
    );
  }

  final bool dualCaptureSupported;
  final String primaryDevice;
  final String secondaryDevice;
  final bool scoStarted;
  final String primarySource;
  final String secondarySource;
}
