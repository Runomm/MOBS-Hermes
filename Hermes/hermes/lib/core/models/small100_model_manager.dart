import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// SMaLL-100 ONNX dosyalarının indirme/durum/silme yönetimi (fast mod NMT).
/// Üç parça: encoder + decoder (int8) + `tokenizer.json`. ~580MB → streamed,
/// asset bundle EDİLMEZ.
///
/// Kaynak: PEWTER/small100-onnx-int8 (HF). Non-gated. ⚠️ .onnx LFS dosyaları
/// Xet CDN'de olabilir → dart:io http TLS hatası verirse (NLLB'de olduğu gibi)
/// dev tarafında PC `curl` → `adb push` ile `app_support/small100/` altına atılır.
class Small100ModelManager {
  // Dev: optimum ile PC'de export edilip (decoder_with_past, int8) `adb push`
  // ile gelir → URL'ler dev'de kullanılmaz (Xet zaten patlıyor). 4 parça.
  static const _base =
      'https://huggingface.co/PEWTER/small100-onnx-int8/resolve/main';

  static const files = <Small100File>[
    Small100File('encoder', 'encoder.onnx', '$_base/encoder.onnx', 200),
    Small100File('decoder', 'decoder.onnx', '$_base/decoder.onnx', 200),
    Small100File('decoder_past', 'decoder_with_past.onnx',
        '$_base/decoder_with_past.onnx', 200),
    Small100File('tokenizer', 'tokenizer.json', '$_base/tokenizer.json', 4),
  ];

  static Small100File fileById(String id) =>
      files.firstWhere((f) => f.id == id);

  Future<String> dirPath() async {
    // De-risk: Xet CDN .onnx'leri in-app inmiyor → PC'den `adb push` ile gelir.
    // Harici app dizini (/sdcard/Android/data/<pkg>/files/small100) hem app'in
    // izinsiz okuyabildiği hem adb'nin yazabildiği yer. Yoksa internal'a düş.
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'small100'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> pathFor(Small100File f) async =>
      p.join(await dirPath(), f.fileName);

  Future<bool> isDownloaded(Small100File f) async {
    final file = File(await pathFor(f));
    if (!await file.exists()) return false;
    // tokenizer.json küçük (~4MB); .onnx'ler büyük → min eşik dosyaya göre.
    final min = f.id == 'tokenizer' ? 256 * 1024 : 10 * 1024 * 1024;
    return (await file.length()) > min;
  }

  Future<bool> allDownloaded() async {
    for (final f in files) {
      if (!await isDownloaded(f)) return false;
    }
    return true;
  }

  /// Tek dosyayı streamed indirir (`.part` → atomik rename). Zaten varsa no-op.
  Future<void> download(Small100File f,
      {void Function(double progress)? onProgress}) async {
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

  Future<void> deleteAll() async {
    final dir = Directory(await dirPath());
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

class Small100File {
  const Small100File(this.id, this.fileName, this.url, this.sizeMb);
  final String id;
  final String fileName;
  final String url;
  final int sizeMb;
}
