import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/cancel_token.dart';

/// NLLB-200-distilled-600M ONNX dosyalarının durum/silme yönetimi (Tier2).
/// Üç parça: encoder + decoder (past'sız, step0) + decoder_with_past +
/// ham `sentencepiece.bpe.model`. Toplam ~1.3GB.
///
/// **int8 + tokenizer FIX (2026-06-07):** Asıl bug int8 DEĞİLMİŞ — `tokenizer.json`
/// loader'ı NLLB'yi yanlış parçalıyordu (çöp token → cihazda "orta" kalite).
/// PC ölçümü: int8 kalitesi ≈ fp16 ≈ PC; fp16 ise cihazda OOM (3.7GB, Poco 8GB'a
/// sığmaz). → **int8** (Xenova quantized, ~1.3GB, hem S25 hem Poco'ya sığar) +
/// ham SP model ([NllbOnnxTranslator] +1 offset ile doğru tokenize eder).
///
/// **Dağıtım (Faz B, 2026-06-09):** dosyalar **GitHub Release**'te host edilir
/// (`Runomm/MOBS-Hermes`, tag `nllb-600m-int8-v1`); app `download()` ile streamed
/// indirir → dosyalar app kendi yazdığından **app-owned** olur (Android 15 FUSE
/// sorunu yok, run-as gerekmez). GitHub release URL'leri standart HTTPS (Xet
/// CDN değil → dart:io http TLS sorunu yok; 302 redirect otomatik izlenir).
/// De-risk döneminde adb-push kullanılıyordu; o yol hâlâ çalışır (aynı dizin).
class NllbModelManager {
  /// GitHub Release asset taban URL'i. Asset adları = [NllbFile.fileName].
  static const _releaseBase =
      'https://github.com/Runomm/MOBS-Hermes/releases/download/nllb-600m-int8-v1';

  static const files = <NllbFile>[
    NllbFile('encoder', 'encoder_model_quantized.onnx',
        '$_releaseBase/encoder_model_quantized.onnx', 419),
    NllbFile('decoder', 'decoder_model_quantized.onnx',
        '$_releaseBase/decoder_model_quantized.onnx', 470),
    NllbFile('decoder_past', 'decoder_with_past_model_quantized.onnx',
        '$_releaseBase/decoder_with_past_model_quantized.onnx', 445),
    NllbFile('tokenizer', 'sentencepiece.bpe.model',
        '$_releaseBase/sentencepiece.bpe.model', 5),
  ];

  static NllbFile fileById(String id) => files.firstWhere((f) => f.id == id);

  Future<String> _dir() async {
    // De-risk: Xet CDN → in-app inmiyor; PC'den `adb push` ile gelir. Harici
    // app dizini (adb-yazılabilir + izinsiz okunur). Yoksa internal'a düş.
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'nllb'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> pathFor(NllbFile f) async => p.join(await _dir(), f.fileName);

  Future<bool> isDownloaded(NllbFile f) async {
    final file = File(await pathFor(f));
    if (!await file.exists()) return false;
    // Yarım kalan indirmeyi (boyut ~0) tamamlanmış sayma.
    return (await file.length()) > 1024 * 1024;
  }

  Future<bool> allDownloaded() async {
    for (final f in files) {
      if (!await isDownloaded(f)) return false;
    }
    return true;
  }

  /// Tek dosyayı streamed indirir (`.part` → atomik rename). [onProgress]
  /// 0.0–1.0. Zaten indirilmişse anında döner.
  Future<void> download(NllbFile f,
      {void Function(double progress)? onProgress,
      CancelToken? cancelToken}) async {
    if (await isDownloaded(f)) {
      onProgress?.call(1.0);
      return;
    }
    final dest = await pathFor(f);
    final partPath = '$dest.part';
    final part = File(partPath);
    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(f.url));
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode} — ${f.url}');
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

  Future<void> deleteAll() async {
    final dir = Directory(await _dir());
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

class NllbFile {
  const NllbFile(this.id, this.fileName, this.url, this.sizeMb);
  final String id;
  final String fileName;
  final String url;
  final int sizeMb;
}
