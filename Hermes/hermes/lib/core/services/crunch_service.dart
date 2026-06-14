/// Konferans "crunch" servisi (K4, 2026-06-05; NLLB çeviri 2026-06-07).
///
/// Oturum sonunda (veya arşivden) transkripti iki motorla işler:
///   1. **Tam çeviri** — transkript küçük parçalar hâlinde hedef dile **NLLB**
///      (saf NMT) ile çevrilir. Bağlam-güvenli (her parça küçük).
///   2. **Özet** — her parçanın çevirisi **Phi** ile kısa nota indirgenir, sonra
///      notlar **map-reduce** ile birleştirilir (önemli noktalar, ödevler, vb.).
///   3. **Başlık** — özetten kısa bir başlık (konferansın adı olur), Phi.
///
/// **İki faz / RAM (KRİTİK):** Önce TÜM çeviriler NLLB ile yapılır (Faz A),
/// ardından [afterTranslate] ile NLLB boşaltılır (çağıran `dispose` eder), sonra
/// Phi özet fazı başlar (Faz B). Böylece NLLB (~1.3GB) + Phi aynı anda resident
/// olmaz — Poco 8GB'de OOM koruması.
///
/// **Bağlam güvenliği (Phi):** Phi'nin bağlam penceresi sınırlı. Her LLM
/// çağrısının GİRDİSİ sıkı sınırlanır — aksi halde native taraf prompt bağlamı
/// aşınca çöker. "Rolling summary" KULLANMAZ; her parça/pencere bağımsız ve
/// küçük tutulur, birleştirme kademeli yapılır.
///
/// Motorlar enjekte edilir — üretimde [translate]=`NllbTranslationEngine`,
/// [run]=`LlmHost.generate(phi,...)`; testte deterministik fake. Böylece
/// chunk/aggregate/ilerleme mantığı native bağımlılık olmadan test edilir.
class CrunchService {
  CrunchService({
    required this.translate,
    required this.run,
    this.afterTranslate,
    this.maxCharsPerChunk = 350,
    this.reduceCharBudget = 1200,
  });

  /// Bir metin parçasını [srcLang]→[tgtLang] çevirir (NLLB, BCP-47 kodları).
  final Future<String> Function(String text, String srcLang, String tgtLang)
      translate;

  /// Tek bir özet/başlık prompt'unu çalıştırıp metin döndürür (Phi).
  final Future<String> Function(String prompt) run;

  /// Faz A (tüm çeviriler) bitince, Faz B (Phi) başlamadan önce çağrılır.
  /// Çağıran burada NLLB'yi `dispose` edip RAM'i boşaltır (Phi'ye yer açar).
  final Future<void> Function()? afterTranslate;

  /// Bir çeviri parçasına en fazla kaç karakter transkript girer. Küçük tutmak
  /// modelin bağlam sınırını aşmamayı garanti eder (native çökme koruması).
  final int maxCharsPerChunk;

  /// Notları birleştirirken (reduce) tek çağrıya giren en fazla karakter.
  final int reduceCharBudget;

  static const _langNames = {
    'tr': 'Turkish',
    'en': 'English',
    'es': 'Spanish',
    'de': 'German',
    'fr': 'French',
    'it': 'Italian',
  };

  static String _name(String code) => _langNames[code] ?? code;

  /// Bir BCP-47 dil kodunun İngilizce adı (prompt'larda kullanılır). Çevrimiçi
  /// crunch runner'ı da çeviri prompt'unda bunu kullanır → tek kaynak.
  static String languageName(String code) => _name(code);

