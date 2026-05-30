import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Oturum modu — DB'de string olarak (`'fast'` / `'full'`) saklanır.
/// UI label sonradan değişebilir, enum adı stabil kalır.
enum SessionMode {
  fast,
  full;

  String get dbValue => name;

  static SessionMode fromDbValue(String value) {
    return SessionMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => SessionMode.full,
    );
  }
}

/// Oturum + mesaj kalıcılık katmanı.
///
/// `AppDatabase`'in tüm DAO-vari iş mantığını burada toplar; çağıranlar Drift
/// tablolarını veya `Insertable` türlerini doğrudan görmemeli.
///
/// Tüm metotlar `async` ve idempotent değil — `appendMessage` her çağrıda yeni
/// satır yazar.
class ConversationRepository {
  ConversationRepository(this._db);

  final AppDatabase _db;

  /// Yeni bir oturum aç. Dönen [SessionRow] DB tarafında `startedAt`
  /// `currentDateAndTime` ile dolmuş olur.
  Future<SessionRow> createSession({
    required SessionMode mode,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    return _db
        .into(_db.sessions)
        .insertReturning(
          SessionsCompanion.insert(
            mode: mode.dbValue,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
          ),
        );
  }

  /// Oturumu bitir — `endedAt`'i şu ana set eder.
  /// Daha önce kapatılmış oturum için de güvenli (idempotent değil ama
  /// veriyi bozmaz: sadece `endedAt` güncellenir).
  Future<void> endSession(int sessionId) async {
    await (_db.update(_db.sessions)
          ..where((s) => s.id.equals(sessionId)))
        .write(SessionsCompanion(endedAt: Value(DateTime.now().toUtc())));
  }

  /// Oturuma yeni mesaj ekle. [translatedText] çeviri başarısızsa `null`.
  Future<MessageRow> appendMessage({
    required int sessionId,
    required String speakerLanguage,
    required String sourceText,
    String? translatedText,
  }) {
    return _db
        .into(_db.messages)
        .insertReturning(
          MessagesCompanion.insert(
            sessionId: sessionId,
            speakerLanguage: speakerLanguage,
            sourceText: sourceText,
            translatedText: Value(translatedText),
          ),
        );
  }

  /// Tek oturum getir. Bulunamazsa `null`.
  Future<SessionRow?> getSession(int sessionId) {
    return (_db.select(_db.sessions)
          ..where((s) => s.id.equals(sessionId)))
        .getSingleOrNull();
  }

  /// Bir oturumdaki tüm mesajlar — kronolojik (en eski önce).
  Future<List<MessageRow>> listMessagesForSession(int sessionId) {
    return (_db.select(_db.messages)
          ..where((m) => m.sessionId.equals(sessionId))
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .get();
  }

  /// Tüm oturumlar — en yeni önce (ana ekran geçmiş listesi için).
  /// `startedAt` SQLite'da saniye granularitesinde; aynı saniyede açılan
  /// oturumları stabil sıralamak için id ile tiebreak.
  Future<List<SessionRow>> listAllSessions() {
    return (_db.select(_db.sessions)
          ..orderBy([
            (s) => OrderingTerm.desc(s.startedAt),
            (s) => OrderingTerm.desc(s.id),
          ]))
        .get();
  }

  /// Bir oturumdaki mesaj sayısı.
  Future<int> countMessages(int sessionId) async {
    final countExp = _db.messages.id.count();
    final query = _db.selectOnly(_db.messages)
      ..addColumns([countExp])
      ..where(_db.messages.sessionId.equals(sessionId));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }
}
