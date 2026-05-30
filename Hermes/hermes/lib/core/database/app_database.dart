import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Konuşma oturumu — bir kullanıcının açtığı tek bir Hermes oturumu.
///
/// `mode`: `SessionMode.fast` / `SessionMode.full` (saklanırken string olarak
/// `'fast' | 'full'`). UI label sonradan değişebilir, kalıcı enum adı stabil
/// kalır.
@DataClassName('SessionRow')
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `fast` veya `full`.
  TextColumn get mode => text().withLength(min: 1, max: 16)();

  /// Konuşmacı A için BCP-47 (örn. `tr`).
  TextColumn get sourceLanguage => text().withLength(min: 1, max: 16)();

  /// Konuşmacı B için BCP-47 (örn. `en`).
  TextColumn get targetLanguage => text().withLength(min: 1, max: 16)();

  /// UTC.
  DateTimeColumn get startedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// UTC. `endSession` çağrılana kadar `null`.
  DateTimeColumn get endedAt => dateTime().nullable()();
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
  int get schemaVersion => 1;

  // SQLite'da foreign key kısıtlamaları connection başına default OFF.
  // `onDelete: cascade` etkili olsun diye her open'ta açılmalı.
  @override
  MigrationStrategy get migration => MigrationStrategy(
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
