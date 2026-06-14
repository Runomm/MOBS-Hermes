import 'dart:async';

import '../services/vad_controller.dart';
import 'audio_input.dart';

/// Tek mic + VAD ile dinleyen `AudioInput` implementasyonu (6r-c).
///
/// Ders Modu kullanır (sürekli dinleme, VAD utterance boundary'lerini
/// belirler). Bas Konuş Modu'na buton state'i ile dinleme zorlanacağı için
/// ayrı bir implementasyon (`PushToTalkAudioInput`) gelir; bu sınıf VAD-
/// merkezli akış için.
///
/// Voice Translator'da kullanım: iki ayrı `SingleMicAudioInput` instance —
/// biri `source: primary` (kulaklık), biri `source: secondary` (telefon
/// mic). Ama 6r-d native plugin'i alternatif olarak `DualMicAudioInput`
/// olarak ayrı bir sınıf sağlayacak; bu iki yaklaşımı 6r-e/h'de değerlendirir.
class SingleMicAudioInput implements AudioInput {
  SingleMicAudioInput({
    required this.vad,
    this.source = AudioSource.primary,
  });

  /// Alttaki VAD motoru — utterance'ları tespit eder.
  final VadController vad;

  /// Bu input'tan yayılan tüm utterance'lar bu source ile etiketlenir.
  final AudioSource source;

  final _controller = StreamController<AudioUtteranceEvent>.broadcast();
  StreamSubscription<VadUtteranceEvent>? _vadSub;

  @override
  Stream<AudioUtteranceEvent> get utterances => _controller.stream;

  @override
  bool get isListening => vad.isListening;

  @override
  Future<void> start() async {
    _vadSub ??= vad.events.listen(_onVadEvent);
    await vad.start();
  }

  @override
  Future<void> pause() => vad.pause();

  @override
  Future<void> stop() => vad.stop();

  @override
  Future<void> dispose() async {
    await _vadSub?.cancel();
    _vadSub = null;
    await vad.dispose();
    await _controller.close();
  }

  void _onVadEvent(VadUtteranceEvent event) {
    // VAD'in ara state'leri (SpeechStart, RealSpeechStart, Misfire, Error)
    // bu katmanda yutulur — AudioInput abstraction'ı sadece bitmiş utterance
    // semantiğini taşır. UI debug için VAD Test ekranı zaten VadController'ı
    // doğrudan dinler.
    if (event is! VadSpeechEnd) return;
    _controller.add(
      AudioUtteranceEvent(
        samples: event.samples,
        source: source,
        detectedAt: DateTime.now(),
      ),
    );
  }
}
