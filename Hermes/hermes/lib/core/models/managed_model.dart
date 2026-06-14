import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:whisper_ggml/whisper_ggml.dart';

import '../engines/translation/google_mlkit_engine.dart';
import '../engines/translation/llm_translation_engine.dart';
import '../engines/translation/translation_engine.dart';
import '../services/cancel_token.dart';
import '../services/hf_token_store.dart';
import 'nllb_model_manager.dart';
import 'vosk_model_manager.dart';
import 'vosk_models.dart';

/// Ayarlar ekranındaki "yüklü modeller" listesinin tek tip arayüzü.
///
/// Modeller heterojen (Whisper yerleşik asset / HuggingFace indirme, Vosk ağ
/// zip, ML Kit dil paketi) — UI'ın hepsini aynı kartla göstermesi için ortak
/// kontrat. Mehmet isteği: tüm modeller görünsün, istenirse silinsin/indirilsin.
abstract class ManagedModel {
  /// Kararlı kimlik (DownloadManager anahtarı). Ayarlar her açılışta yeni örnek
  /// üretir → örnek kimliğine güvenilemez; varsayılan başlık (tüm modeller tekil
  /// başlıklı). Gerekirse alt sınıf override eder.
  String get id => title;

  /// Kart başlığı, örn. "Vosk Türkçe".
  String get title;

  /// Açıklama satırı, örn. "~35MB · Türkçe konuşma tanıma".
  String get subtitle;

  /// Hangi grupta gösterilecek, örn. "Konuşma Tanıma (STT)".
  String get category;

  /// `true` → APK'ya gömülü, silinemez/indirilemez, hep hazır.
  bool get bundled;

  /// İndirme yüzde ilerlemesi destekleniyor mu? (false → belirsiz spinner)
  bool get supportsProgress;

  /// Toplam indirme boyutu (MB) — Ayarlar'da hız/ETA hesabı için. Bilinmiyor
  /// veya bundled → null. (Hız = Δyüzde × sizeMb / Δt; bkz. `DownloadStats`.)
  int? get sizeMb => null;

  /// İndirme için HuggingFace token gerekiyor mu? (Gemma gated). Varsayılan
  /// false; `true` ise UI indirmeden önce token ister/kayıtlıyı kullanır.
  bool get requiresToken => false;

  /// Model cihazda hazır (indirilmiş) mı?
  Future<bool> isReady();

  /// İndir. [onProgress] 0.0–1.0 (destekliyorsa). [cancelToken] verilirse akış
  /// indirmeleri her parçada iptali kontrol eder ([DownloadCancelledException]).
  Future<void> download({
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  });

  /// Cihazdan sil.
  Future<void> delete();
}

/// Uygulamanın tüm yönetilebilir modellerini listeler.
class ModelRegistry {
  ModelRegistry({TranslationEngine? translationEngine})
      : _translation = translationEngine ?? GoogleMLKitEngine();

  final TranslationEngine _translation;

  /// ML Kit çeviri dilleri (Manuel Çeviri ekranıyla aynı set).
  static const Map<String, String> translationLanguages = {
    'en': 'İngilizce',
    'tr': 'Türkçe',
    'es': 'İspanyolca',
    'fr': 'Fransızca',
    'de': 'Almanca',
    'it': 'İtalyanca',
  };

  List<ManagedModel> all() => [
        _WhisperModel.tiny(),
        _WhisperModel.small(),
        for (final info in VoskModels.byLang.values) _VoskLanguageModel(info),
        for (final e in translationLanguages.entries)
          _MlKitLanguageModel(_translation, e.key, e.value),
        _NllbManagedModel(),
        // Crunch (özet) modeli — de-risk sonucu Gemma3-1B (GH-hosted, streamed).
        // Qwen/Gemma/Phi-4 elendi (bozuk karakter / OOM / native hata) → listeden
        // çıkarıldı; canlı çeviri zaten NLLB/MLKit.
        _LlmManagedModel(LlmModelDef.crunch),
      ];
}

