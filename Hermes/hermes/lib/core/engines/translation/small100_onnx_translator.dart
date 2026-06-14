import 'dart:io';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// SMaLL-100 ONNX seq2seq çevirmen — **fast mod adanmış NMT** (Mehmet 2026-06-06:
/// LLM çeviri yetersiz → ONNX; fast=SMaLL-100, full=NLLB).
///
/// SMaLL-100 = M2M-100 mimarisi, 330M, 100 dil. Adanmış çevirmen (akıl yürütmez,
/// context yok) ama bu boyutta saf çeviri kalitesi LLM'lerden iyi (M2M-12B ile
/// yarışır). **KV-cache (decoder_with_past) ile** — KV-cache'siz greedy uzun
/// cümlede dejenere oluyordu + kareli yavaşlık; NLLB'nin kanıtlanmış KV-cache
/// akışı kullanılır.
///
/// **SMaLL-100 protokolü (M2M-100'den FARKLI — config ile doğrulandı):**
/// - Hedef dil token'ı **kaynağa** eklenir: `[__tgt__] + src_subwords + [</s>=2]`.
/// - Decoder `decoder_start_token_id = 2` (</s>) ile başlar, **forced_bos YOK** →
///   ilk gerçek token step0 logits'inden seçilir (NLLB forced_bos kullanır, biz değil).
///
/// **Export (PC, optimum `text2text-generation-with-past`, int8 quantized):**
/// `encoder_model` + `decoder_model` (step0, past'sız) + `decoder_with_past_model`
/// (step1+) + `tokenizer.json`. Dil tokenı `__<code>__` (`__tr__`=128093).
class Small100OnnxTranslator {
  Small100OnnxTranslator({
    required this.encoderPath,
    required this.decoderPath,
    required this.decoderWithPastPath,
    required this.tokenizerJsonPath,
  });

  final String encoderPath;
  final String decoderPath;
  final String decoderWithPastPath;
  final String tokenizerJsonPath;

  static const int maxNewTokens = 128;
  static const int _decoderStart = 2; // </s>

  SentencePieceTokenizer? _tok;
  OrtSession? _encoder;
  OrtSession? _decoder; // past'sız, step0
  OrtSession? _decoderPast; // decoder_with_past, step1+
  final OnnxRuntime _ort = OnnxRuntime();

  bool get isLoaded =>
      _tok != null &&
      _encoder != null &&
      _decoder != null &&
      _decoderPast != null;

  // Debug (de-risk): gerçek tensor adları varsayımları doğrular.
  List<String> get encoderInputNames => _encoder?.inputNames ?? const [];
  List<String> get encoderOutputNames => _encoder?.outputNames ?? const [];
  List<String> get decoderInputNames => _decoder?.inputNames ?? const [];
  List<String> get decoderOutputNames => _decoder?.outputNames ?? const [];

  Future<void> load() async {
    _tok ??= HuggingFaceTokenizerLoader.fromJsonString(
      await File(tokenizerJsonPath).readAsString(),
    );
    final opts = OrtSessionOptions(intraOpNumThreads: 4);
    _encoder ??= await _ort.createSession(encoderPath, options: opts);
    _decoder ??= await _ort.createSession(decoderPath, options: opts);
    _decoderPast ??=
        await _ort.createSession(decoderWithPastPath, options: opts);
  }

  /// BCP-47 kodunu (`tr`) SMaLL-100 dil token'ına (`__tr__`) çevirir.
  static String langToken(String code) => '__${code}__';

  String _toPastName(String presentName) =>
      presentName.replaceFirst('present', 'past_key_values');

