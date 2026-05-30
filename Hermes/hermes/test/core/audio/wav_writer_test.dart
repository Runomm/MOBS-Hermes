import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/audio/wav_writer.dart';

void main() {
  const writer = WavWriter();

  String ascii(Uint8List buf, int start, int len) =>
      ascii_.decode(buf.sublist(start, start + len));

  group('WavWriter — header', () {
    test('boş samples: 44 byte header, data uzunluğu 0', () {
      final out = writer.encodeMono16kHz(const []);
      expect(out.length, 44);

      final view = ByteData.view(out.buffer);
      expect(ascii(out, 0, 4), 'RIFF');
      expect(view.getUint32(4, Endian.little), 36); // 36 + 0 data
      expect(ascii(out, 8, 4), 'WAVE');
      expect(ascii(out, 12, 4), 'fmt ');
      expect(view.getUint32(16, Endian.little), 16); // PCM fmt chunk
      expect(view.getUint16(20, Endian.little), 1); // PCM format
      expect(view.getUint16(22, Endian.little), 1); // mono
      expect(view.getUint32(24, Endian.little), 16000); // sample rate
      expect(view.getUint32(28, Endian.little), 32000); // byte rate
      expect(view.getUint16(32, Endian.little), 2); // block align
      expect(view.getUint16(34, Endian.little), 16); // bits per sample
      expect(ascii(out, 36, 4), 'data');
      expect(view.getUint32(40, Endian.little), 0);
    });

    test('100 sample: data length = 200 byte, dosya 244 byte', () {
      final samples = List<double>.filled(100, 0.0);
      final out = writer.encodeMono16kHz(samples);
      expect(out.length, 244);

      final view = ByteData.view(out.buffer);
      expect(view.getUint32(4, Endian.little), 236); // 36 + 200
      expect(view.getUint32(40, Endian.little), 200);
    });

    test('1 saniyelik (16000 sample) buffer doğru boyut', () {
      final samples = List<double>.filled(16000, 0.0);
      final out = writer.encodeMono16kHz(samples);
      expect(out.length, 44 + 32000);
    });
  });

  group('WavWriter — sample dönüşümü', () {
    test('0.0 → 0', () {
      final out = writer.encodeMono16kHz([0.0]);
      final view = ByteData.view(out.buffer);
      expect(view.getInt16(44, Endian.little), 0);
    });

    test('+1.0 → +32767 (pozitif tavan)', () {
      final out = writer.encodeMono16kHz([1.0]);
      final view = ByteData.view(out.buffer);
      expect(view.getInt16(44, Endian.little), 32767);
    });

    test('-1.0 → -32768 (negatif taban, 16-bit signed asimetri)', () {
      final out = writer.encodeMono16kHz([-1.0]);
      final view = ByteData.view(out.buffer);
      expect(view.getInt16(44, Endian.little), -32768);
    });

    test('aralık dışı clip edilir (taşma olmaz)', () {
      final out = writer.encodeMono16kHz([1.5, -1.5, 100.0, -100.0]);
      final view = ByteData.view(out.buffer);
      expect(view.getInt16(44, Endian.little), 32767);
      expect(view.getInt16(46, Endian.little), -32768);
      expect(view.getInt16(48, Endian.little), 32767);
      expect(view.getInt16(50, Endian.little), -32768);
    });

    test('0.5 → ~16383, küçük tolerans', () {
      final out = writer.encodeMono16kHz([0.5]);
      final view = ByteData.view(out.buffer);
      // 0.5 * 32767 = 16383.5 → round 16384
      expect(view.getInt16(44, Endian.little), 16384);
    });
  });

  group('WavWriter — sabitler', () {
    test('public sabitler Hermes pipeline kilitlerini koruyor', () {
      expect(WavWriter.sampleRate, 16000);
      expect(WavWriter.numChannels, 1);
      expect(WavWriter.bitsPerSample, 16);
    });
  });
}

// `ascii` alanını sınıf adı çakışmasını önlemek için underscore ile alias.
const Encoding ascii_ = AsciiCodec();
