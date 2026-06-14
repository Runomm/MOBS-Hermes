import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Konuşma oturumu — bir kullanıcının açtığı tek bir Hermes oturumu.
///
/// İki ayrı boyut saklanır (6r-b, 2026-05-30):
/// - `mode`: `'lecture' | 'voiceTranslator' | 'pushToTalk'` — hangi mod
/// - `quality`: `'fast' | 'full'` — Whisper tiny mi small mi (hız vs doğruluk)
///
/// Schema v1 → v2 migration eski tek-boyutlu `'fast'/'full'` değerlerini
/// remap eder (`'fast' → voiceTranslator+fast`, `'full' → lecture+full`).
@DataClassName('SessionRow')
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `'lecture' | 'voiceTranslator' | 'pushToTalk'`.
  TextColumn get mode => text().withLength(min: 1, max: 32)();

  /// `'fast' | 'full'` — Whisper kalite seviyesi. v2'de eklendi, varsayılan
  /// `'fast'` ile eski satırlar otomatik dolar.
  TextColumn get quality =>
      text().withLength(min: 1, max: 16).withDefault(const Constant('fast'))();

  /// Konuşmacı A için BCP-47 (örn. `tr`).
  TextColumn get sourceLanguage => text().withLength(min: 1, max: 16)();

  /// Konuşmacı B için BCP-47 (örn. `en`).
  TextColumn get targetLanguage => text().withLength(min: 1, max: 16)();

  /// UTC.
  DateTimeColumn get startedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// UTC. `endSession` çağrılana kadar `null`.
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Oturum başlığı — internet varsa Gemini'den üretilir, yoksa timestamp
  /// fallback (örn. "2026-05-30-14-32-18 tarihli voice translator
  /// konuşması"). v2'de eklendi, nullable.
  TextColumn get title => text().nullable()();

  // --- Konferans Modu "crunch" sonucu (v3, 2026-06-04) ---
  // Oturum sonunda (veya sonradan arşivden) Qwen ile üretilen tam çeviri +
  // yapılandırılmış özet + başlık. `crunchedAt` null = henüz crunch edilmedi.

  /// Crunch zamanı (UTC). null → crunch edilmemiş.
  DateTimeColumn get crunchedAt => dateTime().nullable()();

  /// Qwen'in seçtiği başlık (konferansın adı olur). null → crunch edilmemiş.
  TextColumn get crunchTitle => text().nullable()();

  /// Transkriptin Qwen ile tam/temiz çevirisi. null → crunch edilmemiş.
  TextColumn get crunchTranslation => text().nullable()();

  /// Yapılandırılmış özet (önemli noktalar, ödevler, vb.). null → crunch yok.
  TextColumn get crunchSummary => text().nullable()();
}

/// Bir oturum içindeki tek bir konuşma sırası.
///
/// Her mesaj tek bir konuşmacının çıktısıdır: ham transkripti (`sourceText`),
/// diğer dile çevirisi (`translatedText`) ve hangi dilde söylendiği
/// (`speakerLanguage`). Çift yönlü akışta `speakerLanguage` mesajdan mesaja
/// değişir, oturumun `source`/`target` çiftiyle eşleşmek zorundadır.
@DataClassName('MessageRow')
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get sessionId =>
      integer().references(Sessions, #id, onDelete: KeyAction.cascade)();

  /// Bu mesajı söyleyen konuşmacının dili (BCP-47).
  TextColumn get speakerLanguage => text().withLength(min: 1, max: 16)();

  /// STT'den çıkan ham (varsa filler-cleaned) metin.
  TextColumn get sourceText => text()();

  /// Çevrilmiş metin. Çeviri başarısız olursa `null`.
  TextColumn get translatedText => text().nullable()();

  /// UTC.
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Sessions, Messages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test'lerde in-memory DB enjekte etmek için.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  // SQLite'da foreign key kısıtlamaları connection başına default OFF.
  // `onDelete: cascade` etkili olsun diye her open'ta açılmalı.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 → v2: sessions tablosuna quality + title sütunları ekle,
            // eski tek-boyutlu mode değerlerini iki boyuta remap et.
            //
            // Mapping (Mehmet 2026-05-30 onayladı):
            //   'fast' → mode='voiceTranslator', quality='fast'
            //   'full' → mode='lecture',         quality='full'
            //
            // quality default'u 'fast' olduğu için eski 'fast' satırları
            // ekstra UPDATE'e ihtiyaç duymaz; sadece 'full' satırları için
            // quality='full' yazılır. UPDATE sıralaması KRİTİK: önce
            // quality, sonra mode — mode remap edilince eski 'fast'/'full'
            // bilgisi kaybolur.
            await m.addColumn(sessions, sessions.quality);
            await m.addColumn(sessions, sessions.title);
            await customStatement(
              "UPDATE sessions SET quality = 'full' WHERE mode = 'full'",
            );
            await customStatement(
              "UPDATE sessions SET mode = 'voiceTranslator' WHERE mode = 'fast'",
            );
            await customStatement(
              "UPDATE sessions SET mode = 'lecture' WHERE mode = 'full'",
            );
          }
          if (from < 3) {
            // v2 → v3: Konferans Modu crunch sonucu sütunları (hepsi nullable).
            await m.addColumn(sessions, sessions.crunchedAt);
            await m.addColumn(sessions, sessions.crunchTitle);
            await m.addColumn(sessions, sessions.crunchTranslation);
            await m.addColumn(sessions, sessions.crunchSummary);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'hermes.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
