import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/llm_text.dart';
import 'translation_engine.dart';

/// Bir LLM modelinin statik tanımı (crunch özet modeli + legacy çeviri tier'ları).
class LlmModelDef {
  const LlmModelDef({
    required this.id,
    required this.name,
    required this.url,
    required this.modelType,
    required this.fileType,
    required this.sizeMb,
    required this.requiresToken,
    required this.idMatch,
    this.selfHosted = false,
  });

  final String id; // 'gemma' | 'qwen'
  final String name; // UI etiketi
  final String url;
  final ModelType modelType;
  final ModelFileType fileType;
  final int sizeMb;
  final bool requiresToken; // Gemma gated → HF token
  final String idMatch; // listInstalledModels filename'inde aranan alt-dize

  /// `true` → model **kendi GitHub Release**'imizde host'lanır → bizim güvenilir
  /// **streamed http** indiricimizle iner + `fromFile` ile flutter_gemma'ya
  /// verilir (Faz B, 2026-06-09). flutter_gemma'nın native `fromNetwork`
  /// indiricisi büyük dosyada sessizce çöküyordu + HF Xet CDN dart:io TLS'i
  /// kırıyordu; GH + streamed bunu kökten çözer. `false` → HF'den fromNetwork
  /// (native OkHttp Xet'i kaldırır; legacy çeviri tier'ları için).
  final bool selfHosted;

  /// Qwen2.5-1.5B (Apache-2.0, non-gated) — Tier3, en yüksek kalite.
  static const qwen = LlmModelDef(
    id: 'qwen',
    name: 'Qwen2.5-1.5B',
    url:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_seq128_q8_ekv1280.task',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
    sizeMb: 1567,
    requiresToken: false,
    idMatch: 'qwen',
  );

  /// Gemma3-1B-IT (gated → HF token) — Tier2, Qwen'e yakın kalite, daha hızlı.
  static const gemma = LlmModelDef(
    id: 'gemma',
    name: 'Gemma3-1B-IT',
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    sizeMb: 555,
    requiresToken: true,
    idMatch: 'gemma',
  );

  /// Phi-4-mini-instruct (MIT, non-gated, 3.8B) — **crunch için** (Mehmet
  /// 2026-06-06: "en güçlü"). Qwen'den akıllı; ağır (~3.76GB) → SD860'ta OOM
  /// riski, yalnız oturum-sonu offline crunch'ta + sonra unload. Canlı çeviride
  /// KULLANILMAZ (yavaş).
  static const phi4 = LlmModelDef(
    id: 'phi4',
    name: 'Phi-4-mini',
    url:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv1280.task',
    modelType: ModelType.phi,
    fileType: ModelFileType.task,
    sizeMb: 3761,
    requiresToken: false,
    idMatch: 'phi',
  );

  /// DeepSeek-R1-Distill-Qwen-1.5B (MIT, non-gated) — Phi-4 OOM/çok yavaş
  /// kalırsa crunch için yedek (~1.77GB, akıl yürüten distill, Qwen ile aynı
  /// boyut sınıfı). Düşünme (think) token çıktısı `sanitizeLlmOutput` temizler.
  static const deepseek = LlmModelDef(
    id: 'deepseek',
    name: 'DeepSeek-R1 1.5B',
    url:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv1280.task',
    modelType: ModelType.deepSeek,
    fileType: ModelFileType.task,
    sizeMb: 1774,
    requiresToken: false,
    idMatch: 'deepseek',
  );

  /// Gemma3-1B-IT q8 — **crunch (özet) modeli** (cihaz de-risk 2026-06-09:
  /// Mehmet "gemma yeterli seviyede"; Qwen bozuk karakter+soru sordu, Phi-4 OOM
  /// çöktü, gemma-4-E2B native invoke hatası). **Kendi GitHub Release**'imizde
  /// host (selfHosted) → streamed indirici + `fromFile` (Phi-4 native-çökme +
  /// HF Xet TLS sorunu biter; kullanıcı için token gerekmez — biz re-host ettik).
  static const gemma3 = LlmModelDef(
    id: 'gemma3',
    name: 'Gemma3-1B (özet)',
    url:
        'https://github.com/Runomm/MOBS-Hermes/releases/download/nllb-600m-int8-v1/Gemma3-1B-IT_multi-prefill-seq_q8_ekv1280.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    sizeMb: 1005,
    requiresToken: false,
    idMatch: 'gemma3-1b-it',
    selfHosted: true,
  );

