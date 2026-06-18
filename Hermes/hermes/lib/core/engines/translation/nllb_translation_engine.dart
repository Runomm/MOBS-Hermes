import 'dart:io';

import '../../models/nllb_model_manager.dart';
import 'nllb_onnx_translator.dart';
import 'translation_engine.dart';

/// NLLB-200-distilled-600M (int8 ONNX) çevirisini [TranslationEngine] arayüzüne
/// saran adaptör — Tier "Akıllı/NMT" (Mehmet 2026-06-07: LLM çeviriyi bırak,
/// NMT'ye geç). Cihaz testi GEÇTİ (S25 Ultra): PC kalitesi, hızlı, OOM yok.
///
/// **Tek RAM kopyası:** `_shared` static [NllbOnnxTranslator] — model ~1.3GB,
/// iki kez yüklenmesin (LlmHost mantığı). Tüm instance'lar paylaşır.
///
/// **Dil kodu:** Uygulama BCP-47 ('tr','en'...) kullanır; NLLB FLORES-200
/// ('tur_Latn'...) ister → [_nllbCode] eşlemesi. Dil tokenları [NllbOnnxTranslator]
/// içinde +offset'li haritada.
///
/// **Saf NMT:** `context` (önceki turlar) YOK SAYILIR — NLLB bağlam kullanmaz.
class NllbTranslationEngine implements TranslationEngine {
  final NllbModelManager _mgr = NllbModelManager();

  /// Paylaşılan tek translator (1.3GB tek kopya).
  static NllbOnnxTranslator? _shared;

  /// BCP-47 → NLLB FLORES-200 dil kodu. Desteklenen Faz-1 dilleri.
  static const Map<String, String> _nllbCode = {
    'tr': 'tur_Latn',
    'en': 'eng_Latn',
    'es': 'spa_Latn',
    'de': 'deu_Latn',
    'fr': 'fra_Latn',
    'it': 'ita_Latn',
  };

  static bool supportsLanguage(String code) => _nllbCode.containsKey(code);

  /// Paylaşılan NLLB şu an RAM'de mi?
  static bool get sharedLoaded => _shared != null;

  /// NLLB'yi arka planda RAM'e al (açılışta — en çok kullanılan motor; Mehmet
  /// 2026-06-13). Model inmemişse sessizce atlar (hata fırlatmaz).
  static Future<void> preloadShared() async {
    final e = NllbTranslationEngine();
    try {
      if (await e.isLanguageReady('en')) {
        await e.ensureModelLoaded('en', 'tr');
      }
    } catch (_) {
      // Önyükleme best-effort — başarısızsa ilk çeviride tekrar denenir.
    }
  }

  /// Paylaşılan NLLB'yi RAM'den boşalt (offline LLM özetine yer açmak için).
  /// Model dosyaları diskte kalır; sonra [preloadShared] ile geri yüklenir.
  static Future<void> unloadShared() async {
    await _shared?.dispose();
    _shared = null;
  }

  /// iOS hız: aktif bir ekran/oturum boyunca NLLB session'larını resident tut
  /// (her çeviride 3 ONNX session'ı yeniden açma maliyetini kaldırır). OCR
  /// çok-blok + ardışık Manuel çeviride faydalı. `_shared` henüz yoksa ilk
  /// çeviride yaratılınca pin etkili olur; o yüzden pin bayrağını da koru.
  static bool _pinPending = false;
  static void pinShared() {
    _pinPending = true;
    _shared?.pinResident();
  }

  /// Resident pin'i kaldır + (iOS'te) session'ları kapatıp RAM'i geri ver.
  static Future<void> unpinShared() async {
    _pinPending = false;
    await _shared?.unpinResident();
  }

  @override
  String get engineName => 'NLLB-600M';

  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> ensureModelLoaded(String fromCode, String toCode) async {
    if (!_nllbCode.containsKey(fromCode) || !_nllbCode.containsKey(toCode)) {
      throw ArgumentError('NLLB bu dil çiftini desteklemiyor: $fromCode→$toCode');
    }
    if (!await _mgr.allDownloaded()) {
      throw StateError('NLLB modeli cihazda yok (önce indir).');
    }
    _shared ??= NllbOnnxTranslator(
      encoderPath: await _mgr.pathFor(NllbModelManager.fileById('encoder')),
      decoderPath: await _mgr.pathFor(NllbModelManager.fileById('decoder')),
      decoderWithPastPath:
          await _mgr.pathFor(NllbModelManager.fileById('decoder_past')),
      spModelPath: await _mgr.pathFor(NllbModelManager.fileById('tokenizer')),
      // iOS: 3 session'ı aynı anda tutma → jetsam çöküşü; sıralı yükle/boşalt.
      lowMemory: Platform.isIOS,
    );
    // Pin bayrağı session yaratımından önce konmuşsa (ekran açıkken _shared null
    // idiyse) yeni instance'a uygula → load() resident yaratır.
    if (_pinPending) _shared!.pinResident();
    await _shared!.load();
  }

  @override
  Future<String> translate(
    String text,
    String fromCode,
    String toCode, {
    List<TranslationTurn> context = const [], // NMT → yok sayılır
  }) async {
    await ensureModelLoaded(fromCode, toCode);
    return _shared!.translate(
      text,
      srcLang: _nllbCode[fromCode]!,
      tgtLang: _nllbCode[toCode]!,
    );
  }

  @override
  Future<bool> isLanguageReady(String code) async =>
      _nllbCode.containsKey(code) && await _mgr.allDownloaded();

  /// Tüm NLLB parçaları (enc+dec+past+sp) tek pakettir; ~1.3GB.
  @override
  int estimatedDownloadSizeMb(String code) => 1334;

  @override
  Future<void> downloadLanguage(String code) async {
    // NLLB çok dilli tek model — tüm dosyaları indir (dil-bağımsız).
    for (final f in NllbModelManager.files) {
      await _mgr.download(f);
    }
  }

  @override
  Future<void> deleteLanguage(String code) async {
    await dispose();
    await _mgr.deleteAll();
  }

  @override
  Future<void> dispose() async {
    await _shared?.dispose();
    _shared = null;
  }
}
