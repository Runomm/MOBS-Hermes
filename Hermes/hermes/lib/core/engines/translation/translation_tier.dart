import 'dart:io';

import '../../repositories/conversation_repository.dart' show SessionMode;
import 'google_mlkit_engine.dart';
import 'llm_translation_engine.dart';
import 'nllb_translation_engine.dart';
import 'translation_engine.dart';

/// Çeviri motoru katmanları:
/// - [mlkit]  Hızlı — Google ML Kit, anında/hafif, her zaman hazır.
/// - [nllb]   Akıllı — NLLB-600M int8 NMT (offline, ~1.3GB, PC kalitesi). Çeviri
///            için önerilen "Akıllı" katman (Mehmet 2026-06-07: LLM çeviriyi bırak).
/// - [gemma]/[qwen] LLM — çeviri için artık kullanılmaz (crunch/özet için kalır).
enum TranslationTier { mlkit, nllb, gemma, qwen }

extension TranslationTierX on TranslationTier {
  String get label => switch (this) {
        TranslationTier.mlkit => 'ML Kit',
        TranslationTier.nllb => 'NLLB',
        TranslationTier.gemma => 'Gemma',
        TranslationTier.qwen => 'Qwen',
      };

  /// Kısa açıklama (UI seçici için).
  String get hint => switch (this) {
        TranslationTier.mlkit => 'Anında · hafif',
        TranslationTier.nllb => 'Çevrimdışı · kaliteli',
        TranslationTier.gemma => 'Akıllı · hızlı',
        TranslationTier.qwen => 'En kaliteli · yavaş',
      };

  /// LLM mı? (gemma/qwen — token/RAM/crunch davranışı). NLLB saf NMT → false.
  bool get isLlm =>
      this == TranslationTier.gemma || this == TranslationTier.qwen;

  /// İndirme boyutu (LLM/NMT model boyutu, MLKit dil-başına ~30MB).
  int get approxSizeMb => switch (this) {
        TranslationTier.mlkit => 30,
        TranslationTier.nllb => 1334,
        TranslationTier.gemma => LlmModelDef.gemma.sizeMb,
        TranslationTier.qwen => LlmModelDef.qwen.sizeMb,
      };
}

/// Mod karakterine göre **varsayılan** katman (Mehmet seçimi 2026-06-04):
/// Ders=Qwen (transkript kayıtlı, kalite), Bas Konuş=MLKit (canlı), Manuel=MLKit.
/// Kullanıcı her modda değiştirebilir.
TranslationTier defaultTierFor(SessionMode mode) => switch (mode) {
      SessionMode.lecture => TranslationTier.qwen,
      SessionMode.pushToTalk => TranslationTier.mlkit,
      SessionMode.voiceTranslator => TranslationTier.mlkit,
    };

/// Manuel Çeviri varsayılanı (mod-dışı ana ekran).
const TranslationTier kManualDefaultTier = TranslationTier.mlkit;

/// Seçilen katman için uygun [TranslationEngine] üretir. LLM katmanları
/// paylaşılan [LlmHost] üzerinden çalışır (tek-LLM-RAM). Gemma gated → [hfToken].
///
/// **iOS choke-point (2026-06-19):** ML Kit çevirisi iOS'te bozuk (static linkage
/// resource bundle'ını kırıyor) → `mlkit` istense bile NLLB'ye yönlendirilir.
/// Selector tier'ı zaten gizliyor; bu, doğrudan tier geçen ekranlar (Bas Konuş /
/// Konferans varsayılan mlkit) için son güvence — iOS'te hiçbir yol ML Kit
/// çalıştırmaz. [isTierReady] de bu fonksiyonu kullandığından otomatik uyumlu.
TranslationEngine createTranslationEngine(
  TranslationTier tier, {
  String? hfToken,
}) {
  if (Platform.isIOS && tier == TranslationTier.mlkit) {
    tier = TranslationTier.nllb;
  }
  return switch (tier) {
    TranslationTier.mlkit => GoogleMLKitEngine(),
    TranslationTier.nllb => NllbTranslationEngine(),
    TranslationTier.gemma =>
      LlmTranslationEngine(LlmModelDef.gemma, hfToken: hfToken),
    TranslationTier.qwen =>
      LlmTranslationEngine(LlmModelDef.qwen, hfToken: hfToken),
  };
}

/// Bir katman + dil çifti **gerçekten hazır mı** — her iki yönün modeli de cihazda
/// mı? (KRİTİK: MLKit "hep hazır" DEĞİL — dil paketi (~30MB/dil) inmemiş olabilir;
/// eskiden hazır varsayılıp "no existing model file" patlıyordu — Mehmet 2026-06-08.)
///
/// [sourceLang]/[targetLang] `null` ise (örn. OCR "otomatik algıla") o yön atlanır
/// (çalışma anında denenir). MLKit: iki dil paketi; NLLB: 4 dosya; LLM: model dosyası.
Future<bool> isTierReady(
  TranslationTier tier,
  String? sourceLang,
  String? targetLang, {
  String? hfToken,
}) async {
  final engine = createTranslationEngine(tier, hfToken: hfToken);
  Future<bool> ready(String? code) async {
    if (code == null) return true; // bilinmiyor (auto) → çalışma anına bırak
    try {
      return await engine.isLanguageReady(code);
    } on ArgumentError {
      return true; // katman bu dili tanımıyor → engelleme, çalışma anına bırak
    }
  }

  return await ready(sourceLang) && await ready(targetLang);
}
