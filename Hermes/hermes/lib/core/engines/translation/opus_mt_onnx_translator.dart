import 'dart:io';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Opus-MT (Helsinki-NLP, MarianMT) ONNX seq2seq çevirmen — **dil-çifti başına**
/// küçük adanmış NMT (Mehmet 2026-06-06: SMaLL-100/NLLB-600M yetersiz, NLLB-1.3B
/// OOM → Opus-MT dene; çift-özel ~156MB int8, hızlı, OOM yok).
///
/// **Marian protokolü (NLLB/M2M'den FARKLI — config ile doğrulandı):**
/// - **Dil tokenı YOK** (model zaten tr→en gibi tek çifte özel).
/// - Encoder: `src_subwords + [</s>=eos]`.
/// - Decoder `decoder_start_token_id` (= pad, örn tr-en'de 62388) ile başlar,
///   forced_bos YOK, serbest greedy → `</s>` (eos, Marian'da genelde 0).
/// - `eosId`/`decoderStartId` **model başına** değişir (her çiftin kendi vocab'ı)
///   → constructor'dan verilir.
///
/// **Export:** Xenova/opus-mt-* (transformers.js, int8) — encoder + decoder +
/// decoder_with_past + tokenizer.json (NLLB ile aynı yapı, KV-cache). NLLB'nin
/// kanıtlanmış KV-cache akışı kullanılır.
class OpusMtOnnxTranslator {
  OpusMtOnnxTranslator({
    required this.encoderPath,
    required this.decoderPath,
    required this.decoderWithPastPath,
    required this.tokenizerJsonPath,
    required this.decoderStartId,
    required this.eosId,
  });

  final String encoderPath;
  final String decoderPath;
  final String decoderWithPastPath;
  final String tokenizerJsonPath;

  /// Marian decoder_start_token_id (= pad). Model başına değişir.
  final int decoderStartId;

  /// Marian eos_token_id (genelde 0). Model başına değişir.
  final int eosId;

  static const int maxNewTokens = 128;

  SentencePieceTokenizer? _tok;
  OrtSession? _encoder;
  OrtSession? _decoder;
  OrtSession? _decoderPast;
  final OnnxRuntime _ort = OnnxRuntime();

  bool get isLoaded =>
      _tok != null &&
      _encoder != null &&
      _decoder != null &&
      _decoderPast != null;

  List<String> get encoderInputNames => _encoder?.inputNames ?? const [];
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

  String _toPastName(String presentName) =>
      presentName.replaceFirst('present', 'past_key_values');

  /// [srcLang]/[tgtLang] Marian'da KULLANILMAZ (model çift-özel) — arayüz
  /// uyumu için kabul edilir.
  Future<String> translate(String text,
      {String? srcLang, String? tgtLang}) async {
    await load();
    final tok = _tok!;
    debugPrint('🔵 OpusMT start: text="${text.length} chars"');

    // Encoder: subwords + [eos] (dil tokenı yok).
    final subwords = tok.encode(text, addSpecialTokens: false).ids;
    final inputIds = <int>[...subwords, eosId];
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
      // step0: decoder_model (past'sız) input=[decoder_start] → logits + cache.
      final step0In =
          await OrtValue.fromList(Int64List.fromList([decoderStartId]), [1, 1]);
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
          cache[_toPastName(e.key)] = e.value;
        }
      }

      var lastToken = _argmaxExcluding(logits0!, 0, logits0.length, const {});
      if (lastToken != eosId) generated.add(lastToken);

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
        for (final e in out.entries) {
          if (e.key == 'logits') {
            await e.value.dispose();
            continue;
          }
          final pastName = _toPastName(e.key);
          await cache[pastName]?.dispose();
          cache[pastName] = e.value;
        }

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
    debugPrint('🟢 OpusMT done: ${generated.length} token → "$result"');
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
