/// Konuşma transkriptlerinden filler kelime/seslerini temizleyen saf Dart sınıfı.
///
/// Faz 1'in offline-first, LLM'siz çözümü. Faz 2'de opsiyonel olarak Gemini
/// Flash ile online cilalama eklenecek (bu sınıfa dokunmadan, ayrı bir motor).
///
/// Kullanım:
/// ```dart
/// final cleaner = FillerCleaner();
/// final result = cleaner.clean(
///   'Eee, yani bugün şey, sinema mı gideceğiz hani?',
///   language: 'tr',
///   level: FillerLevel.aggressive,
/// );
/// // → 'Bugün, sinema mı gideceğiz?'
/// ```
class FillerCleaner {
  const FillerCleaner();

  /// Metni belirtilen dilde ve agresiflik seviyesinde temizler.
  ///
  /// [language]: BCP-47 dil kodu ('tr', 'en'). Bilinmeyen dil için sadece
  /// jenerik sesler ve whitespace normalize edilir.
  /// [level]: Temizlik seviyesi (default conservative).
  String clean(
    String text, {
    required String language,
    FillerLevel level = FillerLevel.conservative,
  }) {
    if (level == FillerLevel.off) {
      return _normalizeWhitespace(text);
    }

    final patterns = _patternsFor(language, level);

    var result = text;
    for (final pattern in patterns) {
      result = result.replaceAll(pattern, ' ');
    }

    result = _normalizeWhitespace(result);
    result = _capitalizeSentences(result);
    return result;
  }

  /// Whitespace ve cümle sonu noktalama normalizasyonu.
  /// - Çoklu boşluklar tek boşluğa
  /// - Noktalama öncesi boşluk silinir (örn. " ," → ",")
  /// - String trim'lenir
  String _normalizeWhitespace(String text) {
    var t = text.replaceAll(RegExp(r'\s+'), ' ');
    // replaceAllMapped: Dart'ta replaceAll backreference desteklemez,
    // o yüzden eşleşen punctuation'ı manuel geri yazıyoruz.
    t = t.replaceAllMapped(
      RegExp(r'\s+([,\.!\?;:])'),
      (m) => m.group(1)!,
    );
    return t.trim();
  }

  /// Cümle başlarındaki ilk harfi büyük yapar.
  /// "merhaba. nasılsın?" → "Merhaba. Nasılsın?"
  String _capitalizeSentences(String text) {
    if (text.isEmpty) return text;

    final buffer = StringBuffer();
    var capitalizeNext = true;
    for (final char in text.split('')) {
      if (capitalizeNext && _isLetter(char)) {
        buffer.write(char.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
        if (char == '.' || char == '!' || char == '?') {
          capitalizeNext = true;
        }
      }
    }
    return buffer.toString();
  }

  bool _isLetter(String char) {
    if (char.isEmpty) return false;
    return RegExp(r'\p{L}', unicode: true).hasMatch(char);
  }

  List<RegExp> _patternsFor(String language, FillerLevel level) {
    final lang = language.toLowerCase();
    final patterns = <RegExp>[];

    // Genel (dil bağımsız) dolgu sesleri — her zaman temizlenir
    patterns.addAll(_genericFillers);

    if (lang == 'tr') {
      patterns.addAll(_trConservative);
      if (level == FillerLevel.aggressive) {
        patterns.addAll(_trAggressive);
      }
    } else if (lang == 'en') {
      patterns.addAll(_enConservative);
      if (level == FillerLevel.aggressive) {
        patterns.addAll(_enAggressive);
      }
    }

    return patterns;
  }

  // ---------- Pattern üretimi ----------
  //
  // Önemli notlar:
  // - `\b` (word boundary) Dart RegExp'inde Unicode-aware DEĞİL. Çözüm:
  //   `(?<![\p{L}])word(?![\p{L}])` Unicode lookaround.
  // - `caseSensitive: false` Dart'ta Türkçe `İ` ↔ `i` eşlemesini YAPMAZ
  //   (standart Unicode case folding farklı kurallar uygular). Bu yüzden
  //   Türkçe pattern'lerde ilk harf için **açık character class** yazılır:
  //   `[İi]şte`, `[Şş]ey` gibi.
  // - Filler kelime + sonraki virgül + boşluk birlikte yutulur; "şey,"
  //   ortada virgül bırakmaz.

  /// ASCII karakterli + case-insensitive pattern (jenerik sesler ve İngilizce
  /// söz kalıpları için).
  static RegExp _ascii(String word) {
    return RegExp(
      '(?<![\\p{L}])(?:$word)(?![\\p{L}])\\s*,?\\s*',
      unicode: true,
      caseSensitive: false,
    );
  }

  /// Türkçe pattern (caller, "[İi]şte" gibi açık character class yazmalı).
  static RegExp _tr(String pattern) {
    return RegExp(
      '(?<![\\p{L}])(?:$pattern)(?![\\p{L}])\\s*,?\\s*',
      unicode: true,
    );
  }

  /// Cümle başı "Like ..." kalıbı (İngilizce, case-insensitive).
  static RegExp _sentenceInitial(String word) {
    return RegExp(
      '(?:^|(?<=[\\.!\\?]\\s))$word\\s+',
      unicode: true,
      caseSensitive: false,
      multiLine: true,
    );
  }

  static final List<RegExp> _genericFillers = [
    _ascii('m+m+'),
    _ascii('a+a+'),
  ];

  static final List<RegExp> _trConservative = [
    _tr('[Ee]e+'),
    _tr('[Uu]hh+'),
  ];

  static final List<RegExp> _trAggressive = [
    _tr('[Yy]ani'),
    _tr('[İi]şte'),
    _tr('[Hh]ani'),
    _tr('[Ff]alan'),
    _tr('[Şş]ey'),
  ];

  static final List<RegExp> _enConservative = [
    _ascii('um+'),
    _ascii('uh+'),
  ];

  static final List<RegExp> _enAggressive = [
    _ascii('you know'),
    _ascii('i mean'),
    _sentenceInitial('like'),
    _ascii('kinda'),
    _ascii('sorta'),
  ];
}

/// Filler temizleme agresiflik seviyesi.
enum FillerLevel {
  /// Hiç temizleme yapma (sadece whitespace normalizasyonu).
  /// Kullanıcı "ham transkripti göster" toggle'ı için.
  off,

  /// Default. Sadece bariz dolgu sesleri: "ee", "uhh", "umm", "mmm".
  conservative,

  /// Söz kalıpları dahil: "yani", "işte", "hani", "şey", "you know", vb.
  /// Bazen meşru kullanımı da yiyebilir; opt-in.
  aggressive,
}
