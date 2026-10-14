import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';

/// Records facts on the phone. Every write goes through here, with or without
/// signal; the sync engine sends them later in the same order.
class OutboxService {
  OutboxService(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  /// Queues an operation. [build] receives a numbering function so a document
  /// number and the operation that prints it are saved in one transaction:
  /// if the app closes right after, the number is never handed out twice.
  Future<OutboxData> enqueue({
    required String deviceCode,
    required String type,
    required String summary,
    required Future<Map<String, dynamic>> Function(Future<String> Function(String scope) number) build,
  }) async {
    return _db.transaction(() async {
      final payload = await build(_next);
      final id = await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            clientReference: '$deviceCode:${_uuid.v4()}',
            type: type,
            payload: jsonEncode(payload),
            summary: Value(summary),
            createdAt: DateTime.now(),
          ));

      return (_db.select(_db.outbox)..where((o) => o.id.equals(id))).getSingle();
    });
  }

  /// Next number of a series, e.g. FAC-M001-000046. Never reused.
  Future<String> nextNumber(String scope) => _db.transaction(() => _next(scope));

  Future<String> _next(String scope) async {
    final series = await (_db.select(_db.documentSeries)..where((s) => s.scope.equals(scope))).getSingleOrNull();
    if (series == null) {
      throw StateError('El teléfono no tiene serie para "$scope". Sincroniza con señal antes de emitir documentos.');
    }
    final next = series.lastNumber + 1;
    await (_db.update(_db.documentSeries)..where((s) => s.scope.equals(scope)))
        .write(DocumentSeriesCompanion(lastNumber: Value(next)));
    return '${series.prefix}${next.toString().padLeft(6, '0')}';
  }

  /// Keeps the local counters at or above what the server already holds.
  Future<void> adoptServerSeries(Map<String, dynamic> series) => _db.transaction(() async {
        for (final entry in series.entries) {
          final info = entry.value as Map<String, dynamic>;
          final prefix = info['prefix'] as String;
          final serverLast = (info['last_number'] as num).toInt();
          final local = await (_db.select(_db.documentSeries)..where((s) => s.scope.equals(entry.key))).getSingleOrNull();

          if (local == null || local.prefix != prefix) {
            await _db.into(_db.documentSeries).insertOnConflictUpdate(
                  DocumentSeriesCompanion.insert(scope: entry.key, prefix: prefix, lastNumber: Value(serverLast)),
                );
          } else if (serverLast > local.lastNumber) {
            await (_db.update(_db.documentSeries)..where((s) => s.scope.equals(entry.key)))
                .write(DocumentSeriesCompanion(lastNumber: Value(serverLast)));
          }
        }
      });

  Stream<List<OutboxData>> watch({String? status}) {
    final query = _db.select(_db.outbox)
      ..orderBy([(o) => OrderingTerm.asc(o.id)]);
    if (status != null) query.where((o) => o.status.equals(status));
    return query.watch();
  }

  /// A rejected operation the user has read and dismissed.
  Future<void> dismiss(int id) => (_db.delete(_db.outbox)..where((o) => o.id.equals(id))).go();
}
