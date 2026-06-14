import 'dart:async';

import 'audio_input.dart';
import 'streaming_mic_audio_input.dart';

/// `AudioInput` adaptörü — [StreamingMicAudioInput]'u Manager pipeline'ına bağlar.
///
/// Ders Modu'nun "chunk mantığıyla canlı, konuşmacının susmasını beklemeden"
/// transkript isteğini karşılar (Mehmet 2026-06-01): alttaki streaming kaynak,
/// konuşmacı sussa da `maxSegmentDuration` (~5sn) dolunca segmenti commit eder.
/// Her commit edilen segment (`finals`) burada tek bir `AudioUtteranceEvent`
/// (source: primary) olarak yayılır → Manager normal transkript→çeviri→altyazı
/// pipeline'ını her chunk için işletir. Böylece uzun konuşma, susma beklenmeden
/// ~5sn'lik parçalar hâlinde canlı düşer.
///
/// Pre-roll buffer (ilk-kelime kırpılması fix'i) alttaki kaynaktan gelir.
///
/// Not: gerçek kelime-kelime partial gösterimi (`partials` stream'i) bu
/// adaptörde KULLANILMAZ — Manager interface'i yalnızca bitmiş utterance taşır.
/// Word-by-word canlı için ileride Vosk native SpeechService yolu (ayrı iş).
class StreamingAudioInput implements AudioInput {
  StreamingAudioInput({StreamingMicAudioInput? source})
      : _source = source ?? StreamingMicAudioInput();

  final StreamingMicAudioInput _source;

  final StreamController<AudioUtteranceEvent> _utterances =
      StreamController<AudioUtteranceEvent>.broadcast();
  StreamSubscription<List<double>>? _finalSub;
  bool _listening = false;

  @override
  Stream<AudioUtteranceEvent> get utterances => _utterances.stream;

  @override
  bool get isListening => _listening;

  @override
  Future<void> start() async {
    _finalSub ??= _source.finals.listen((samples) {
      if (samples.isEmpty) return;
      _utterances.add(AudioUtteranceEvent(
        samples: samples,
        source: AudioSource.primary, // Ders Modu tek yönlü
        detectedAt: DateTime.now(),
      ));
    });
    await _source.start();
    _listening = true;
  }

  @override
  Future<void> pause() async {
    await _source.stop();
    _listening = false;
  }

  @override
  Future<void> stop() async {
    await _source.stop();
    _listening = false;
  }

  @override
  Future<void> dispose() async {
    await _finalSub?.cancel();
    _finalSub = null;
    await _source.dispose();
    await _utterances.close();
  }
}
