import 'dart:async';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'translation_engine.dart';

/// ML Kit dil paketi indirmesi için zaman aşımı. ML Kit çeviri modelini
/// **tamamen Google Play Services (GMS) indirir** — biz yalnız tetikleriz.
/// Bazı cihazlarda (öz. MIUI/Poco, agresif arka plan kısıtı) GMS indirmeyi
/// başlatıp tamamlamıyor → `downloadModel` Future'ı **asla** çözülmüyor (sonsuz
/// "indiriliyor"). ~30MB'lık paket yavaş mobil veride bile ~1 dk'da iner; bu süre
/// aşılırsa GMS'in getiremediğini varsayıp net hata fırlatır (sonsuz beklemek
/// yerine). Mehmet 2026-06-08: Poco'da 40+ dk denedi, model dizini boş kaldı.
const Duration kMlKitDownloadTimeout = Duration(seconds: 90);

/// ML Kit dil paketi GMS tarafından getirilemediğinde (zaman aşımı) fırlatılır.
/// UI bunu yakalayıp `$e` olarak gösterir → kullanıcı **NLLB**'ye yönlendirilir
/// (NLLB tamamen offline, GMS'siz çalışır).
class MlKitDownloadException implements Exception {
  const MlKitDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// ML Kit dil paketi indirmesini [timeout] ile sarar. Süre aşılırsa (GMS
/// indirmeyi tamamlamıyor → Future asla çözülmüyor) [MlKitDownloadException]
/// fırlatır; timeout-dışı hatalar olduğu gibi propagate olur. Saf/test edilebilir
/// (platform bağımsız) — gerçek indirmeyi [download] callback'i yapar.
Future<void> runMlKitDownloadWithTimeout(
  Future<void> Function() download, {
  Duration timeout = kMlKitDownloadTimeout,
}) async {
  try {
    await download().timeout(timeout);
  } on TimeoutException {
    throw const MlKitDownloadException(
      'Google Play çeviri modelini indiremedi (zaman aşımı). Cihazın Google '
      'Play Servisleri modeli getiremiyor olabilir — "Akıllı (NLLB)" motorunu '
      'seçin (tamamen çevrimdışı).',
    );
  }
}

/// Google ML Kit On-Device Translation motoru.
/// İlk çağrıda ~30MB'lık dil modelini indirir, sonrasında tamamen offline çalışır.
class GoogleMLKitEngine implements TranslationEngine {
  OnDeviceTranslator? _translator;
  TranslateLanguage? _currentSource;
  TranslateLanguage? _currentTarget;

  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();

  @override
  String get engineName => 'Google ML Kit';

  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> ensureModelLoaded(String fromCode, String toCode) async {
    final source = _languageFromCode(fromCode);
    final target = _languageFromCode(toCode);

    // Model dosyalarını indir (yüklüyse atlar). isWifiRequired:false — varsayılan
    // WiFi şartı mobil veride indirmeyi ASLA başlatmıyordu (Mehmet 2026-06-08:
    // "indiriliyor"da takılı + TR "no existing model file"). Paket ~30MB, kullanıcı
    // indir'e bastı → mobil veriye izin ver.
    if (!await _modelManager.isModelDownloaded(source.bcpCode)) {
      await runMlKitDownloadWithTimeout(() =>
          _modelManager.downloadModel(source.bcpCode, isWifiRequired: false));
    }
    if (!await _modelManager.isModelDownloaded(target.bcpCode)) {
      await runMlKitDownloadWithTimeout(() =>
          _modelManager.downloadModel(target.bcpCode, isWifiRequired: false));
    }

    // Dil çifti değiştiyse translator'ı yeniden oluştur
    if (_currentSource != source || _currentTarget != target) {
      await _translator?.close();
      _translator = OnDeviceTranslator(
        sourceLanguage: source,
        targetLanguage: target,
      );
      _currentSource = source;
      _currentTarget = target;
    }
  }

  @override
  Future<String> translate(
    String text,
    String fromCode,
    String toCode, {
    List<TranslationTurn> context = const [], // MLKit bağlamsız → yok sayılır
  }) async {
    await ensureModelLoaded(fromCode, toCode);
    return _translator!.translateText(text);
  }

  // ---------- Dil paketi yönetimi ----------

  @override
  Future<bool> isLanguageReady(String code) async {
    final lang = _languageFromCode(code);
    return _modelManager.isModelDownloaded(lang.bcpCode);
  }

  /// ML Kit'in resmi belgelerinde dil paketi boyutu yaklaşık ~30MB olarak
  /// belirtiliyor; dilden dile küçük farklar var ama API tam değer vermiyor.
  @override
  int estimatedDownloadSizeMb(String code) => 30;

  @override
  Future<void> downloadLanguage(String code) async {
    final lang = _languageFromCode(code);
    if (await _modelManager.isModelDownloaded(lang.bcpCode)) return;
    // isWifiRequired:false — mobil veride de insin (varsayılan WiFi şartı takılıyordu).
    // Timeout sargısı: GMS indirmeyi tamamlamazsa sonsuz beklemek yerine net hata.
    await runMlKitDownloadWithTimeout(
        () => _modelManager.downloadModel(lang.bcpCode, isWifiRequired: false));
  }

  @override
  Future<void> deleteLanguage(String code) async {
    final lang = _languageFromCode(code);
    if (!await _modelManager.isModelDownloaded(lang.bcpCode)) return;
    await _modelManager.deleteModel(lang.bcpCode);

    // Silinen dil mevcut translator'ın kaynağı/hedefi ise translator'ı invalide et.
    if (_currentSource == lang || _currentTarget == lang) {
      await _translator?.close();
      _translator = null;
      _currentSource = null;
      _currentTarget = null;
    }
  }

  @override
  Future<void> dispose() async {
    await _translator?.close();
    _translator = null;
    _currentSource = null;
    _currentTarget = null;
  }

  /// BCP-47 dil kodunu (örn. 'tr', 'en') ML Kit enum'una çevirir.
  TranslateLanguage _languageFromCode(String code) {
    return TranslateLanguage.values.firstWhere(
      (lang) => lang.bcpCode == code,
      orElse: () =>
          throw ArgumentError('ML Kit bu dili desteklemiyor: $code'),
    );
  }
}
