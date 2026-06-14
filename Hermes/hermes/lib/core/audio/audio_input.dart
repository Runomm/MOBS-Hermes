/// Manager'ın utterance kaynağı için strategy abstraction'ı (6r-c).
///
/// 3 mod mimarisinde her mod farklı bir audio input modeline ihtiyaç duyar:
/// - **Ders Modu**: tek mic + VAD ile sürekli dinleme (`SingleMicAudioInput`)
/// - **Voice Translator**: çift mic (kulaklık + telefon) eş zamanlı dinleme
///   (`DualMicAudioInput`, 6r-d'de native Kotlin plugin'le gelir)
/// - **Bas Konuş**: tek mic + push-to-talk buton state'i (ilerideki
///   `PushToTalkAudioInput`, 6r-e veya Step 7+)
///
/// Manager bu interface'i alır, alttaki implementasyondan habersiz çalışır.
/// `AudioUtteranceEvent.source` Voice Translator'da hangi mic'ten geldiğini
/// taşır (primary = kulaklık → sağ, secondary = telefon → sol); diğer
/// modlarda her zaman `primary`.
library;

import 'dart:async';

abstract class AudioInput {
  /// Bitmiş utterance'lar — VAD endpoint'i veya buton bırakma anı.
  /// Sadece "konuşma bitti, samples hazır" event'leri yayar; VAD'in
  /// ara state'leri (SpeechStart, RealSpeechStart, Misfire) bu seviyede
  /// görünmez.
  Stream<AudioUtteranceEvent> get utterances;

  bool get isListening;

  /// Dinlemeyi başlat. Gerekirse alttaki kaynağı (VAD modeli vb.)
  /// initialize eder.
  Future<void> start();

  /// Dinlemeyi geçici olarak duraklat (kaynaklar tutulur, hızlı resume).
  Future<void> pause();

  /// Dinlemeyi tamamen durdur, mikrofon kaynaklarını serbest bırak.
  Future<void> stop();

  Future<void> dispose();
}

/// Bitmiş bir konuşma sözcesi.
class AudioUtteranceEvent {
  const AudioUtteranceEvent({
    required this.samples,
    required this.source,
    required this.detectedAt,
  });

  /// Float32 normalized PCM samples, 16 kHz mono. WavWriter doğrudan yutar.
  final List<double> samples;

  /// Hangi mic'ten geldi (Voice Translator dual mic için kritik; diğer
  /// modlarda her zaman `primary`).
  final AudioSource source;

  final DateTime detectedAt;

  /// 16 kHz varsayımıyla saniye cinsinden uzunluk.
  double get durationSeconds => samples.length / 16000.0;
}

/// Bir utterance'ın hangi fiziksel kaynaktan geldiği.
enum AudioSource {
  /// Ana mic:
  /// - Ders Modu / Bas Konuş: telefon dahili mic veya bağlı kulaklık mic
  ///   (Android default routing)
  /// - Voice Translator: kulaklık mic'i → chat sağ taraf
  primary,

  /// Voice Translator'da telefon dahili mic'i → chat sol taraf.
  /// Diğer modlarda yayılmaz.
  secondary,
}
