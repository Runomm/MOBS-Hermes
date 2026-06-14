import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import 'vosk_models.dart';

/// Bir dilin Vosk modelinin (örn. `vosk-model-small-tr-0.3`) indirme/durum/
/// silme yönetimi. Whisper bazı dillerde (özellikle Türkçe) zayıf olduğu için
/// Vosk ana STT olarak benimsendi (her dil kendi modeliyle; router Burst 2).
///
/// İndirme ilerlemesi: `ModelLoader.loadFromNetwork` ham `http.get` kullanıp
/// ilerleme yaymıyor. Bu yüzden ModelLoader'a, response stream'ini bayt sayan
/// bir [_ProgressClient] enjekte ediyoruz — extraction mantığını yeniden
/// yazmadan yüzde ilerleme elde ediyoruz. (Çıkartma indirme bitince ayrı
/// isolate'te olur; o aşamada ilerleme belirsizdir.)
class VoskModelManager {
  VoskModelManager(this.info);

  /// Kısayol: dil kodundan yönetici (desteklenmiyorsa hata).
  factory VoskModelManager.forLang(String langCode) {
    final info = VoskModels.forLang(langCode);
    if (info == null) {
      throw ArgumentError('Bu dil için Vosk modeli yok: $langCode');
    }
    return VoskModelManager(info);
  }

  final VoskModelInfo info;
  final ModelLoader _loader = ModelLoader();

  String get modelName => info.modelName;
  int get sizeMb => info.sizeMb;

  /// Model cihazda çıkartılmış (indirilmiş) mi?
  Future<bool> isDownloaded() => _loader.isModelAlreadyLoaded(info.modelName);

  /// Çıkartılmış modelin dizin yolu (indirilmişse).
  Future<String> modelPath() => _loader.modelPath(info.modelName);

  /// Modeli ağdan indirir + çıkartır. [onProgress] 0.0–1.0 indirme yüzdesi
  /// (çıkartma fazında çağrılmaz). Zaten indirilmişse anında döner.
  Future<String> download({void Function(double progress)? onProgress}) async {
    final client = _ProgressClient((received, total) {
      if (onProgress != null && total != null && total > 0) {
        onProgress(received / total);
      }
    });
    final loader = ModelLoader(httpClient: client);
    try {
      return await loader.loadFromNetwork(info.url);
    } finally {
      client.close();
    }
  }

  /// Modeli cihazdan siler (çıkartılmış dizini).
  Future<void> delete() async {
    final dir = Directory(await _loader.modelPath(info.modelName));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

/// İndirme stream'inin baytlarını sayıp ilerleme bildiren http istemcisi.
/// `ModelLoader` içindeki `httpClient.get(...)` → `send(...)` zincirine
/// takılır; `Response.fromStream` baytları okudukça [_onProgress] tetiklenir.
class _ProgressClient extends http.BaseClient {
  _ProgressClient(this._onProgress);

  final http.Client _inner = http.Client();
  final void Function(int received, int? total) _onProgress;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final total = response.contentLength;
    var received = 0;
    final tracked = response.stream.map((chunk) {
      received += chunk.length;
      _onProgress(received, total);
      return chunk;
    });
    return http.StreamedResponse(
      tracked,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