  /// **Crunch modeli** (oturum sonu özet). Tek değiştirme noktası.
  static const crunch = gemma3;
}

/// [def] modelinin (selfHosted) yerel dosya yolu — `<appDocs>/<url-basename>`.
/// Streamed indirme buraya yazar, `fromFile` buradan yükler, readiness bunu
/// kontrol eder (tek kaynak).
Future<String> llmLocalPath(LlmModelDef def) async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, p.basename(Uri.parse(def.url).path));
}

/// selfHosted modeli streamed indirir (`.part` → atomik rename, [onProgress]
/// 0–1). GitHub Release standart HTTPS (302 redirect otomatik izlenir).
Future<void> _streamLlmDownload(
  String url,
  String dest, {
  String? authToken,
  void Function(double progress)? onProgress,
}) async {
  final part = File('$dest.part');
  final client = http.Client();
  IOSink? sink;
  try {
    final req = http.Request('GET', Uri.parse(url));
    if (authToken != null && authToken.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $authToken';
    }
    final resp = await client.send(req);
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode} — $url');
    }
    final total = resp.contentLength;
    var received = 0;
    sink = part.openWrite();
    await resp.stream.forEach((chunk) {
      sink!.add(chunk);
      received += chunk.length;
      if (onProgress != null && total != null && total > 0) {
        onProgress(received / total);
      }
    });
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

/// **Tek-LLM-RAM koordinatörü** (singleton). flutter_gemma'da aynı anda yalnız
/// bir aktif model olabilir; cihaz (SD860) iki LLM'i RAM'de taşıyamaz → OOM.
/// Model değişiminde önceki handle kapatılır, yenisi yüklenir. Birden çok
/// [LlmTranslationEngine] (Gemma + Qwen) bu host üzerinden sıraya girer.
class LlmHost {
  LlmHost._();
  static final LlmHost instance = LlmHost._();

  static const int _defaultMaxTokens = 512;

  String? _loadedId;
  int? _loadedMaxTokens;
  InferenceModel? _model;

  /// Hâlâ RAM'de yüklü modelin id'si (yoksa null).
  String? get loadedId => _loadedId;

  /// [def] modeliyle [prompt]'u çalıştırır. Gerekirse modeli yükler (önce
  /// farklı bir model yüklüyse onu kapatır). Çeviri için her çağrı **taze
  /// session** (geçmiş bağlam sızması olmasın).
  ///
  /// [maxTokens]: üretim üst sınırı. Canlı çeviri kısa (512); konferans crunch
  /// daha uzun çıktı ister → farklı `maxTokens` gelince model yeniden yüklenir.
  Future<String> generate(
    LlmModelDef def,
    String prompt, {
    String? token,
    int maxTokens = _defaultMaxTokens,
  }) async {
    if (_loadedId != def.id || _model == null || _loadedMaxTokens != maxTokens) {
      await unload();
      // install() idempotent: indirilmişse atlar, modeli AKTİF yapar.
      if (def.selfHosted) {
        // GH'den streamed inen yerel dosyadan yükle (kopyalamaz, yerinde referans).
        final path = await llmLocalPath(def);
        if (!File(path).existsSync()) {
          throw StateError('${def.name} modeli indirilmedi.');
        }
        await FlutterGemma.installModel(
                modelType: def.modelType, fileType: def.fileType)
            .fromFile(path)
            .install();
      } else {
        await FlutterGemma.installModel(
                modelType: def.modelType, fileType: def.fileType)
            .fromNetwork(def.url, token: def.requiresToken ? token : null)
            .install();
      }
      _model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.cpu, // SD860'te GPU LLM güvenilmez
      );
      _loadedId = def.id;
      _loadedMaxTokens = maxTokens;
    }
    final session = await _model!.createSession();
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      // On-device LLM çıktısındaki bozuk/özel karakterleri temizle (#2,
      // 2026-06-05). Tek choke point → canlı çeviri + crunch özeti birlikte.
      return sanitizeLlmOutput(await session.getResponse());
    } finally {
      await session.close();
    }
  }

  /// Yüklü modeli RAM'den boşaltır.
  Future<void> unload() async {
    await _model?.close();
    _model = null;
    _loadedId = null;
    _loadedMaxTokens = null;
  }

  /// Yalnız belirtilen model yüklüyse boşaltır (engine dispose için).
  Future<void> unloadIfLoaded(String id) async {
    if (_loadedId == id) await unload();
  }
}

