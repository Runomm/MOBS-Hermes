import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/engines/translation/google_mlkit_engine.dart';

void main() {
  group('runMlKitDownloadWithTimeout', () {
    test('asla çözülmeyen indirme → MlKitDownloadException (timeout)', () async {
      // GMS indirmeyi tamamlamayınca downloadModel Future'ı asla çözülmüyor.
      await expectLater(
        () => runMlKitDownloadWithTimeout(
          () => Completer<void>().future, // hiç çözülmez
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<MlKitDownloadException>()),
      );
    });

    test('timeout hata mesajı kullanıcıyı NLLB\'ye yönlendirir', () async {
      try {
        await runMlKitDownloadWithTimeout(
          () => Completer<void>().future,
          timeout: const Duration(milliseconds: 20),
        );
        fail('MlKitDownloadException bekleniyordu');
      } on MlKitDownloadException catch (e) {
        expect(e.toString(), contains('NLLB'));
      }
    });

    test('başarılı indirme → sorunsuz tamamlanır', () async {
      var ran = false;
      await runMlKitDownloadWithTimeout(
        () async => ran = true,
        timeout: const Duration(seconds: 1),
      );
      expect(ran, isTrue);
    });

    test('timeout-dışı hata olduğu gibi propagate olur', () async {
      await expectLater(
        () => runMlKitDownloadWithTimeout(
          () async => throw StateError('ağ hatası'),
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
