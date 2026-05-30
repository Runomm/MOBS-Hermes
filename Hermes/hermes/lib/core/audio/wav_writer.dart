import 'dart:io';
import 'dart:typed_data';

/// VAD'den çıkan Float32 PCM örneklerini Whisper'ın okuyabileceği 16-bit
/// little-endian PCM WAV dosyasına yazar.
///
/// Hermes pipeline'ı:
/// ```
/// VadSpeechEnd.samples (List<double>, 16kHz mono, normalized -1..1)
///     ↓ WavWriter.writeMono16kHz()
/// /tmp/utterance_XXXXX.wav
///     ↓ WhisperCppEngine.transcribeFile(path)
/// metin
/// ```
///
/// Format: 44-byte canonical WAV header + LPCM samples. Whisper.cpp bu
/// formatı doğrudan tüketir.
class WavWriter {
  const WavWriter();

  /// Sabit: Hermes pipeline'ı 16kHz mono'ya kilitli (Whisper tiny'nin
  /// resampling maliyetini önlemek için).
  static const int sampleRate = 16000;
  static const int numChannels = 1;
  static const int bitsPerSample = 16;

  /// [samples]'ı [path]'a WAV olarak yazar. [samples] aralık [-1.0, 1.0]
  /// kabul edilir; dışı clip edilir (16-bit int aralığına taşma olmaz).
  ///
  /// Dosya zaten varsa üzerine yazılır.
  Future<File> writeMono16kHz(List<double> samples, String path) async {
    final file = File(path);
    await file.writeAsBytes(encodeMono16kHz(samples), flush: true);
    return file;
  }

  /// Test'lerde dosyaya yazmadan byte buffer üretmek için.
  /// Saf fonksiyon, side-effect yok.
  Uint8List encodeMono16kHz(List<double> samples) {
    final pcmBytes = _floatSamplesToPcm16(samples);
    final header = _buildHeader(dataLength: pcmBytes.lengthInBytes);

    final out = Uint8List(header.lengthInBytes + pcmBytes.lengthInBytes);
    out.setRange(0, header.lengthInBytes, header);
    out.setRange(
      header.lengthInBytes,
      header.lengthInBytes + pcmBytes.lengthInBytes,
      pcmBytes,
    );
    return out;
  }

  Uint8List _floatSamplesToPcm16(List<double> samples) {
    final out = Uint8List(samples.length * 2);
    final view = ByteData.view(out.buffer);
    for (var i = 0; i < samples.length; i++) {
      var s = samples[i];
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;
      // -1.0 → -32768, +1.0 → +32767 (asimetri 16-bit signed range).
      final intVal = s < 0 ? (s * 32768).round() : (s * 32767).round();
      view.setInt16(i * 2, intVal, Endian.little);
    }
    return out;
  }

  Uint8List _buildHeader({required int dataLength}) {
    const byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;
    final fileSizeMinus8 = 36 + dataLength;

    final header = Uint8List(44);
    final view = ByteData.view(header.buffer);

    // RIFF chunk
    _writeAscii(header, 0, 'RIFF');
    view.setUint32(4, fileSizeMinus8, Endian.little);
    _writeAscii(header, 8, 'WAVE');

    // fmt subchunk
    _writeAscii(header, 12, 'fmt ');
    view.setUint32(16, 16, Endian.little); // fmt chunk size = 16 for PCM
    view.setUint16(20, 1, Endian.little); // audio format = 1 (PCM)
    view.setUint16(22, numChannels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, byteRate, Endian.little);
    view.setUint16(32, blockAlign, Endian.little);
    view.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    _writeAscii(header, 36, 'data');
    view.setUint32(40, dataLength, Endian.little);

    return header;
  }

  void _writeAscii(Uint8List buf, int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      buf[offset + i] = s.codeUnitAt(i);
    }
  }
}
