/// Bir çeviri için **bağlam** — önceki konuşma turu (kaynak + çeviri, kendi
/// dilleriyle). LLM motorlar bununla referansları çözer ve olası tanıma
/// hatalarını düzeltir ("market" sonra "marcus" duyulursa konuya uymadığını
/// fark edip düzeltir). MLKit gibi bağlamsız motorlar yok sayar.
class TranslationTurn {
  const TranslationTurn({
    required this.fromCode,
    required this.toCode,
    required this.sourceText,
    required this.translatedText,
  });

  final String fromCode;
  final String toCode;
  final String sourceText;
  final String translatedText;
}

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
  ///
  /// [context]: önceki konuşma turları (en eskiden yeniye). Bağlam-duyarlı
  /// motorlar (LLM) referans çözümü + tanıma hatası düzeltmesi için kullanır;
  /// bağlamsız motorlar (MLKit) yok sayar.
  Future<String> translate(
    String text,
    String fromCode,
    String toCode, {
    List<TranslationTurn> context = const [],
  });

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
