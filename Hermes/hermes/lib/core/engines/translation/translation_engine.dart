/// Strategy Pattern arayüzü — herhangi bir çeviri motoru bunu implement eder.
/// Uygulama yalnızca bu arayüzü tanır, hangi motor olduğunu bilmez.
///
/// Yeni bir motor eklemek için (örn. Argos, NLLB, SeamlessM4T):
/// 1. Bu sınıfı implement eden bir sınıf yaz
/// 2. Servis katmanında motor referansını değiştir
/// Uygulama kodunun geri kalanı hiç değişmez.
abstract class TranslationEngine {
  /// Motorun adı (UI'da gösterim ve loglama için).
  String get engineName;

  /// Motor internet bağlantısı olmadan çalışabilir mi?
  bool get isOfflineCapable;

  /// Belirtilen dil çiftinin modelinin yüklü olduğunu garantiler.
  /// İlk seferde modeli indirebilir; bu durumda internet bağlantısı gerekir.
  Future<void> ensureModelLoaded(String fromCode, String toCode);

  /// Metni kaynak dilden hedef dile çevirir.
  /// Gerekirse önce ensureModelLoaded çağrılır.
  Future<String> translate(String text, String fromCode, String toCode);

  // ---------- Dil paketi yönetimi ----------
  // Motor bu işlemleri desteklemiyorsa (örn. tamamen online bir API),
  // override edip mantıklı default'lar dönebilir.

  /// Verilen dilin paketi cihazda hazır mı (indirilmiş, kullanıma açık)?
  Future<bool> isLanguageReady(String code);

  /// Verilen dil için tahmini indirme boyutu (MB).
  /// Tam değer motor API'sinde yoksa hardcoded ortalama dönülebilir.
  int estimatedDownloadSizeMb(String code);

  /// Verilen dilin paketini indirir. Internet gerekir.
  /// Zaten indirilmişse no-op.
  Future<void> downloadLanguage(String code);

  /// Verilen dilin paketini cihazdan siler.
  Future<void> deleteLanguage(String code);

  /// Kaynakları serbest bırakır (translator instance'ı kapatır).
  Future<void> dispose();
}
