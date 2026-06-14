import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Oturum modu — Hermes'in 3 modundan biri (Mehmet 2026-05-30 kesinleşti).
/// DB'de string olarak `name` ile saklanır. UI label sonradan değişebilir,
/// enum adı stabil kalır.
///
/// Geriye dönük uyumluluk: v1 schema'da `'fast'` / `'full'` saklanıyordu.
/// `fromDbValue` bu eski değerleri yeni 3-mod evrenine map'ler. Migration
/// `app_database.dart::MigrationStrategy.onUpgrade` içinde DB satırlarını
/// kalıcı olarak günceller; `fromDbValue`'daki fallback sadece eski tohumlar
/// veya beklenmedik değerler için savunma katmanı.
enum SessionMode {
  lecture,          // Ders Modu
  voiceTranslator,  // Voice Translator (kulaklık zorunlu, çift mic)
  pushToTalk;       // Bas Konuş Modu

  String get dbValue => name;

  static SessionMode fromDbValue(String value) {
    return switch (value) {
      'lecture' => SessionMode.lecture,
      'voiceTranslator' => SessionMode.voiceTranslator,
      'pushToTalk' => SessionMode.pushToTalk,
      // Eski v1 değerleri — migration sonrası DB'de kalmamalı ama tohum
      // dosyalardan / harici satırlardan gelirse savunma.
      'full' => SessionMode.lecture,
      'fast' => SessionMode.voiceTranslator,
      _ => SessionMode.voiceTranslator,
    };
  }
}

/// Oturum kalite seviyesi. Her `SessionMode` ile birlikte saklanır.
///
/// SmallTalk hands-free **3 katman** kullanır (Mehmet 2026-06-08):
/// - [fast]     = Vosk×2 + MLKit (hız, hafif)
/// - [full]     = Whisper + MLKit (daha doğru tanıma, MLKit çeviri)
/// - [fullPlus] = Whisper + NLLB (en kaliteli çeviri, ağır — düşük-RAM uyarısı)
///
/// Diğer modlar (Bas Konuş/Ders=Manager, Konferans) yalnız [fast]/[full]
/// kullanır (orada anlam: Whisper tiny vs small / TTS backpressure). [fullPlus]
/// sadece SmallTalk'ta görünür.
enum SessionQuality {
  fast,
  full,
  fullPlus;

  String get dbValue => name;

  static SessionQuality fromDbValue(String value) {
    return switch (value) {
      'fast' => SessionQuality.fast,
      'full' => SessionQuality.full,
      'fullPlus' => SessionQuality.fullPlus,
      _ => SessionQuality.fast,
    };
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
  /// `currentDateAndTime` ile dolmuş olur. `quality` opsiyonel, default
  /// `SessionQuality.fast` (Voice Translator/Bas Konuş için doğal varsayılan;
  /// Ders Modu çağıranı `full` geçer).
  Future<SessionRow> createSession({
    required SessionMode mode,
    required String sourceLanguage,
    required String targetLanguage,
    SessionQuality quality = SessionQuality.fast,
  }) {
    return _db
        .into(_db.sessions)
        .insertReturning(
          SessionsCompanion.insert(
            mode: mode.dbValue,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            quality: Value(quality.dbValue),
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

  /// Oturum başlığını yaz (6r-f). `SessionEnd` anında `TitleGenerator`
  /// çıktısı buraya yazılır. Daha önce başlık varsa üzerine yazar.
  Future<void> setTitle(int sessionId, String title) async {
    await (_db.update(_db.sessions)
          ..where((s) => s.id.equals(sessionId)))
        .write(SessionsCompanion(title: Value(title)));
  }

  /// Konferans Modu "crunch" sonucunu yaz (v3, 2026-06-04). Qwen'in ürettiği
  /// başlık + tam çeviri + özet; `crunchedAt` şu ana set edilir (= crunch'lı
  /// işareti). Arşiv ekranı `crunchedAt != null` ile "already crunched" gösterir.
  Future<void> setCrunchResult(
    int sessionId, {
    required String title,
    required String translation,
    required String summary,
  }) async {
    await (_db.update(_db.sessions)..where((s) => s.id.equals(sessionId)))
        .write(SessionsCompanion(
      crunchedAt: Value(DateTime.now().toUtc()),
      crunchTitle: Value(title),
      crunchTranslation: Value(translation),
      crunchSummary: Value(summary),
    ));
  }

  /// **Faz A — Derinlemesine Çevir** sonucu: yalnız tam çeviriyi yazar.
  /// `crunchedAt` SET EDİLMEZ → oturum "çevrildi ama özetlenmedi" durumunda kalır
  /// (detay ekranı "Özetle" butonu gösterir). 2-adımlı crunch (2026-06-09).
  Future<void> setCrunchTranslation(int sessionId, String translation) async {
    await (_db.update(_db.sessions)..where((s) => s.id.equals(sessionId)))
        .write(SessionsCompanion(crunchTranslation: Value(translation)));
  }

  /// **Faz B — Özetle** sonucu: özet + başlık + `crunchedAt` (= tamamlandı
  /// işareti; arşiv "already crunched" bununla işaretler).
  Future<void> setCrunchSummary(
    int sessionId, {
    required String title,
    required String summary,
  }) async {
    await (_db.update(_db.sessions)..where((s) => s.id.equals(sessionId)))
        .write(SessionsCompanion(
      crunchedAt: Value(DateTime.now().toUtc()),
      crunchTitle: Value(title),
      crunchSummary: Value(summary),
    ));
  }

  /// Belirli moddaki oturumlar — en yeni önce. Konferans arşivi (klasör)
  /// `SessionMode.lecture` ile çağırır.
  Future<List<SessionRow>> listSessionsForMode(SessionMode mode) {
    return (_db.select(_db.sessions)
          ..where((s) => s.mode.equals(mode.dbValue))
          ..orderBy([
            (s) => OrderingTerm.desc(s.startedAt),
            (s) => OrderingTerm.desc(s.id),
          ]))
        .get();
  }

  /// Birden çok moddaki oturumlar — en yeni önce. SmallTalk arşivi (klasör)
  /// hem `voiceTranslator` (hands-free) hem `pushToTalk` (bas konuş) alt-modlarını
  /// tek listede gösterir.
  Future<List<SessionRow>> listSessionsForModes(List<SessionMode> modes) {
    final values = modes.map((m) => m.dbValue).toList();
    return (_db.select(_db.sessions)
          ..where((s) => s.mode.isIn(values))
          ..orderBy([
            (s) => OrderingTerm.desc(s.startedAt),
            (s) => OrderingTerm.desc(s.id),
          ]))
        .get();
  }

  /// Bir oturumu (ve cascade ile mesajlarını) sil.
  Future<void> deleteSession(int sessionId) async {
    await (_db.delete(_db.sessions)..where((s) => s.id.equals(sessionId))).go();
  }

  /// Oturumda hiç mesaj yoksa (boş transkript) sil. Döndürdüğü `true` = silindi.
  /// Boş oturumların arşive/dosyalara kaydını engeller (Mehmet 2026-06-11).
  Future<bool> deleteSessionIfEmpty(int sessionId) async {
    if (await countMessages(sessionId) > 0) return false;
    await deleteSession(sessionId);
    return true;
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
