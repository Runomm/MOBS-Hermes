import 'package:flutter/foundation.dart';

import 'whisper_cpp_engine.dart';
import 'stt_engine.dart';
import 'vosk_stt_engine.dart';

/// STT router (Mehmet kararı 2026-06-01): **Vosk ana motor, Whisper fallback.**
///
/// Her transkriptte dile bakar:
/// - Dilin Vosk modeli var VE cihaza inmişse → [VoskSttEngine] (daha doğru,
///   özellikle Türkçe; Apache-2.0).
/// - Aksi halde (Vosk desteği yok / model inmemiş / Vosk hata verirse) →
///   [WhisperCppEngine] fallback (geniş dil kapsamı).
///
/// `SttEngine` Strategy'sini implement eder; pipeline (ConversationSession
/// Manager) değişmeden çalışır. Sadece WAV (16kHz mono PCM16) girdisi için —
/// Vosk ham PCM ister; pipeline `WavWriter` ile zaten bunu üretiyor.
class HybridSttEngine implements SttEngine {
  HybridSttEngine({bool whisperNoFallback = true})
      : _whisper = WhisperCppEngine(noFallback: whisperNoFallback);

  final VoskSttEngine _vosk = VoskSttEngine();
  final WhisperCppEngine _whisper;

  /// Son transkripti hangi motor işledi (UI görünürlüğü — Mehmet 2026-06-01:
  /// "hiçbir mod hangi modelin çalıştığını göstermiyor"). Her transcribeFile
  /// sonrası güncellenir; ekranlar `ValueListenableBuilder` ile gösterir.
  final ValueNotifier<String> activeBackend = ValueNotifier<String>('—');

  @override
  String get engineName => 'Hybrid (Vosk + Whisper)';

  @override
  bool get isOfflineCapable => true;

  @override
  SttSpeedMode get speedMode => _whisper.speedMode;

  @override
  Future<void> initialize() async {
    // TEMBEL — burada Whisper'ı eager init ETME. Aksi halde Ders Modu (accurate)
    // başlarken Vosk işi yapacak olsa bile Whisper small (~466MB) inebilir.
    // Her iki motor kendini transcribeFile'da lazy-init ediyor: Whisper
    // `if(!_initialized)`, Vosk dil-başına model yükler. Fallback gerçekten
    // gerektiğinde (Vosk yok/inmemiş) Whisper o an hazırlanır.
  }

  @override
  Future<String> transcribeFile(
    String audioPath, {
    String language = 'auto',
  }) async {
    if (await _vosk.canHandle(language)) {
      try {
        final result =
            await _vosk.transcribeFile(audioPath, language: language);
        activeBackend.value = 'Vosk · $language';
        return result;
      } catch (_) {
        // Vosk beklenmedik şekilde patlarsa (bozuk model vb.) sessizce
        // Whisper'a düş — kullanıcı transkriptsiz kalmasın.
      }
    }
    final result =
        await _whisper.transcribeFile(audioPath, language: language);
    final model =
        _whisper.speedMode == SttSpeedMode.accurate ? 'small' : 'tiny';
    activeBackend.value = 'Whisper · $model';
    return result;
  }

  @override
  Future<void> setSpeedMode(SttSpeedMode mode) async {
    // Whisper fallback'in hız/doğruluk modunu yönet; Vosk'ta no-op.
    await _whisper.setSpeedMode(mode);
    await _vosk.setSpeedMode(mode);
  }

  @override
  Future<void> dispose() async {
    activeBackend.dispose();
    await _vosk.dispose();
    await _whisper.dispose();
  }
}