  Future<String> translate(
    String text, {
    required String srcLang,
    required String tgtLang,
  }) async {
    await load();
    final tok = _tok!;
    final eosId = tok.vocab.eosId;
    final tgtLangId = tok.convertTokensToIds([langToken(tgtLang)]).first;
    debugPrint('🔵 S100 start: $srcLang→$tgtLang tgtId=$tgtLangId');

    // --- Kaynak: [__tgt__] + subwords + [</s>] (SMaLL-100 hedefi kaynağa koyar)
    final subwords = tok.encode(text, addSpecialTokens: false).ids;
    final inputIds = <int>[tgtLangId, ...subwords, eosId];
    final srcLen = inputIds.length;

    final encInputIds =
        await OrtValue.fromList(Int64List.fromList(inputIds), [1, srcLen]);
    final encAttMask = await OrtValue.fromList(
        Int64List.fromList(List<int>.filled(srcLen, 1)), [1, srcLen]);

    final encOut = await _encoder!
        .run({'input_ids': encInputIds, 'attention_mask': encAttMask});
    final hidden = encOut['last_hidden_state']!;
    await encInputIds.dispose();

    final cache = <String, OrtValue>{};
    final generated = <int>[];

    try {
      // step0: decoder_model (past'sız) — cache seed + ilk logits.
      final step0In =
          await OrtValue.fromList(Int64List.fromList([_decoderStart]), [1, 1]);
      final dec0 = await _decoder!.run({
        'input_ids': step0In,
        'encoder_attention_mask': encAttMask,
        'encoder_hidden_states': hidden,
      });
      await step0In.dispose();
      await hidden.dispose();

      List<num>? logits0;
      for (final e in dec0.entries) {
        if (e.key == 'logits') {
          logits0 = (await e.value.asFlattenedList()).cast<num>();
          await e.value.dispose();
        } else {
          cache[_toPastName(e.key)] = e.value; // present.* → past
        }
      }

      // SMaLL-100: forced_bos YOK → ilk token step0 logits'inden.
      var lastToken = _argmaxExcluding(logits0!, 0, logits0.length, const {});
      if (lastToken != eosId) generated.add(lastToken);

      // step1+: decoder_with_past, tek token.
      while (lastToken != eosId && generated.length < maxNewTokens) {
        final stepIn =
            await OrtValue.fromList(Int64List.fromList([lastToken]), [1, 1]);
        final out = await _decoderPast!.run({
          'input_ids': stepIn,
          'encoder_attention_mask': encAttMask,
          ...cache,
        });
        await stepIn.dispose();

        final logitsVal = out['logits']!;
        final flat = (await logitsVal.asFlattenedList()).cast<num>();

        // Cache güncelle (yalnız present.* = decoder.* gelir; encoder.* sabit).
        for (final e in out.entries) {
          if (e.key == 'logits') {
            await e.value.dispose();
            continue;
          }
          final pastName = _toPastName(e.key);
          await cache[pastName]?.dispose();
          cache[pastName] = e.value;
        }

        // no_repeat_ngram=3 safety (greedy dejenerasyonuna karşı).
        final banned = _bannedNgram(generated, 3);
        final next = _argmaxExcluding(flat, 0, flat.length, banned);
        if (next == eosId) break;
        generated.add(next);
        lastToken = next;
      }
    } finally {
      for (final v in cache.values) {
        await v.dispose();
      }
      await encAttMask.dispose();
    }

    final raw = tok.decode(generated, skipSpecialTokens: true);
    final result =
        raw.replaceAll('▁', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    debugPrint('🟢 S100 done: ${generated.length} token → "$result"');
    return result;
  }

  int _argmaxExcluding(List<num> data, int offset, int len, Set<int> banned) {
    var bestIdx = -1;
    num bestVal = double.negativeInfinity;
    for (var i = 0; i < len; i++) {
      if (banned.contains(i)) continue;
      final v = data[offset + i];
      if (v > bestVal) {
        bestVal = v;
        bestIdx = i;
      }
    }
    return bestIdx < 0 ? 0 : bestIdx;
  }

  Set<int> _bannedNgram(List<int> gen, int n) {
    final banned = <int>{};
    if (gen.length < n - 1) return banned;
    final prefix = gen.sublist(gen.length - (n - 1));
    for (var i = 0; i + n <= gen.length; i++) {
      var match = true;
      for (var j = 0; j < n - 1; j++) {
        if (gen[i + j] != prefix[j]) {
          match = false;
          break;
        }
      }
      if (match) banned.add(gen[i + n - 1]);
    }
    return banned;
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
