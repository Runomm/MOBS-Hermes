import 'dart:typed_data';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// NLLB-200-distilled-600M ONNX seq2seq çevirmen — **Tier2 de-risk (KV-cache)**.
///
/// Mehmet (2026-06-04): NLLB = 3-katman çevirinin orta katman adayı (MLKit'ten
/// iyi, Qwen'den hafif). İlk spike past'sız decode kullandı → çok yavaş (~12sn).
/// Mehmet KV-cache hız optimizasyonu istedi → bu sürüm `decoder_with_past` ile.
///
/// **Mimari (HF Optimum standart export, 3 oturum):**
/// - `encoder_model` — kaynağı 1 kez encode eder (`last_hidden_state`).
/// - `decoder_model` (past'sız) — **yalnız step0**: cross-attention KV'yi
///   encoder'dan üretip cache'i seed eder; çıktısı tüm `present.*` KV.
/// - `decoder_with_past` — **step1+**: her adım TEK token + KV cache; logits
///   sabit `[1,1,vocab]` (büyüyen-logits transferi yok). 12 katman × {decoder,
///   encoder}×{key,value} = 48 KV tensörü. `decoder_with_past` encoder KV'yi
///   re-emit ETMEZ (sabit) → encoder cache girişleri adımlar arası taşınır.
///
/// **Verimlilik:** KV tensörleri Dart'a çekilmez; output `OrtValue`'lar (native
/// handle/id) doğrudan sonraki adımın input'una geçirilir → round-trip yok.
///
/// **Tokenizer (2026-06-07 KRİTİK FIX):** ÖNCE `tokenizer.json` +
/// `HuggingFaceTokenizerLoader` kullanılıyordu — NLLB'nin Unigram/normalizer'ını
/// YANLIŞ uyguluyordu (bol `<unk>`, çöp segmentasyon → cihazda "orta" kalite).
/// Doğrusu: ham **`sentencepiece.bpe.model`** + `SentencePieceTokenizer.fromModelFile`.
/// SP model id'leri HF model-girdisinden **+1 offset'li** (fairseq); dil tokenları
/// SP model'de YOK (HF eklenmiş özel token) → sabit [_langIds] haritası.
/// Parite PC'de doğrulandı: SP+1 == HF birebir.
/// NLLB format: kaynak `[src_lang]+subwords+[eos]`; decoder `start=eos(2)`,
/// `forced_bos=tgt_lang`, sonra greedy üretim → eos.
class NllbOnnxTranslator {
  NllbOnnxTranslator({
    required this.encoderPath,
    required this.decoderPath,
    required this.decoderWithPastPath,
    required this.spModelPath,
    this.lowMemory = false,
  });

  final String encoderPath;
  final String decoderPath;
  final String decoderWithPastPath;
  final String spModelPath;

  /// **iOS bellek modu (2026-06-18).** iOS, `increased-memory-limit` entitlement'ı
  /// olmadan (ücretsiz Apple ID + Sideloadly yolunda yok) uygulama başına bellek
  /// tavanı uygular; 3 ONNX session'ı (~1.34GB) aynı anda yüklemek jetsam SIGKILL
  /// = yakalanamayan native çöküş üretiyordu (preload'da, inference'tan ÖNCE →
  /// kök neden = session yaratımı, int8 inference spike'i değil).
  ///
  /// `lowMemory=true` → session'lar [load]'da değil, her [translate] içinde
  /// **sırayla** yaratılır ve kullanım biter bitmez kapatılır
  /// (encoder→kapat→decoder→kapat→decoder_with_past→kapat). Peak ~1.34GB → ~600MB.
  /// Bir session'ın çıktısı (hidden / KV cache) o session kapatılınca CPU mem
  /// arena ile serbest kaldığından (iOS plugin `useArena`'yı yok sayıyor →
  /// arena daima açık), session sınırını geçen her tensör [_detach] ile bağımsız
  /// kopyaya alınır (hidden ~80KB, cache ~birkaç MB — ucuz).
  ///
  /// **Hız bedeli:** her çeviride 3 session yeniden yüklenir (int8 prepack) →
  /// iOS'te çeviri başına birkaç sn yavaşlama olabilir; önce "çöküyor mu" sorusu,
  /// hız sonra optimize edilir. Android'de `false` → session'lar resident (hızlı,
  /// cihazda kanıtlandı; parite korunur).
  final bool lowMemory;

