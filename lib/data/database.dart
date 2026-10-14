import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Copy of a server record kept for working offline, stored as the JSON the
/// server sent. One table for every downloaded resource keeps the schema
/// stable while the server contract grows.
class SyncRecords extends Table {
  TextColumn get resource => text()();
  TextColumn get id => text()();
  TextColumn get data => text()();

  @override
  Set<Column<Object>> get primaryKey => {resource, id};
}

/// Small key/value state: cursors, last manifest, last sync times, owner.
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Facts recorded on the phone waiting to be sent, in order.
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientReference => text().unique()();
  TextColumn get type => text()();
  TextColumn get payload => text()();

  /// One of [OutboxStatus].
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get summary => text().withDefault(const Constant(''))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  IntColumn get httpStatus => integer().nullable()();
  TextColumn get message => text().nullable()();
  TextColumn get result => text().nullable()();
  DateTimeColumn get processedAt => dateTime().nullable()();
}

abstract final class OutboxStatus {
  static const pending = 'pending';
  static const done = 'done';
  static const rejected = 'rejected';
}

/// Last number used by this phone for each of its document series.
@DataClassName('DocumentSeriesRow')
class DocumentSeries extends Table {
  TextColumn get scope => text()();
  TextColumn get prefix => text()();
  IntColumn get lastNumber => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {scope};
}

@DriftDatabase(tables: [SyncRecords, SyncState, Outbox, DocumentSeries])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'proximus'));

  @override
  int get schemaVersion => 1;

  Future<String?> readState(String key) async {
    final row = await (select(syncState)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeState(String key, String? value) async {
    if (value == null) {
      await (delete(syncState)..where((s) => s.key.equals(key))).go();
      return;
    }
    await into(syncState).insertOnConflictUpdate(SyncStateCompanion.insert(key: key, value: value));
  }

  /// Everything local: used when another user signs in or the phone is blocked.
  /// Document series belong to the phone, not the user, so they survive a
  /// change of user and a printed number is never repeated.
  Future<void> wipe({bool keepSeries = true}) => transaction(() async {
        await delete(syncRecords).go();
        await delete(syncState).go();
        await delete(outbox).go();
        if (!keepSeries) {
          await delete(documentSeries).go();
        }
      });
}
