import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/repositories/conversation_repository.dart';
import 'package:hermes/features/smalltalk/smalltalk_screen.dart';

/// F2 — hands-free 3 katman motor seçimi (Mehmet 2026-06-08):
/// fast=Vosk+MLKit, full=Whisper+MLKit, full+=Whisper+NLLB.
void main() {
  group('handsFreeUsesWhisper (STT motoru)', () {
    test('fast → Vosk (Whisper değil)', () {
      expect(handsFreeUsesWhisper(SessionQuality.fast), isFalse);
    });
    test('full → Whisper', () {
      expect(handsFreeUsesWhisper(SessionQuality.full), isTrue);
    });
    test('full+ → Whisper', () {
      expect(handsFreeUsesWhisper(SessionQuality.fullPlus), isTrue);
    });
  });

  group('handsFreeUsesNllb (çeviri motoru)', () {
    test('fast → MLKit (NLLB değil)', () {
      expect(handsFreeUsesNllb(SessionQuality.fast), isFalse);
    });
    test('full → MLKit (NLLB değil)', () {
      expect(handsFreeUsesNllb(SessionQuality.full), isFalse);
    });
    test('full+ → NLLB', () {
      expect(handsFreeUsesNllb(SessionQuality.fullPlus), isTrue);
    });
  });
}
