import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes/core/services/gemini_key_store.dart';

void main() {
  // Singleton cache'i testler arası sızdırmasın diye her testte mock + temizle.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GeminiKeyStore.instance.clear();
  });

  test('başlangıçta null', () async {
    SharedPreferences.setMockInitialValues({});
    await GeminiKeyStore.instance.clear();
    expect(await GeminiKeyStore.instance.read(), isNull);
  });

  test('save → read roundtrip (trim edilir)', () async {
    await GeminiKeyStore.instance.save('  AIza-secret  ');
    expect(await GeminiKeyStore.instance.read(), 'AIza-secret');
  });

  test('boş save siler', () async {
    await GeminiKeyStore.instance.save('AIza-x');
    await GeminiKeyStore.instance.save('   ');
    expect(await GeminiKeyStore.instance.read(), isNull);
  });

  test('clear siler', () async {
    await GeminiKeyStore.instance.save('AIza-x');
    await GeminiKeyStore.instance.clear();
    expect(await GeminiKeyStore.instance.read(), isNull);
  });
}
