import 'language_detector.dart';

/// **Saf Dart** sezgisel dil tespiti — ML Kit'siz (offline, hiçbir native/pod
/// bağımlılığı yok). 2026-06-19 iOS kurtarma: [MlKitLanguageDetector] iOS'te
/// bozuk (ML Kit'in tamamı static-linkage resource bundle yüzünden çalışmıyor)
/// → hands-free transkriptleri `detect`=null yüzünden sessizce düşürülüyordu
/// ([WhisperLangIdTranscriber]). whisper_ggml yanıtı da algılanan dili
/// döndürmüyor → bu sezgisel detector boşluğu doldurur.
///
/// **Neden 2-aday yeterli:** Hands-free konuşma yalnız **iki bilinen dil**
/// (master + local) arasında karar verir → genel 100-dilli langid'e gerek yok.
/// Metni yalnız [candidates] dilleri için dil-özel imlerle (karaktere + sık
/// fonksiyon kelimelerine) skorlar, yüksek olanı döner. Hiç im yoksa null
/// (belirsiz → çağıran drop eder; ML Kit davranışıyla aynı).
///
/// Doğruluk ML Kit'ten düşük ama hands-free'i **çalışır** kılar (aksi halde hiç
/// çıktı yok). Faz-1 dilleri: tr/en/es/de/fr/it (NLLB ile aynı küme).
class HeuristicLanguageDetector implements LanguageDetector {
  /// Aralarında karar verilecek diller (BCP-47). Tipik: [masterLang, localLang].
  HeuristicLanguageDetector({required List<String> candidates})
      : _candidates = candidates
            .map((c) => c.toLowerCase())
            .where(_markers.containsKey)
            .toList();

  final List<String> _candidates;

  @override
  String get engineName => 'Sezgisel (offline, 2-aday)';

  @override
  bool get isOfflineCapable => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<LanguageDetectionResult?> detect(
    String text, {
    double minConfidence = 0.6,
  }) async {
    final result = score(text, _candidates);
    if (result == null) return null;
    if (result.confidence < minConfidence) return null;
    return result;
  }

  @override
  Future<void> dispose() async {}

  /// Saf/senkron skorlama (test edilebilir). [candidates] içindeki her dili
  /// imlerle puanlar; en yüksek puanlı dili döner. Tüm puanlar 0 ise null.
  /// Beraberlikte ilk aday kazanır (deterministik).
  static LanguageDetectionResult? score(String text, List<String> candidates) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty || candidates.isEmpty) return null;

    // Kelimeler: harf-dışı her şeyde böl (Türkçe/aksanlı harfler korunur).
    final words = t.split(_nonLetter).where((w) => w.isNotEmpty).toSet();

    var bestLang = '';
    var bestScore = 0;
    var total = 0;
    for (final lang in candidates) {
      final m = _markers[lang];
      if (m == null) continue;
      var s = 0;
      // Dil-özel karakterler (güçlü sinyal, ×2).
      for (final ch in m.chars) {
        if (t.contains(ch)) s += 2;
      }
      // Sık fonksiyon kelimeleri (tam kelime eşleşmesi).
      for (final w in m.words) {
        if (words.contains(w)) s += 1;
      }
      total += s;
      if (s > bestScore) {
        bestScore = s;
        bestLang = lang;
      }
    }

    if (bestScore == 0 || bestLang.isEmpty) return null;
    // Güven: kazananın toplam içindeki payı (0.5..1). Tek sinyal bile olsa ≥0.5.
    final conf = total == 0 ? 0.5 : (bestScore / total).clamp(0.5, 1.0);
    return LanguageDetectionResult(
      languageCode: bestLang,
      confidence: conf.toDouble(),
    );
  }
}

/// Harf-dışı sınır (kelime ayırıcı). Türkçe/aksanlı harfleri bölmemek için
/// Unicode harf-olmayan: `\P{L}` Dart RegExp'te unicode flag ile.
final RegExp _nonLetter = RegExp(r'[^\p{L}]+', unicode: true);

/// Bir dilin sezgisel imleri: dil-özel karakterler + sık fonksiyon kelimeleri.
class _LangMarkers {
  const _LangMarkers({required this.chars, required this.words});
  final List<String> chars;
  final Set<String> words;
}

/// Faz-1 dilleri (tr/en/es/de/fr/it) için imler. Kelimeler en sık geçen
/// fonksiyon/selamlama kelimeleri — kısa sözcelerde bile yakalanır.
const Map<String, _LangMarkers> _markers = {
  'tr': _LangMarkers(
    chars: ['ç', 'ğ', 'ı', 'ş'],
    words: {
      've', 'bir', 'bu', 'için', 'çok', 'ben', 'sen', 'var', 'yok', 'değil',
      'evet', 'hayır', 'merhaba', 'teşekkür', 'teşekkürler', 'nasıl', 'ne',
      'ama', 'ile', 'da', 'de', 'mı', 'mi', 'şey', 'günaydın'
    },
  ),
  'en': _LangMarkers(
    chars: [],
    words: {
      'the', 'and', 'is', 'are', 'you', 'to', 'of', 'in', 'it', 'that', 'this',
      'have', 'with', 'for', 'what', 'how', 'hello', 'hi', 'thanks', 'thank',
      'yes', 'no', 'please', 'good', 'my', 'we', 'do', 'not'
    },
  ),
  'es': _LangMarkers(
    chars: ['ñ', '¿', '¡'],
    words: {
      'el', 'la', 'los', 'las', 'de', 'que', 'y', 'en', 'un', 'una', 'es',
      'por', 'con', 'para', 'hola', 'gracias', 'sí', 'no', 'cómo', 'qué',
      'buenos', 'días', 'muy', 'está'
    },
  ),
  'de': _LangMarkers(
    chars: ['ä', 'ö', 'ü', 'ß'],
    words: {
      'der', 'die', 'das', 'und', 'ist', 'ich', 'nicht', 'ein', 'eine', 'zu',
      'mit', 'hallo', 'danke', 'ja', 'nein', 'wie', 'was', 'wir', 'sie', 'gut',
      'bitte', 'guten'
    },
  ),
  'fr': _LangMarkers(
    chars: ['à', 'é', 'è', 'ê', 'ç', 'û'],
    words: {
      'le', 'la', 'les', 'de', 'et', 'est', 'un', 'une', 'je', 'vous', 'pour',
      'avec', 'bonjour', 'merci', 'oui', 'non', 'comment', 'que', 'qui', 'ce',
      'pas', 'salut'
    },
  ),
  'it': _LangMarkers(
    chars: ['à', 'è', 'ì', 'ò', 'ù'],
    words: {
      'il', 'lo', 'la', 'di', 'che', 'e', 'è', 'un', 'una', 'per', 'con',
      'sono', 'ciao', 'grazie', 'sì', 'no', 'come', 'cosa', 'non', 'mi',
      'buongiorno', 'molto'
    },
  ),
};
