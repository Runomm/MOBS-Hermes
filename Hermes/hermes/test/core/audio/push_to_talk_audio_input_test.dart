import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/audio/audio_input.dart';
import 'package:hermes/core/audio/push_to_talk_audio_input.dart';

/// Test için PttRecorder fake'i — `record` plugin'i yerine bellek içi stream.
/// `sync: true` ile pushPcm çağrısı listener'a senkron iletilir, böylece
/// test'lerde event-loop pompalamaya gerek kalmaz.
class _FakePttRecorder implements PttRecorder {
  bool permission = true;
  int startStreamCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  StreamController<Uint8List>? _stream;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<Stream<Uint8List>> startStream() async {
    startStreamCount++;
    _stream = StreamController<Uint8List>(sync: true);
    return _stream!.stream;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    await _stream?.close();
    _stream = null;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  /// Test API — aktif stream'e ham PCM byte'ları it.
  void pushPcm(Uint8List bytes) => _stream?.add(bytes);
}

/// int16 listesini little-endian PCM16 byte'larına çevirir (test fixture).
Uint8List _pcm16Bytes(List<int> samples) {
  final bd = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(i * 2, samples[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

void main() {
  group('PushToTalkAudioInput', () {
    test('press → push → release tek utterance yayar (source primary)',
        () async {
      final rec = _FakePttRecorder();
      final input = PushToTalkAudioInput(recorder: rec);
      try {
        await input.start();
        expect(input.isListening, isTrue);

        final got = input.utterances.first;
        await input.pressTalk(AudioSource.primary);
        rec.pushPcm(_pcm16Bytes([16384, -32768, 0]));
        await input.releaseTalk();

        final event = await got.timeout(const Duration(seconds: 1));
        expect(event.source, AudioSource.primary);
        // 16384/32768 = 0.5, -32768/32768 = -1.0, 0 → 0.0
        expect(event.samples, [0.5, -1.0, 0.0]);
      } finally {
        await input.dispose();
      }
    });

    test('secondary yarı basılırsa event.source secondary taşır', () async {
      final rec = _FakePttRecorder();
      final input = PushToTalkAudioInput(recorder: rec);
      try {
        await input.start();
        final got = input.utterances.first;
        await input.pressTalk(AudioSource.secondary);
        rec.pushPcm(_pcm16Bytes([100, 200]));
        await input.releaseTalk();

        final event = await got.timeout(const Duration(seconds: 1));
        expect(event.source, AudioSource.secondary);
      } finally {
        await input.dispose();
      }
    });

    test('birden fazla PCM chunk birikip tek utterance olur', () async {
      final rec = _FakePttRecorder();
      final input = PushToTalkAudioInput(recorder: rec);
      try {
        await input.start();
        final got = input.utterances.first;
        await input.pressTalk(AudioSource.primary);
        rec.pushPcm(_pcm16Bytes([16384]));
        rec.pushPcm(_pcm16Bytes([-16384]));
        await input.releaseTalk();

        final event = await got.timeout(const Duration(seconds: 1));
        expect(event.samples, [0.5, -0.5]);
      } finally {
        await input.dispose();
      }
    });

    test('releaseTalk press olmadan çağrılırsa no-op (event yok)', () async {
      final rec = _FakePttRecorder();
      final input = PushToTalkAudioInput(recorder: rec);
      try {
        await input.start();
        final received = <AudioUtteranceEvent>[];
        final sub = input.utterances.listen(received.add);

        await input.releaseTalk();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel();

        expect(received, isEmpty);
        expect(rec.startStreamCount, 0);
      } finally {
        await input.dispose();
      }
    });

    test('arm değilken (start çağrılmadan) pressTalk yakalama başlatmaz',
        () async {
      final rec = _FakePttRecorder();
      final input = PushToTalkAudioInput(recorder: rec);
      try {
        final received = <AudioUtteranceEvent>[];
        final sub = input.utterances.listen(received.add);

        await input.pressTalk(AudioSource.primary);
        await input.releaseTalk();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel();

        expect(rec.startStreamCount, 0);
        expect(received, isEmpty);
      } finally {
        await input.dispose();
      }
    });

    test('hiç byte gelmezse (boş yakalama) utterance yayılmaz', () async {
      final rec = _FakePttRecorder();
      final input = PushToTalkAudioInput(recorder: rec);
      try {
        await input.start();
        final received = <AudioUtteranceEvent>[];
        final sub = input.utterances.listen(received.add);

        await input.pressTalk(AudioSource.primary);
        await input.releaseTalk(); // hiç pushPcm yok
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel();

        expect(received, isEmpty);
        expect(rec.stopCount, 1);
      } finally {
        await input.dispose();
      }
    });

    test('pause aktif yakalamayı iptal eder + disarm eder', () async {
      final rec = _FakePttRecorder();
      final input = PushToTalkAudioInput(recorder: rec);
      try {
        await input.start();
        final received = <AudioUtteranceEvent>[];
        final sub = input.utterances.listen(received.add);

        await input.pressTalk(AudioSource.primary);
        rec.pushPcm(_pcm16Bytes([16384]));
        await input.pause(); // yakalamayı utterance yaymadan iptal et

        expect(input.isListening, isFalse);

        // pause sonrası releaseTalk no-op, pressTalk da (disarmed).
        await input.releaseTalk();
        await input.pressTalk(AudioSource.primary);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sub.cancel();

        expect(received, isEmpty, reason: 'iptal edilen yakalama event yaymaz');
      } finally {
        await input.dispose();
      }
    });

    test('start() izin reddedilirse StateError fırlatır', () async {
      final rec = _FakePttRecorder()..permission = false;
      final input = PushToTalkAudioInput(recorder: rec);
      try {
        expect(() => input.start(), throwsStateError);
        expect(input.isListening, isFalse);
      } finally {
        await input.dispose();
      }
    });

    test('stop/dispose recorder\'a delegate eder', () async {
      final rec = _FakePttRecorder();
      final input = PushToTalkAudioInput(recorder: rec);

      await input.start();
      await input.stop();
      expect(input.isListening, isFalse);

      await input.dispose();
      expect(rec.disposeCount, 1);
    });
  });
}