  static const int maxNewTokens = 96;

  /// NLLB </s>. Decoder start token da budur.
  static const int eosId = 2;

  /// NLLB dil tokenı HF id'leri — SP model'de YOK (HF eklenmiş özel tokenlar).
  static const Map<String, int> _langIds = {
    'tur_Latn': 256184,
    'eng_Latn': 256047,
    'spa_Latn': 256161,
    'deu_Latn': 256042,
    'fra_Latn': 256057,
    'ita_Latn': 256077,
  };

  int _langId(String code) => _langIds[code] ??
      (throw ArgumentError('NLLB bu dili desteklemiyor: $code'));

  SentencePieceTokenizer? _tok;
  OrtSession? _encoder;
  OrtSession? _decoder; // past'sız, step0
  OrtSession? _decoderPast; // decoder_with_past, step1+
  final OnnxRuntime _ort = OnnxRuntime();

  bool get isLoaded =>
      _tok != null &&
      // lowMemory'de session'lar geçici (her translate'te yaratılır) → tokenizer
      // hazırsa "yüklü" say.
      (lowMemory ||
          (_encoder != null && _decoder != null && _decoderPast != null));

  // Debug: gerçek tensor adları (varsayımlar yanlışsa ekranda görünür).
  List<String> get encoderInputNames => _encoder?.inputNames ?? const [];
  List<String> get encoderOutputNames => _encoder?.outputNames ?? const [];
  List<String> get decoderInputNames => _decoder?.inputNames ?? const [];
  List<String> get decoderOutputNames => _decoder?.outputNames ?? const [];

  OrtSessionOptions get _opts => OrtSessionOptions(intraOpNumThreads: 4);

  Future<void> load() async {
    _tok ??= await SentencePieceTokenizer.fromModelFile(spModelPath);
    // lowMemory'de session'lar burada DEĞİL, translate içinde sırayla yaratılır
    // (peak RAM'i ~1.34GB→~600MB indirir, iOS jetsam'i aşmasın).
    if (lowMemory) return;
    _encoder ??= await _ort.createSession(encoderPath, options: _opts);
    _decoder ??= await _ort.createSession(decoderPath, options: _opts);
    _decoderPast ??= await _ort.createSession(decoderWithPastPath, options: _opts);
  }

  /// Bir float32 tensörü (hidden / KV cache) üreten session'dan **bağımsız**
  /// kopyaya alır — `lowMemory`'de session kapatılınca arena ile dangling olmasın.
  /// NLLB'nin hidden state ve KV cache tensörleri float32'dir.
  Future<OrtValue> _detach(OrtValue v) async {
    final flat = (await v.asFlattenedList()).map((e) => (e as num).toDouble());
    return OrtValue.fromList(Float32List.fromList(flat.toList()), v.shape);
  }

  /// `present.X` çıktı adını `past_key_values.X` giriş adına çevirir.
  String _toPastName(String presentName) =>
      presentName.replaceFirst('present', 'past_key_values');