// ---------- Whisper (STT) ----------

class _WhisperModel extends ManagedModel {
  _WhisperModel._(this._model, this.title, this.subtitle, this.bundled);

  factory _WhisperModel.tiny() => _WhisperModel._(
        WhisperModel.tiny,
        'Whisper tiny',
        'Yerleşik · hızlı · İngilizce vb. (Türkçe zayıf)',
        true,
      );

  factory _WhisperModel.small() => _WhisperModel._(
        WhisperModel.small,
        'Whisper small',
        '~466MB · daha doğru · İngilizce vb.',
        false,
      );

  final WhisperModel _model;
  final WhisperController _controller = WhisperController();

  @override
  final String title;
  @override
  final String subtitle;
  @override
  final bool bundled;

  @override
  String get category => 'Konuşma Tanıma (STT)';

  @override
  bool get supportsProgress => true;

  @override
  int? get sizeMb => bundled ? null : 466;

  @override
  Future<bool> isReady() async {
    if (bundled) return true; // tiny APK asset'inden, hep var.
    final path = await _controller.getPath(_model);
    return File(path).existsSync();
  }

  @override
  Future<void> download({
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dest = await _controller.getPath(_model);
    if (File(dest).existsSync()) {
      onProgress?.call(1.0);
      return;
    }
    // `whisper_ggml`'in `downloadModel`'i `consolidateHttpClientResponseBytes`
    // kullanıyor (byte sayacı yok → ilerleme verilemez). NLLB/Vosk kalıbıyla
    // kendimiz streamed indiriyoruz ki Ayarlar'da %/hız/ETA görünsün.
    final partPath = '$dest.part';
    final part = File(partPath);
    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', _model.modelUri);
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode} — ${_model.modelUri}');
      }
      final total = resp.contentLength;
      var received = 0;
      sink = part.openWrite();
      await for (final chunk in resp.stream) {
        cancelToken?.throwIfCancelled();
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total != null && total > 0) {
          onProgress(received / total);
        }
      }
      await sink.close();
      sink = null;
      await part.rename(dest);
      onProgress?.call(1.0);
    } catch (e) {
      // Açık sink ile delete bazı platformlarda başarısız olur / handle sızar.
      try {
        await sink?.close();
      } catch (_) {}
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> delete() async {
    final path = await _controller.getPath(_model);
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }
}

// ---------- Vosk dil modeli (STT) ----------

class _VoskLanguageModel extends ManagedModel {
  _VoskLanguageModel(this._info) : _manager = VoskModelManager(_info);

  final VoskModelInfo _info;
  final VoskModelManager _manager;

  @override
  String get title => 'Vosk ${_info.langName}';

  @override
  String get subtitle => '~${_info.sizeMb}MB · ${_info.langName} konuşma tanıma';

  @override
  String get category => 'Konuşma Tanıma (STT)';

  @override
  bool get bundled => false;

  @override
  bool get supportsProgress => true;

  @override
  int? get sizeMb => _info.sizeMb;

  @override
  Future<bool> isReady() => _manager.isDownloaded();