/// LLM tabanlı çeviri motoru (Tier2 Gemma / Tier3 Qwen). [TranslationEngine]
/// arayüzünü uygular; uygulama hangi LLM olduğunu bilmeden kullanır.
///
/// LLM çok dilli → "dil hazır" = **modelin indirilmiş** olması (dil-başına
/// model yok). Yükleme/RAM disiplini [LlmHost] üzerinden.
class LlmTranslationEngine implements TranslationEngine {
  LlmTranslationEngine(this.def, {this.hfToken});

  final LlmModelDef def;
  final String? hfToken;

  /// Prompt için BCP-47 kodu → dil adı.
  static const _langNames = {
    'tr': 'Turkish',
    'en': 'English',
    'es': 'Spanish',
    'de': 'German',
    'fr': 'French',
    'it': 'Italian',
  };

  @override
  String get engineName => def.name;

  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> ensureModelLoaded(String fromCode, String toCode) async {
    if (!await _isModelDownloaded()) {
      throw StateError('${def.name} modeli indirilmedi.');
    }
    // Asıl yükleme translate() içinde LlmHost tarafından tembel yapılır.
  }

  /// Bağlamda taşınacak en fazla tur + her metnin kırpılma uzunluğu (küçük
  /// modelin context penceresi taşmasın — Qwen ekv1280 / Gemma ekv2048).
  static const int _maxContextTurns = 6;
  static const int _maxTurnChars = 140;

  @override
  Future<String> translate(
    String text,
    String fromCode,
    String toCode, {
    List<TranslationTurn> context = const [],
  }) async {
    final src = _langNames[fromCode] ?? fromCode;
    final tgt = _langNames[toCode] ?? toCode;

    // **Sade few-shot prompt** (Mehmet 2026-06-06: uzun kural bloğu Gemma'yı
    // karıştırıyor, cevaplamaya itiyordu). Aynı yöndeki önceki turlar örnek
    // olarak verilir: hem "$src: … / $tgt: …" formatı "sadece çevir"i öğretir
    // (cevaplama yerine), hem de bağlam/tanıma hatası düzeltmesi (market→marcus)
    // sağlar. Ters yön turları formatı bozmasın diye filtrelenir.
    final shots = context
        .where((t) => t.fromCode == fromCode && t.toCode == toCode)
        .toList();
    final trimmed = shots.length > _maxContextTurns
        ? shots.sublist(shots.length - _maxContextTurns)
        : shots;

    final prompt = StringBuffer()
      ..writeln('Translate from $src to $tgt. Only translate, never answer.');
    for (final t in trimmed) {
      prompt.writeln('$src: ${_clip(t.sourceText)}');
      prompt.writeln('$tgt: ${_clip(t.translatedText)}');
    }
    prompt
      ..writeln('$src: $text')
      ..write('$tgt:');

    final raw =
        await LlmHost.instance.generate(def, prompt.toString(), token: hfToken);
    return _cleanTranslation(raw);
  }

  static String _clip(String s) {
    final t = s.trim();
    return t.length <= _maxTurnChars ? t : '${t.substring(0, _maxTurnChars)}…';
  }

  /// LLM çıktısındaki önsöz/etiket kalıntılarını temizler ("İşte ... çevirisi:",
  /// "Here is the translation:", "Translation:"/"Çeviri:" etiketi, çevreleyen
  /// tırnaklar). Önsözden sonra gerçek çeviri varsa onu korur; yoksa metni
  /// olduğu gibi bırakır (boş döndürme — kullanıcı en azından bir şey görsün).
  static String _cleanTranslation(String out) {
    var s = out.trim();

    // 1) Baştaki "Translation:" / "Çeviri:" / "Çevirisi:" etiketi.
    s = s.replaceFirst(
      RegExp(r'^(translation|çeviri|çevirisi|translated text)\s*:\s*',
          caseSensitive: false),
      '',
    );

    // 2) İlk satır bir önsöz gibi görünüyor (':' ile bitiyor + çeviri/işte/here/
    //    sure kelimeleri) ve ardından gerçek içerik varsa, o satırı at.
    final nl = s.indexOf('\n');
    if (nl > 0) {
      final first = s.substring(0, nl).trim();
      final rest = s.substring(nl + 1).trim();
      final looksPreamble = first.endsWith(':') &&
          RegExp(r'(çevir|i̇?şte|translat|here|sure|elbette|tabii|buyrun)',
                  caseSensitive: false)
              .hasMatch(first);
      if (looksPreamble && rest.isNotEmpty) s = rest;
    }

    return _stripWrappingQuotes(s.trim());
  }

