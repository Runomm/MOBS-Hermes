import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/audio/audio_input.dart';
import 'package:hermes/core/audio/single_mic_audio_input.dart';
import 'package:hermes/core/services/vad_controller.dart';

/// Sadece test için: VadController interface'ini taklit eden minimal fake.
class _FakeVad implements VadController {
  final _events = StreamController<VadUtteranceEvent>.broadcast();
  bool _listening = false;
  int startCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Stream<VadUtteranceEvent> get events => _events.stream;

  @override
  bool get isListening => _listening;

  @override
  Future<void> start() async {
    startCount++;
    _listening = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _listening = false;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _listening = false;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    _listening = false;
    await _events.close();
  }

  void emit(VadUtteranceEvent event) => _events.add(event);
}

void main() {
  group('SingleMicAudioInput', () {
    test('VadSpeechEnd → AudioUtteranceEvent (samples + source primary)',
        () async {
      final vad = _FakeVad();
      final input = SingleMicAudioInput(vad: vad);
      try {
        await input.start();

        final got = input.utterances.first;
        final samples = List<double>.filled(8000, 0.5);
        vad.emit(VadSpeechEnd(samples));

        final event = await got.timeout(const Duration(seconds: 1));
        expect(event.samples, samples);
        expect(event.source, AudioSource.primary);
        expect(
          event.detectedAt.difference(DateTime.now()).inSeconds.abs(),
          lessThan(2),
          reason: 'detectedAt şu ana yakın olmalı',
        );
      } finally {
        await input.dispose();
      }
    });

    test('source: secondary parametresi geçtiğinde event onu taşır',
        () async {
      final vad = _FakeVad();
      final input = SingleMicAudioInput(
        vad: vad,
        source: AudioSource.secondary,
      );
      try {
        await input.start();
        final got = input.utterances.first;
        vad.emit(VadSpeechEnd(List<double>.filled(1000, 0.1)));
        final event = await got.timeout(const Duration(seconds: 1));
        expect(event.source, AudioSource.secondary);
      } finally {
        await input.dispose();
      }
    });

    test('VadSpeechStart / RealSpeechStart / Misfire / Error sessizce yutulur',
        () async {
      final vad = _FakeVad();
      final input = SingleMicAudioInput(vad: vad);
      try {
        await input.start();

        final received = <AudioUtteranceEvent>[];
        final sub = input.utterances.listen(received.add);

        vad.emit(const VadSpeechStart());
        vad.emit(const VadRealSpeechStart());
        vad.emit(const VadMisfire());
        vad.emit(const VadErrorEvent('boom'));
        // Sonra gerçek bir SpeechEnd at — bunun yakalanması yutmanın
        // "tümünü kapatma" değil "sadece ara state'leri eleme" olduğunu
        // doğrular.
        vad.emit(VadSpeechEnd(List<double>.filled(100, 0.0)));

        await Future<void>.delayed(const Duration(milliseconds: 30));
        await sub.cancel();

        expect(received, hasLength(1));
        expect(received.single.samples.length, 100);
      } finally {
        await input.dispose();
      }
    });

    test('start/pause/stop/dispose VadController\'a delegate eder', () async {
      final vad = _FakeVad();
      final input = SingleMicAudioInput(vad: vad);

      await input.start();
      expect(vad.startCount, 1);
      expect(input.isListening, isTrue);

      await input.pause();
      expect(vad.pauseCount, 1);
      expect(input.isListening, isFalse);

      await input.start();
      expect(vad.startCount, 2);

      await input.stop();
      expect(vad.stopCount, 1);

      await input.dispose();
      expect(vad.disposeCount, 1);
    });
  });
}
