import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/device_memory.dart';

void main() {
  group('isLowRam', () {
    test('null (bilinmiyor) → false, uyarma', () {
      expect(isLowRam(null), isFalse);
    });

    test('8GB cihaz (~7.4GB rapor) → true, düşük-RAM', () {
      expect(isLowRam(7600), isTrue);
    });

    test('12GB cihaz (~12000MB) → false, yeterli', () {
      expect(isLowRam(12000), isFalse);
    });

    test('tam eşik (11264MB) → false (sınır dahil değil)', () {
      expect(isLowRam(kLowRamThresholdMb), isFalse);
    });

    test('eşiğin 1MB altı → true', () {
      expect(isLowRam(kLowRamThresholdMb - 1), isTrue);
    });
  });
}
