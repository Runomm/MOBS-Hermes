import '../database/app_database.dart';
import '../repositories/conversation_repository.dart';

/// Oturum başlığı üreticisi (6r-f).
///
/// `SessionEnd` anında çağrılır, dönen başlık `sessions.title` column'una
/// yazılır (tasarım §3.7). Strategy Pattern: offline timestamp fallback her
/// zaman çalışır; online (Gemini) üretici Step 9'da `HybridTitleGenerator`'a
/// enjekte edilir.
abstract class TitleGenerator {
  Future<String> generate({
    required SessionMode mode,
    required List<MessageRow> messages,
    required DateTime startedAt,
  });
}

/// İnternet gerektirmeyen varsayılan üretici.
///
/// Format: `YYYY-MM-DD-HH-MM-SS tarihli {mod} konuşması`
/// Örn: `2026-05-31-21-04-08 tarihli bas konuş konuşması` (tasarım §3.7).
class TimestampFallbackGenerator implements TitleGenerator {
  const TimestampFallbackGenerator();

  @override
  Future<String> generate({
    required SessionMode mode,
    required List<MessageRow> messages,
    required DateTime startedAt,
  }) async =>
      titleFor(mode, startedAt);

  /// Saf (test edilebilir) başlık üretimi — `startedAt` yerel saate çevrilir.
  static String titleFor(SessionMode mode, DateTime startedAt) {
    final t = startedAt.toLocal();
    final ts = '${t.year}-${_p(t.month)}-${_p(t.day)}-'
        '${_p(t.hour)}-${_p(t.minute)}-${_p(t.second)}';
    return '$ts tarihli ${modeName(mode)} konuşması';
  }

  static String modeName(SessionMode mode) => switch (mode) {
        SessionMode.lecture => 'konferans',
        SessionMode.voiceTranslator => 'smalltalk',
        SessionMode.pushToTalk => 'bas konuş',
      };

  static String _p(int n) => n.toString().padLeft(2, '0');
}

/// Önce online üreticiyi (varsa) dener; hata/timeout/boş → timestamp fallback.
///
/// Faz 1'de [online] `null` → her zaman fallback (offline-first). Step 9'da
/// `GeminiTitleGenerator` enjekte edilince içerikten anlamlı başlık üretilir,
/// internet yoksa veya API patlarsa sessizce timestamp'e düşülür.
class HybridTitleGenerator implements TitleGenerator {
  const HybridTitleGenerator({
    TitleGenerator? online,
    this.fallback = const TimestampFallbackGenerator(),
  }) : _online = online;

  final TitleGenerator? _online;
  final TitleGenerator fallback;

  @override
  Future<String> generate({
    required SessionMode mode,
    required List<MessageRow> messages,
    required DateTime startedAt,
  }) async {
    final online = _online;
    if (online != null) {
      try {
        final title = await online.generate(
          mode: mode,
          messages: messages,
          startedAt: startedAt,
        );
        if (title.trim().isNotEmpty) return title.trim();
      } catch (_) {
        // Online üretim patladı → sessizce fallback.
      }
    }
    return fallback.generate(
      mode: mode,
      messages: messages,
      startedAt: startedAt,
    );
  }
}
