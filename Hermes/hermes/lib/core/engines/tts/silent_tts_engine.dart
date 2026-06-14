import 'tts_engine.dart';

/// Hiçbir şey seslendirmeyen TTS motoru — Ders Modu gibi "sadece altyazı"
/// senaryoları için (canlı konuşmacının sesi üstüne TTS bindirmesin).
///
/// Manager pipeline'ı her zaman `tts.speak` çağırır; sesli çeviri istenmeyen
/// modlarda bu no-op motor enjekte edilir (TTS toggle'ı açıkça açılınca
/// `NativeOsTtsEngine`'e geçilir).
class SilentTtsEngine implements TtsEngine {
  const SilentTtsEngine();

  @override
  String get engineName => 'Silent';

  @override
  bool get isOfflineCapable => true;

  @override
  bool get isSpeaking => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(String text, String languageCode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