  @override
  Future<void> download({
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _manager.download(onProgress: onProgress, cancelToken: cancelToken);

  @override
  Future<void> delete() => _manager.delete();
}

// ---------- ML Kit çeviri dili ----------

class _MlKitLanguageModel extends ManagedModel {
  _MlKitLanguageModel(this._engine, this._code, this._name);

  final TranslationEngine _engine;
  final String _code;
  final String _name;

  @override
  String get title => _name;

  @override
  String get subtitle =>
      '~${_engine.estimatedDownloadSizeMb(_code)}MB · çeviri dili';

  @override
  String get category => 'Çeviri Dilleri (ML Kit)';

  @override
  bool get bundled => false;

  @override
  bool get supportsProgress => false;

  @override
  int? get sizeMb => _engine.estimatedDownloadSizeMb(_code);

  @override
  Future<bool> isReady() => _engine.isLanguageReady(_code);

  @override
  Future<void> download({
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      // ML Kit indirmesi GMS tarafından yürütülür (akış yok) → iptal edilemez;
      // token yok sayılır. supportsProgress=false zaten iptal butonu göstermez.
      _engine.downloadLanguage(_code);

  @override
  Future<void> delete() => _engine.deleteLanguage(_code);
}

// ---------- LLM çeviri modeli (Gemma / Qwen) ----------

/// Tier2 Gemma / Tier3 Qwen LLM çeviri modelleri — Ayarlar'da gör/indir/sil
/// (NS-1, 2026-06-06). Gemma gated → HF token ([HfTokenStore]'dan, indirme
/// akışında UI doldurur). "Hazır" = diskte gerçek dosya var ([_isModelDownloaded]
/// dosya doğrulaması yapar; yanlış pozitif yok).
class _LlmManagedModel extends ManagedModel {
  _LlmManagedModel(this._def);

  final LlmModelDef _def;

  LlmTranslationEngine _engine([String? token]) =>
      LlmTranslationEngine(_def, hfToken: token);

  @override
  String get title => _def.name;

  @override
  String get subtitle => _def.requiresToken
      ? '~${_def.sizeMb}MB · oturum-sonu özet · HF token gerekir'
      : '~${_def.sizeMb}MB · oturum-sonu özet (crunch)';

  @override
  String get category => 'Özet Modeli (Crunch)';

  @override
  bool get bundled => false;

  @override
  bool get supportsProgress => true;

  @override
  int? get sizeMb => _def.sizeMb;

  @override
  bool get requiresToken => _def.requiresToken;

  @override
  Future<bool> isReady() => _engine().isLanguageReady('en');

  @override
  Future<void> download({
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Gemma için kayıtlı HF token (NS-3); Settings indirme öncesi store'u
    // doldurur (gerekirse kullanıcıdan ister). Qwen non-gated → null.
    // flutter_gemma native indirici iptali desteklemez → cancelToken best-effort
    // (yalnız başlamadan kontrol; sürerkenki native indirme durdurulamaz).
    cancelToken?.throwIfCancelled();
    final token =
        _def.requiresToken ? await HfTokenStore.instance.read() : null;
    await _engine(token).downloadModel(token: token, onProgress: onProgress);
  }

  @override
  Future<void> delete() => _engine().deleteLanguage('en');
}

// ---------- NLLB-600M NMT çeviri modeli ----------

/// NLLB-200-distilled-600M int8 (offline NMT, PC kalitesi) — Ayarlar'da
/// gör/indir/sil. 4 parça (~1.3GB) tek paket; ilerleme birleşik. App kendi
/// indirir → dosyalar app-owned (Android 15 FUSE sorunu olmaz).
class _NllbManagedModel extends ManagedModel {
  final NllbModelManager _mgr = NllbModelManager();

  @override
  String get title => 'NLLB-600M';

  @override
  String get subtitle => '~1.3GB · çevrimdışı NMT çeviri · PC kalitesi';

  @override
  String get category => 'Çeviri Modelleri (NMT)';

  @override
  bool get bundled => false;

  @override
  bool get supportsProgress => true;

  @override
  int? get sizeMb => 1334;

  @override
  Future<bool> isReady() => _mgr.allDownloaded();

  @override
  Future<void> download({
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final files = NllbModelManager.files;
    // Dosyalar çok farklı boyutta (419/470/445/5 MB) → ilerlemeyi bayt ağırlıklı
    // hesapla ki çubuk ve hız/ETA gerçekçi olsun (eşit ağırlık yanıltıcıydı).
    final totalMb = files.fold<int>(0, (s, f) => s + f.sizeMb);
    var doneMb = 0;
    for (final f in files) {
      cancelToken?.throwIfCancelled();
      await _mgr.download(f,
          cancelToken: cancelToken,
          onProgress: (p) =>
              onProgress?.call((doneMb + p * f.sizeMb) / totalMb));
      doneMb += f.sizeMb;
    }
  }

  @override
  Future<void> delete() => _mgr.deleteAll();
}
