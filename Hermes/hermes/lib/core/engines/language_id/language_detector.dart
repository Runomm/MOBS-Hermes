/// Strategy Pattern arayüzü — herhangi bir dil tespit motoru bunu implement eder.
///
/// Konuşma Modu'nda çift yönlü routing için kritik: kullanıcı bir sözce
/// söyledi, app hangi taraftan (source/target) geldiğini anlamak için
/// metni dil tespit motoruna verir.
///
/// Yeni bir motor eklemek için (örn. fastText, cld3):
/// 1. Bu sınıfı implement eden bir sınıf yaz
/// 2. Servis katmanında motor referansını değiştir
abstract class LanguageDetector {
  /// Motorun adı (UI ve loglama için).
  String get engineName;

  /// Motor offline çalışır mı?
  bool get isOfflineCapable;

  /// Motoru hazırla (model yükleme vb). İlk çağrıda yapılır.
  Future<void> initialize();

  /// Metnin dilini tahmin et.
  ///
  /// Dönen [LanguageDetectionResult]'in `confidence` değeri implementasyona
  /// göre [minConfidence] ile karşılaştırılır; altındaysa **null** döner.
  /// Çağıran "null = belirsiz, sessizce drop" anlamına geldiğini bilir
  /// (HERMES_KONUSMA_MODU_TASARIM.md karar f).
  ///
  /// [text] boşsa null döner.
  Future<LanguageDetectionResult?> detect(
    String text, {
    double minConfidence = 0.6,
  });

  Future<void> dispose();
}

/// Dil tespit sonucu — BCP-47 kodu + tespit motorunun verdiği confidence (0..1).
class LanguageDetectionResult {
  const LanguageDetectionResult({
    required this.languageCode,
    required this.confidence,
  });

  /// BCP-47 dil kodu ('tr', 'en', 'es', ...). 'und' = undetermined
  /// (motor hiçbir dile karar verememiş; bu sonuç çağırana ulaşmaz çünkü
  /// `detect` zaten null döner).
  final String languageCode;

  /// 0..1. Motorun "ne kadar emin" olduğu.
  final double confidence;

  @override
  String toString() =>
      'LanguageDetectionResult($languageCode, ${confidence.toStringAsFixed(2)})';
}
