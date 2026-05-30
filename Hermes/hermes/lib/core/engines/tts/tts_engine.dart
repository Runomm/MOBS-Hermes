/// Strategy Pattern arayüzü — herhangi bir konuşma-sentezi (TTS) motoru bunu implement eder.
/// Uygulama yalnızca bu arayüzü tanır, hangi motor olduğunu bilmez.
///
/// Yeni bir motor eklemek için (örn. Coqui TTS, ElevenLabs):
/// 1. Bu sınıfı implement eden bir sınıf yaz
/// 2. Servis katmanında motor referansını değiştir
abstract class TtsEngine {
  /// Motorun adı (UI'da gösterim ve loglama için).
  String get engineName;

  /// Motor internet bağlantısı olmadan çalışabilir mi?
  bool get isOfflineCapable;

  /// Motor o anda konuşuyor mu?
  bool get isSpeaking;

  /// Motoru hazırla (gerekirse ses paketini ön-yükle, parametreleri ayarla).
  /// İlk çağrıda yapılır, sonra cache'lenir.
  Future<void> initialize();

  /// Metni verilen dilde seslendir.
  /// [languageCode]: BCP-47 kodu ('tr', 'en', 'es'...).
  /// Sentez tamamlanana veya kesilene kadar bekler.
  Future<void> speak(String text, String languageCode);

  /// Aktif konuşmayı durdur.
  Future<void> stop();

  Future<void> dispose();
}
