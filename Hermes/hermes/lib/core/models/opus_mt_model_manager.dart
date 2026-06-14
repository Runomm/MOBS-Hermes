import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Opus-MT (Helsinki/Marian) ONNX dosyalarının indirme/durum/silme yönetimi —
/// **dil-çifti başına** 4 parça (encoder + decoder + decoder_with_past +
/// tokenizer), her çift ~156MB int8. Kaynak: Xenova/opus-mt-* (transformers.js).
///
/// ⚠️ .onnx LFS Xet CDN'de olabilir → dart http patlarsa PC'den `adb push`
/// (harici app dizini `/sdcard/Android/data/<pkg>/files/opus/<pair>/`).
class OpusMtModelManager {
  /// Desteklenen çiftler. `decoderStartId`/`eosId` Marian config'inden (her
  /// çiftin kendi vocab'ı → kendi pad id'si). en-tr Xenova'da int8 yok →
  /// ileride kendi export'um (şimdilik tr-en de-risk).
  static const pairs = <OpusMtPair>[
    OpusMtPair(
      id: 'tr-en',
      label: 'Türkçe → İngilizce',
      repo: 'Xenova/opus-mt-tr-en',
      decoderStartId: 62388,
      eosId: 0,
    ),
  ];

  static OpusMtPair pairById(String id) =>
      pairs.firstWhere((p) => p.id == id);

  static List<OpusMtFile> filesFor(OpusMtPair pair) {
    final base = 'https://huggingface.co/${pair.repo}/resolve/main';
    return [
      OpusMtFile('encoder', 'encoder_model_quantized.onnx',
          '$base/onnx/encoder_model_quantized.onnx', 49),
      OpusMtFile('decoder', 'decoder_model_quantized.onnx',
          '$base/onnx/decoder_model_quantized.onnx', 55),
      OpusMtFile('decoder_past', 'decoder_with_past_model_quantized.onnx',
          '$base/onnx/decoder_with_past_model_quantized.onnx', 52),
      OpusMtFile('tokenizer', 'tokenizer.json', '$base/tokenizer.json', 2),
    ];
  }

  Future<String> dirPath(OpusMtPair pair) async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'opus', pair.id));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> pathFor(OpusMtPair pair, OpusMtFile f) async =>
      p.join(await dirPath(pair), f.fileName);

  Future<bool> isDownloaded(OpusMtPair pair, OpusMtFile f) async {
    final file = File(await pathFor(pair, f));
    if (!await file.exists()) return false;
    final min = f.id == 'tokenizer' ? 64 * 1024 : 5 * 1024 * 1024;
    return (await file.length()) > min;
  }

  Future<bool> allDownloaded(OpusMtPair pair) async {
    for (final f in filesFor(pair)) {
      if (!await isDownloaded(pair, f)) return false;
    }
    return true;
  }

  Future<void> download(OpusMtPair pair, OpusMtFile f,
      {void Function(double progress)? onProgress}) async {
    if (await isDownloaded(pair, f)) {
      onProgress?.call(1.0);
      return;
    }
    final dest = await pathFor(pair, f);
    final partPath = '$dest.part';
    final part = File(partPath);
    final client = http.Client();
    IOSink? sink;
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(f.url)));
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

  Future<void> deleteAll(OpusMtPair pair) async {
    final dir = Directory(await dirPath(pair));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

class OpusMtPair {
  const OpusMtPair({
    required this.id,
    required this.label,
    required this.repo,
    required this.decoderStartId,
    required this.eosId,
  });
  final String id;
  final String label;
  final String repo;
  final int decoderStartId;
  final int eosId;
}

class OpusMtFile {
  const OpusMtFile(this.id, this.fileName, this.url, this.sizeMb);
  final String id;
  final String fileName;
  final String url;
  final int sizeMb;
}