  /// Çevreleyen tırnakları (düz/eğri) soyar.
  static String _stripWrappingQuotes(String s) {
    if (s.length < 2) return s;
    const pairs = {'"': '"', "'": "'", '“': '”', '«': '»', '‘': '’'};
    final close = pairs[s[0]];
    if (close != null && s.endsWith(close)) {
      return s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  @override
  Future<bool> isLanguageReady(String code) => _isModelDownloaded();

  @override
  int estimatedDownloadSizeMb(String code) => def.sizeMb;

  @override
  Future<void> downloadLanguage(String code) =>
      downloadModel(token: hfToken);

  @override
  Future<void> deleteLanguage(String code) async {
    if (def.selfHosted) {
      final f = File(await llmLocalPath(def));
      if (f.existsSync()) await f.delete();
    }
    final id = await _installedId();
    if (id != null) await FlutterGemma.uninstallModel(id);
  }

  @override
  Future<void> dispose() => LlmHost.instance.unloadIfLoaded(def.id);

  // ---------- LLM'e özel (arayüz dışı) ----------

  /// Modeli indirir (ilerlemeli). UI model seçici için. Zaten varsa no-op.
  Future<void> downloadModel({
    String? token,
    void Function(double progress)? onProgress,
  }) async {
    if (await _isModelDownloaded()) {
      onProgress?.call(1.0);
      return;
    }
    if (def.selfHosted) {
      // GH Release'ten bizim güvenilir streamed indiricimizle (Phi-4 native
      // çökme + Xet TLS sorunu yok). Kayıt/yükleme generate()'te fromFile ile.
      await _streamLlmDownload(
        def.url,
        await llmLocalPath(def),
        authToken: def.requiresToken ? token : null,
        onProgress: onProgress,
      );
      return;
    }
    final builder = FlutterGemma.installModel(
            modelType: def.modelType, fileType: def.fileType)
        .fromNetwork(def.url, token: def.requiresToken ? token : null);
    if (onProgress != null) {
      builder.withProgress((p) => onProgress(p / 100.0));
    }
    await builder.install();
  }

  Future<bool> _isModelDownloaded() async {
    if (def.selfHosted) {
      // selfHosted readiness = yerel dosya var + makul boyut (flutter_gemma
      // metadata'sına bağlı değil; tek kaynak yerel dosya).
      final f = File(await llmLocalPath(def));
      return f.existsSync() && (await f.length()) > 1024 * 1024;
    }
    return (await _installedId()) != null;
  }

  /// flutter_gemma'nın "indirili" listesi yalnız SharedPreferences metadata'sına
  /// bakar; cihazdan dosya silinince (yer açmak için) metadata kalır → **yanlış
  /// pozitif** ("Model hazır" görünür, warmup geçer, çeviri/crunch sessizce
  /// patlar). Bu yüzden metadata id'sini bulduktan sonra **diskteki dosyanın
  /// gerçekten var ve makul boyutta** olduğunu doğrularız; değilse stale
  /// metadata'yı temizleyip (install() temiz yeniden indirsin) yok sayarız.
  Future<String?> _installedId() async {
    final installed = await FlutterGemma.listInstalledModels();
    for (final m in installed) {
      if (!m.toLowerCase().contains(def.idMatch)) continue;
      if (await _fileExistsFor(m)) return m;
      // Dosya yok → metadata yalancı. Temizle, indirilmemiş say.
      try {
        await FlutterGemma.uninstallModel(m);
      } catch (_) {
        // uninstall best-effort; zaten yok olabilir.
      }
    }
    return null;
  }

  /// Model dosyası flutter_gemma tarafından app documents dizinine [filename]
  /// adıyla yazılır. Var olduğunu ve > ~1MB (kısmi/bozuk indirme değil)
  /// olduğunu doğrula.
  static Future<bool> _fileExistsFor(String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, filename));
      if (!await file.exists()) return false;
      return await file.length() >= 1024 * 1024; // ≥1MB
    } catch (_) {
      return false;
    }
  }
}
