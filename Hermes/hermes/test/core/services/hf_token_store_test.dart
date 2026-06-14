import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/hf_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NS-3 — HF token kalıcılığı. save() her zaman cache'i günceller, bu yüzden
/// singleton cache'ine rağmen save→read roundtrip güvenilir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('temizlenince null döner', () async {
    await HfTokenStore.instance.clear();
    expect(await HfTokenStore.instance.read(), isNull);
  });

  test('kaydet → oku roundtrip (whitespace trim edilir)', () async {
    await HfTokenStore.instance.save('  hf_abc123  ');
    expect(await HfTokenStore.instance.read(), 'hf_abc123');
  });

  test('boş/whitespace kaydetmek kaydı siler', () async {
    await HfTokenStore.instance.save('hf_x');
    await HfTokenStore.instance.save('   ');
    expect(await HfTokenStore.instance.read(), isNull);
  });
}