  Future<String> translate(
    String text, {
    required String srcLang,
    required String tgtLang,
  }) async {
    await load();
    final tok = _tok!;
    final srcLangId = _langId(srcLang);
    final tgtLangId = _langId(tgtLang);

    // --- Kaynağı tokenize et: [src_lang] + subwords(+1) + [eos] ---
    // SP model id'leri HF'den +1 offset'li (fairseq); dil tokenı SP'de yok.
    final subwords =
        tok.encode(text, addSpecialTokens: false).ids.map((e) => e + 1);
    final inputIds = <int>[srcLangId, ...subwords, eosId];
    final srcLen = inputIds.length;

    final encAttMask = await OrtValue.fromList(
        Int64List.fromList(List<int>.filled(srcLen, 1)), [1, srcLen]);

    // --- KV cache: past_key_values.* → OrtValue ---
    final cache = <String, OrtValue>{};
    final generated = <int>[];

    // Session'lar: resident (Android) veya geçici (iOS lowMemory). Geçici
    // olanlar kullanımı bitince kapatılır → peak RAM ~1.34GB→~600MB.
    OrtSession? enc, dec, decPast;

    try {
      // --- Encoder (1 kez) ---
      enc = _encoder ?? await _ort.createSession(encoderPath, options: _opts);
      final encInputIds =
          await OrtValue.fromList(Int64List.fromList(inputIds), [1, srcLen]);
      final encOut =
          await enc.run({'input_ids': encInputIds, 'attention_mask': encAttMask});
      await encInputIds.dispose();
      var hidden = encOut['last_hidden_state']!;
      if (lowMemory) {
        // hidden, encoder'ın arena çıktısı → encoder'ı kapatmadan önce bağımsız
        // kopyaya al; sonra ~419MB'lik encoder'ı bırak.
        final detached = await _detach(hidden);
        await hidden.dispose();
        hidden = detached;
        await enc.close();
        enc = null;
      }

      // step0: decoder_model (past'sız) → cache'i seed et, forced tgt_lang.
      dec = _decoder ?? await _ort.createSession(decoderPath, options: _opts);
      final step0In =
          await OrtValue.fromList(Int64List.fromList([eosId]), [1, 1]);
      final dec0 = await dec.run({
        'input_ids': step0In,
        'encoder_attention_mask': encAttMask,
        'encoder_hidden_states': hidden,
      });
      await step0In.dispose();
      await hidden.dispose(); // encoder_hidden_states artık gerekmiyor
      for (final e in dec0.entries) {
        if (e.key == 'logits') {
          await e.value.dispose();
        } else {
          final pastName = _toPastName(e.key); // present.* → past
          if (lowMemory) {
            // decoder'ı kapatacağız → cache girişlerini bağımsız kopyaya al.
            // (encoder.* cross-attn cache loop boyunca taşınır, decoder.* ilk
            //  adımda decoder_with_past çıktısıyla değişecek.)
            cache[pastName] = await _detach(e.value);
            await e.value.dispose();
          } else {
            cache[pastName] = e.value;
          }
        }
      }
      if (lowMemory) {
        await dec.close(); // ~470MB bırak
        dec = null;
      }

      var lastToken = tgtLangId; // forced_bos (pos1)

      // step1+: decoder_with_past, her adım tek token.
      decPast = _decoderPast ??
          await _ort.createSession(decoderWithPastPath, options: _opts);
      for (var step = 0; step < maxNewTokens; step++) {
        final stepIn =
            await OrtValue.fromList(Int64List.fromList([lastToken]), [1, 1]);
        final inputs = <String, OrtValue>{
          'input_ids': stepIn,
          'encoder_attention_mask': encAttMask,
          ...cache,
        };
        final out = await decPast.run(inputs);
        await stepIn.dispose();

        // logits [1,1,vocab] → argmax.
        final logitsVal = out['logits']!;
        final logits = (await logitsVal.asFlattenedList()).cast<num>();
        await logitsVal.dispose();
        final next = _argmax(logits, 0, logits.length);

        // Cache güncelle: yalnız çıktıda gelen present.* (decoder.*) yenilenir;
        // encoder.* gelmez → eski değer korunur (sabit cross-attn KV).
        // decPast loop boyunca açık → çıktıları detach gerektirmez.
        for (final e in out.entries) {
          if (e.key == 'logits') continue;
          final pastName = _toPastName(e.key);
          await cache[pastName]?.dispose();
          cache[pastName] = e.value;
        }

        if (next == eosId) break;
        generated.add(next);
        lastToken = next;
      }
    } finally {
      for (final v in cache.values) {
        await v.dispose();
      }
      await encAttMask.dispose();
      // Geçici session'ları kapat (hata yolunda da sızdırma).
      if (lowMemory) {
        await enc?.close();
        await dec?.close();
        await decPast?.close();
      }
    }

    // Üretilen HF id'leri → SP id (-1) → detokenize.
    final spIds = generated.map((e) => e - 1).toList();
    final raw = tok.decode(spIds, skipSpecialTokens: true);
    return raw.replaceAll('▁', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _argmax(List<num> data, int offset, int len) {
    var bestIdx = 0;
    var bestVal = data[offset];
    for (var i = 1; i < len; i++) {
      final v = data[offset + i];
      if (v > bestVal) {
        bestVal = v;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  Future<void> dispose() async {
    await _encoder?.close();
    await _decoder?.close();
    await _decoderPast?.close();
    _encoder = null;
    _decoder = null;
    _decoderPast = null;
    _tok = null;
  }
}
