import 'dart:convert';

/// On-device LLM (Qwen/Gemma) **ham çıktısını temizler** — cihazda gözlemlenen
/// "değişik karakterler" sorununun çözümü (2026-06-05, Konferans crunch; Mehmet
/// birebir: "qwen özetinde ve çevirisinde değişik karakterler beliriyor").
///
/// Tipik on-device LLM artefaktları:
///   - **SentencePiece byte-fallback token'ları** (`<0xC3><0xA7>` = `ç`): tokenizer
///     UTF-8 dışı baytı ayrı token olarak yaydığında metne sızar. Ardışık olanlar
///     toplanıp `utf8.decode` ile gerçek karaktere çevrilir (Türkçe ç/ş/ğ kurtarılır);
///     geçersiz/eksik dizi atılır.
///   - **Özel/şablon token'ları** (`<|im_end|>`, `<end_of_turn>`, `<eos>` vb.):
///     sohbet şablonu sınırlayıcıları çıktıya kaçtığında.
///   - **Metaspace işareti** (`▁`, U+2581): SentencePiece'in boşluk göstergesi —
///     boşluğa çevrilir.
///   - **Replacement char** (`�`, U+FFFD) + non-printable kontrol karakterleri.
///
/// Tek yerde ([LlmHost.generate]) uygulanır → hem canlı çeviri hem crunch özeti
/// temizlenir.
String sanitizeLlmOutput(String raw) {
  var s = raw;

  // 1) Byte-fallback token'ları (<0xNN>) → gerçek UTF-8 karakter.
  s = _decodeByteTokens(s);

  // 2) Özel/şablon token'ları kaldır.
  s = s.replaceAll(RegExp(r'<\|[^>]*\|>'), '');
  s = s.replaceAll(
    RegExp(
      r'</?(?:s|bos|eos|pad|unk|sep|cls|mask|start_of_turn|end_of_turn|'
      r'endoftext|im_start|im_end)>',
      caseSensitive: false,
    ),
    '',
  );

  // 3) Metaspace → boşluk; replacement char → at.
  s = s.replaceAll('▁', ' ').replaceAll('�', '');

  // 4) Non-printable kontrol karakterleri at (tab=9 ve newline=10 korunur).
  //    Kaynağa ham kontrol baytı gömmemek için kod noktasıyla süzülür.
  s = String.fromCharCodes(s.runes.where(_isPrintable));

  // 5) Satır-içi fazla boşlukları (özellikle metaspace çevriminden) sadeleştir;
  //    satır sonlarını (bullet/özet yapısı) koru.
  s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');

  return s.trim();
}

/// Yazdırılabilir mi? C0 kontrol (0x00–0x1F, tab/newline hariç) ve DEL (0x7F) at.
bool _isPrintable(int codeUnit) {
  if (codeUnit == 9 || codeUnit == 10) return true; // \t, \n
  if (codeUnit < 0x20) return false; // diğer C0 kontrol
  if (codeUnit == 0x7F) return false; // DEL
  return true;
}

/// Ardışık `<0xNN>` byte token'larını toplayıp UTF-8 olarak çözer.
/// Geçersiz dizi (eksik/bozuk bayt) → boş (atılır). `replaceAll` backreference
/// desteklemediği için `replaceAllMapped` kullanılır (env cheatsheet).
String _decodeByteTokens(String input) {
  final group = RegExp(r'(?:<0x[0-9A-Fa-f]{2}>)+');
  final single = RegExp(r'<0x([0-9A-Fa-f]{2})>');
  return input.replaceAllMapped(group, (m) {
    final bytes = <int>[
      for (final b in single.allMatches(m.group(0)!))
        int.parse(b.group(1)!, radix: 16),
    ];
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '';
    }
  });
}
