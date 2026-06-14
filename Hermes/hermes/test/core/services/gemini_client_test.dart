import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hermes/core/services/gemini_client.dart';

void main() {
  group('GeminiClient.generate', () {
    test('doğru URL + body kurar, candidates metnini parse eder', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '  Özet metni  '}
                  ]
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final gemini = GeminiClient('test-key', model: 'gemini-x', client: client);
      final out = await gemini.generate('Merhaba', maxTokens: 555);

      expect(out, 'Özet metni'); // trim edilmiş
      expect(captured.method, 'POST');
      expect(captured.url.toString(), contains('models/gemini-x:generateContent'));
      expect(captured.url.toString(), contains('key=test-key'));
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['contents'][0]['parts'][0]['text'], 'Merhaba');
      expect(body['generationConfig']['maxOutputTokens'], 555);
    });

    test('çok parçalı yanıtı birleştirir', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Bir '},
                      {'text': 'iki'}
                    ]
                  }
                }
              ]
            }),
            200,
          ));
      final out = await GeminiClient('k', client: client).generate('x');
      expect(out, 'Bir iki');
    });

    test('400 API_KEY_INVALID → geçersiz anahtar mesajı', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'error': {'message': 'API key not valid', 'status': 'INVALID_ARGUMENT'}
            }),
            400,
          ));
      final gemini = GeminiClient('bad', client: client);
      expect(
        () => gemini.generate('x'),
        throwsA(isA<GeminiException>()
            .having((e) => e.message, 'message', contains('geçersiz'))),
      );
    });

    test('429 → kota mesajı', () async {
      final client = MockClient((req) async => http.Response('{}', 429));
      expect(
        () => GeminiClient('k', client: client).generate('x'),
        throwsA(isA<GeminiException>()
            .having((e) => e.message, 'message', contains('kota'))),
      );
    });

    test('boş candidates + blockReason → engellendi mesajı', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'candidates': <dynamic>[],
              'promptFeedback': {'blockReason': 'SAFETY'}
            }),
            200,
          ));
      expect(
        () => GeminiClient('k', client: client).generate('x'),
        throwsA(isA<GeminiException>()
            .having((e) => e.message, 'message', contains('engelledi'))),
      );
    });

    test('diğer non-200 → api mesajını taşır', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'error': {'message': 'internal boom'}
            }),
            500,
          ));
      expect(
        () => GeminiClient('k', client: client).generate('x'),
        throwsA(isA<GeminiException>()
            .having((e) => e.message, 'message', contains('boom'))),
      );
    });
  });

  group('GeminiClient.validateKey', () {
    test('200 → sorunsuz döner (GET /models?key=)', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('{"models":[]}', 200);
      });
      await GeminiClient('test-key', client: client).validateKey();
      expect(captured.method, 'GET');
      expect(captured.url.toString(), contains('/v1beta/models'));
      expect(captured.url.toString(), contains('key=test-key'));
    });

    test('400/403 → geçersiz anahtar mesajı', () async {
      final client = MockClient((req) async => http.Response('{}', 400));
      expect(
        () => GeminiClient('bad', client: client).validateKey(),
        throwsA(isA<GeminiException>()
            .having((e) => e.message, 'message', contains('geçersiz'))),
      );
    });

    test('401 (expected OAuth2 senaryosu) → kullanıcı-dostu hata', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'error': {'message': 'Expected OAuth 2 access token'}
            }),
            401,
          ));
      expect(
        () => GeminiClient('aiza-degil', client: client).validateKey(),
        throwsA(isA<GeminiException>()
            .having((e) => e.message, 'message', contains('OAuth'))),
      );
    });
  });
}
