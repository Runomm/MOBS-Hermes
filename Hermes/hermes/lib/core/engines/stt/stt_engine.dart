/// Strategy Pattern arayüzü — herhangi bir konuşma-tanıma motoru bunu implement eder.
/// Uygulama yalnızca bu arayüzü tanır.
///
/// Yeni bir motor eklemek için (örn. SeamlessM4T, native iOS SFSpeechRecognizer):
/// 1. Bu sınıfı implement eden bir sınıf yaz
/// 2. Servis katmanında motor referansını değiştir
abstract class SttEngine {
  /// Motorun adı (UI'da gösterim ve loglama için).
  String get engineName;

  /// Motor internet bağlantısı olmadan çalışabilir mi?
  bool get isOfflineCapable;

  /// Modeli hazırla (asset'ten kopyala veya gerekirse indir).
  /// İlk çağrıda yapılır, sonra cache'lenir.
  Future<void> initialize();

  /// Ses dosyasından (yol) metin çıkar.
  /// [language]: BCP-47 kodu ('tr', 'en', 'es'...) veya 'auto' (otomatik algılama).
  Future<String> transcribeFile(String audioPath, {String language = 'auto'});

  /// Hız–doğruluk dengesini değiştir.
  /// Konuşma modu için fast, ders modu için accurate.
  Future<void> setSpeedMode(SttSpeedMode mode);

  /// Aktif hız modu.
  SttSpeedMode get speedMode;

  Future<void> dispose();
}

/// STT motorunun hız–doğruluk tercihi.
enum SttSpeedMode {
  /// Whisper tiny — düşük gecikme, makul doğruluk.
  /// Konuşma modu varsayılanı.
  fast,

  /// Whisper small — yüksek doğruluk, yüksek gecikme.
  /// Ders modu varsayılanı.
  accurate,
}