  /// **Faz A — Derinlemesine Çevir.** Transkript satırlarını ([transcripts] =
  /// mesajların `sourceText`'leri) küçük parçalar hâlinde NLLB ile [targetLang]'a
  /// çevirir, birleşik tam çeviriyi döndürür. [onProgress] 0–1. (NLLB dispose'u
  /// çağıran tarafta — `afterTranslate` ya da doğrudan.)
  Future<String> translateTranscript({
    required List<String> transcripts,
    required String sourceLang,
    required String targetLang,
    void Function(double progress)? onProgress,
  }) async {
    final chunks = _chunk(transcripts);
    if (chunks.isEmpty) {
      onProgress?.call(1.0);
      return '';
    }
    final parts = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      parts.add((await translate(chunks[i], sourceLang, targetLang)).trim());
      onProgress?.call((i + 1) / chunks.length);
    }
    return parts.join('\n\n');
  }

  /// **Faz B — Özetle.** Hazır [translationText] (Faz A çıktısı, [targetLang]
  /// dilinde) → Gemma ile ana hikaye / verilmek istenen düşünce / önemli noktalar
  /// özeti + başlık. Girdiler küçük parçalara bölünür (bağlam güvenli),
  /// hierarchical reduce ile birleşir. [onProgress] 0–1.
  Future<CrunchSummary> summarize({
    required String translationText,
    required String targetLang,
    void Function(double progress)? onProgress,
  }) async {
    final chunks = _chunk([translationText]);
    if (chunks.isEmpty) {
      onProgress?.call(1.0);
      return const CrunchSummary(title: 'Konuşma', summary: '');
    }
    final tgt = _name(targetLang);
    final notes = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final note = (await run(_notePrompt(chunks[i], tgt))).trim();
      if (note.isNotEmpty) notes.add(note);
      onProgress?.call((i + 1) / chunks.length * 0.7);
    }
    final summary = await _reduceNotes(notes, tgt);
    onProgress?.call(0.9);
    final title = summary.isEmpty
        ? 'Konuşma'
        : _sanitizeTitle((await run(_titlePrompt(summary, tgt))).trim());
    onProgress?.call(1.0);
    return CrunchSummary(
      title: title.isEmpty ? 'Konuşma' : title,
      summary: summary,
    );
  }

  /// Tek adımda çevir + özetle (🧪 crunch de-risk ekranı için; gerçek akış iki
  /// butonla [translateTranscript] + [summarize]'ı ayrı çağırır).
  Future<CrunchResult> crunch({
    required List<String> transcripts,
    required String sourceLang,
    required String targetLang,
    void Function(double progress)? onProgress,
  }) async {
    final translation = await translateTranscript(
      transcripts: transcripts,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: (p) => onProgress?.call(p * 0.5),
    );
    await afterTranslate?.call();
    final s = await summarize(
      translationText: translation,
      targetLang: targetLang,
      onProgress: (p) => onProgress?.call(0.5 + p * 0.5),
    );
    return CrunchResult(
      title: s.title,
      fullTranslation: translation,
      summary: s.summary,
    );
  }

  /// Notları tek bir özete indirir. Notlar `reduceCharBudget`'i aşarsa
  /// pencerelere bölünüp her pencere ayrı özetlenir; tek özet kalana kadar
  /// tekrar eder (hierarchical reduce — her çağrı bağlam-güvenli).
  Future<String> _reduceNotes(List<String> notes, String tgt) async {
    if (notes.isEmpty) return '';
    var current = notes;
    while (current.length > 1) {
      final next = <String>[];
      var i = 0;
      while (i < current.length) {
        final window = StringBuffer();
        while (i < current.length &&
            (window.isEmpty ||
                window.length + current[i].length + 2 <= reduceCharBudget)) {
          if (window.isNotEmpty) window.write('\n\n');
          window.write(current[i]);
          i++;
        }
        next.add((await run(_reducePrompt(window.toString(), tgt))).trim());
      }
      current = next;
    }
    return current.first;
  }

  /// Tüm transkripti kelimelere açıp [maxCharsPerChunk]'ı aşmayan parçalara
  /// paketler. Kısa satırları birleştirir, uzun tek satırı kelime sınırından
  /// böler → hiçbir parça bağlam sınırını zorlamaz.
  List<String> _chunk(List<String> transcripts) {
    final words = <String>[];
    for (final raw in transcripts) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      words.addAll(line.split(RegExp(r'\s+')));
    }
    final chunks = <String>[];
    final buf = StringBuffer();
    for (final w in words) {
      if (buf.isNotEmpty && buf.length + w.length + 1 > maxCharsPerChunk) {
        chunks.add(buf.toString());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(w);
    }
    if (buf.isNotEmpty) chunks.add(buf.toString());
    return chunks;
  }

  String _notePrompt(String excerpt, String tgt) =>
      'You are summarizing a conversation/talk (in $tgt). From this excerpt, '
      'capture what is being discussed and the key message as a few short bullet '
      'points — the main points, any important details, decisions or conclusions. '
      'Be concise, no filler. Output ONLY the bullet points in $tgt.\n\n'
      'Excerpt:\n$excerpt\n\nKey points:';

  String _reducePrompt(String notes, String tgt) =>
      'Combine these notes into a single concise summary in $tgt that conveys the '
      'main story, the intended message, and the most important points. Write a '
      'short coherent summary (a few sentences or tight bullet points), remove '
      'repetition. Output ONLY the summary in $tgt.\n\nNotes:\n$notes\n\nSummary:';

  String _titlePrompt(String summary, String tgt) =>
      'Give a short descriptive title (3 to 6 words) in $tgt for this conversation, '
      'based on the summary below. Output ONLY the title, no quotes, no period.\n\n'
      'Summary:\n$summary\n\nTitle:';

  /// Başlığı tek satıra indir + tırnak/sonbaşı noktalama temizle.
  static String _sanitizeTitle(String raw) {
    var t = raw.split('\n').first.trim();
    t = t.replaceAll(RegExp(r'^["“”\s]+|["“”.\s]+$'), '');
    return t.isEmpty ? 'Konferans' : t;
  }
}

/// Crunch çıktısı — başlık + tam çeviri + yapılandırılmış özet (tek-adım crunch).
class CrunchResult {
  const CrunchResult({
    required this.title,
    required this.fullTranslation,
    required this.summary,
  });

  final String title;
  final String fullTranslation;
  final String summary;
}

/// Özet fazı çıktısı — başlık + özet (Faz B / [CrunchService.summarize]).
class CrunchSummary {
  const CrunchSummary({required this.title, required this.summary});

  final String title;
  final String summary;
}
