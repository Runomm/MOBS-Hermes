import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/utils/llm_text.dart';

void main() {
  group('sanitizeLlmOutput', () {
    test('normal metin değişmeden geçer', () {
      expect(sanitizeLlmOutput('Merhaba dünya.'), 'Merhaba dünya.');
    });

    test('baş/son boşluk kırpılır', () {
      expect(sanitizeLlmOutput('  selam  '), 'selam');
    });

    test('byte-fallback token UTF-8 karaktere çözülür (ç)', () {
      // ç = U+00E7 = UTF-8 0xC3 0xA7
      expect(sanitizeLlmOutput('a<0xC3><0xA7>k'), 'açk');
    });

    test('byte-fallback token UTF-8 karaktere çözülür (ş)', () {
      // ş = U+015F = UTF-8 0xC5 0x9F
      expect(sanitizeLlmOutput('i<0xC5><0x9F>te'), 'işte');
    });

    test('geçersiz/eksik byte token atılır', () {
      // Tek başına 0xC3 geçerli UTF-8 değil → düşürülür.
      expect(sanitizeLlmOutput('ab<0xC3>cd'), 'abcd');
    });

    test('özel pipe token kaldırılır', () {
      expect(sanitizeLlmOutput('Cevap<|im_end|>'), 'Cevap');
    });

    test('açılı şablon token kaldırılır', () {
      expect(sanitizeLlmOutput('Metin<end_of_turn>'), 'Metin');
      expect(sanitizeLlmOutput('<s>İçerik</s>'), 'İçerik');
    });

    test('metaspace boşluğa çevrilir', () {
      expect(sanitizeLlmOutput('▁the▁cat'), 'the cat');
    });

    test('replacement char atılır', () {
      expect(sanitizeLlmOutput('ka�yıt'), 'kayıt');
    });

    test('non-printable kontrol karakteri atılır, \\n ve \\t korunur', () {
      final input = 'a${String.fromCharCode(0)}b'
          '${String.fromCharCode(7)}c'
          '${String.fromCharCode(127)}';
      expect(sanitizeLlmOutput(input), 'abc');
      // newline + tab içeren çok satırlı metin korunur (collapse hariç).
      expect(sanitizeLlmOutput('satır1\nsatır2'), 'satır1\nsatır2');
    });

    test('fazla iç boşluk tek boşluğa iner, satır sonu korunur', () {
      expect(sanitizeLlmOutput('a    b'), 'a b');
      expect(sanitizeLlmOutput('- madde1\n- madde2'), '- madde1\n- madde2');
    });

    test('boş/whitespace girdi boş döner', () {
      expect(sanitizeLlmOutput(''), '');
      expect(sanitizeLlmOutput('   \n  '), '');
    });

    test('karışık artefakt: token + byte + metaspace birlikte', () {
      // "▁Soru:▁ge<0xC3><0xA7>erli<|im_end|>" → "Soru: geçerli"
      final out = sanitizeLlmOutput('▁Soru:▁ge<0xC3><0xA7>erli<|im_end|>');
      expect(out, 'Soru: geçerli');
    });
  });
}
