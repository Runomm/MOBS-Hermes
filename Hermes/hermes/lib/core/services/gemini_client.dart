import 'dart:convert';

import 'package:http/http.dart' as http;

/// Kullanıcının kendi anahtarıyla Google Gemini REST API'sine tek-atış metin
/// üretimi yapan saf istemci (çevrimiçi crunch fallback'i için).
///
/// `CrunchService` LLM'i `run: Future<String> Function(String prompt)` olarak
/// soyutladığından, [generate] doğrudan `run` olarak takılır; chunk/reduce/özet
/// mantığı yerel Gemma3 yolundakiyle aynı kalır.
///
/// `http.Client` enjekte edilebilir (test için `MockClient`). Yerel model
/// gerektirmez → düşük-RAM cihazlar için gerçek fallback.
class GeminiClient {
  GeminiClient(this.apiKey, {this.model = defaultModel, http.Client? client})
      : _client = client ?? http.Client();

  /// Hızlı + ücretsiz katmanda erişilebilir; gerekirse değiştirilebilir.
  static const String defaultModel = 'gemini-2.0-flash';

  final String apiKey;
  final String model;
  final http.Client _client;

  /// [prompt]'u Gemini'ye gönderip üretilen metni döndürür. Hata durumunda
  /// kullanıcı-dostu mesajlı [GeminiException] fırlatır.
  Future<String> generate(String prompt, {int maxTokens = 1024}) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent?key=$apiKey',
    );
    final resp = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'maxOutputTokens': maxTokens,
          'temperature': 0.3,
        },
      }),
    );

    if (resp.statusCode != 200) {
      throw GeminiException.fromResponse(resp.statusCode, resp.bodyBytes);
    }

    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

    // İçerik güvenlik filtresine takıldıysa candidates boş gelebilir.
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      final block =
          (json['promptFeedback'] as Map<String, dynamic>?)?['blockReason'];
      throw GeminiException(
        block != null
            ? 'Gemini içeriği engelledi ($block).'
            : 'Gemini boş yanıt döndürdü.',
      );
    }

    final parts = ((candidates.first as Map<String, dynamic>)['content']
        as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw const GeminiException('Gemini boş yanıt döndürdü.');
    }

    final buffer = StringBuffer();
    for (final p in parts) {
      final text = (p as Map<String, dynamic>)['text'] as String?;
      if (text != null) buffer.write(text);
    }
    return buffer.toString().trim();
  }

  /// Anahtarı kaydetmeden önce hafif bir istekle (model listesi `GET`) doğrular.
  /// Geçersiz/yetkisiz/yanlış-projeli anahtar → kullanıcı-dostu [GeminiException]
  /// (generateContent ile aynı auth katmanı). Mehmet 2026-06-11: geçersiz anahtar
  /// sessizce kabul edilmesin + 401 "expected OAuth2" gibi sorunu kaydetme anında
  /// göster.
  Future<void> validateKey() async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
    );
    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      throw GeminiException.fromResponse(resp.statusCode, resp.bodyBytes);
    }
  }

  /// Tek seferlik istemcide [close] çağrısı; enjekte edilen istemciyi çağıran
  /// yönetir.
  void close() => _client.close();
}

/// Gemini API hatası — `toString()` doğrudan kullanıcıya gösterilebilir mesajdır.
class GeminiException implements Exception {
  const GeminiException(this.message);

  final String message;

  /// HTTP durum koduna göre kullanıcı-dostu mesaj üretir.
  factory GeminiException.fromResponse(int status, List<int> bodyBytes) {
    String? apiMessage;
    try {
      final json = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
      apiMessage = (json['error'] as Map<String, dynamic>?)?['message'] as String?;
    } catch (_) {
      // gövde JSON değilse yok say
    }
    if (status == 400 || status == 403) {
      return GeminiException(
          'Gemini anahtarı geçersiz veya yetkisiz (HTTP $status). '
          'Ayarlar\'dan anahtarını kontrol et.');
    }
    if (status == 429) {
      return const GeminiException(
          'Gemini kotası doldu (HTTP 429). Bir süre sonra tekrar dene.');
    }
    return GeminiException(
        'Gemini isteği başarısız (HTTP $status)${apiMessage != null ? ': $apiMessage' : ''}.');
  }

  @override
  String toString() => message;
}
