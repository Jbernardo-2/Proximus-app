import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/api.dart';
import '../data/database.dart';
import 'outbox_service.dart';

class SyncReport {
  SyncReport({required this.pushed, required this.rejected, required this.pulled, this.error});

  final int pushed;
  final int rejected;

  /// Records received per resource.
  final Map<String, int> pulled;

  /// Set when the cycle stopped early (e.g. no signal); what finished is kept.
  final ApiException? error;

  bool get ok => error == null;
}

/// Thrown when the phone was blocked by the administrator; local data is already wiped.
class DeviceRevokedException implements Exception {
  DeviceRevokedException(this.message);
  final String message;
}

/// Thrown when the token is no longer valid; the queue is kept for after the next login.
class SessionExpiredException implements Exception {}

/// Applies the sync contract (docs/api/sincronizacion-movil.md in the server
/// repository): send the queue first, then download what the user may see.
class SyncEngine {
  SyncEngine({required AppDatabase db, required SyncApi api, required OutboxService outbox, DateTime Function()? clock})
      : _db = db,
        _api = api,
        _outbox = outbox,
        _now = clock ?? DateTime.now;

  static const batchSize = 100;
  static const pageSize = 200;
  static const keepDoneFor = Duration(days: 7);

  final AppDatabase _db;
  final SyncApi _api;
  final OutboxService _outbox;
  final DateTime Function() _now;
  Future<SyncReport>? _running;

  /// One cycle at a time; a second call while running joins the first.
  /// Longest a cycle may take before it is reported as stuck and the next one may start.
  static const maxCycle = Duration(minutes: 3);

  Future<SyncReport> sync() => _running ??= _cycle()
      .timeout(maxCycle, onTimeout: () => SyncReport(pushed: 0, rejected: 0, pulled: const {}, error: ApiException('La sincronización tardó demasiado y se detuvo. Inténtalo de nuevo.', status: 0, code: 'local_timeout')))
      .whenComplete(() => _running = null);

  /// Only the queue, for right after recording something with signal.
  Future<SyncReport> pushOnly() async {
    if (_running != null) return _running!;
    try {
      final (pushed, rejected) = await _push();
      return SyncReport(pushed: pushed, rejected: rejected, pulled: const {});
    } on ApiException catch (error) {
      await _guard(error);
      return SyncReport(pushed: 0, rejected: 0, pulled: const {}, error: error);
    }
  }

  Future<SyncReport> _cycle() async {
    var pushed = 0;
    var rejected = 0;
    final pulled = <String, int>{};

    try {
      final manifest = await _api.manifest();
      await _db.writeState('manifest', jsonEncode(manifest));
      final series = (manifest['device'] as Map<String, dynamic>?)?['series'];
      if (series is Map<String, dynamic>) {
        await _outbox.adoptServerSeries(series);
      }

      (pushed, rejected) = await _push();

      final resources = (manifest['resources'] as Map<String, dynamic>? ?? const {});
      for (final entry in resources.entries) {
        final info = entry.value as Map<String, dynamic>;
        if (info['available'] != true) {
          await _forget(entry.key);
          continue;
        }
        pulled[entry.key] = info['mode'] == 'delta' ? await _pullDelta(entry.key) : await _pullFull(entry.key);
      }

      await _db.writeState('last_sync_at', _now().toIso8601String());
      await _purgeDone();
      return SyncReport(pushed: pushed, rejected: rejected, pulled: pulled);
    } on ApiException catch (error) {
      await _guard(error);
      return SyncReport(pushed: pushed, rejected: rejected, pulled: pulled, error: error);
    }
  }

  Future<void> _guard(ApiException error) async {
    if (error.isDeviceRevoked) {
      await _db.wipe(keepSeries: false);
      throw DeviceRevokedException(error.message);
    }
    if (error.isUnauthorized) {
      throw SessionExpiredException();
    }
  }

  Future<(int, int)> _push() async {
    var pushed = 0;
    var rejected = 0;

    while (true) {
      final now = _now();
      final batch = await (_db.select(_db.outbox)
            ..where((o) => o.status.equals(OutboxStatus.pending) & (o.nextAttemptAt.isNull() | o.nextAttemptAt.isSmallerOrEqualValue(now)))
            ..orderBy([(o) => OrderingTerm.asc(o.id)])
            ..limit(batchSize))
          .get();
      if (batch.isEmpty) break;

      final response = await _api.push([
        for (final operation in batch)
          {'client_reference': operation.clientReference, 'type': operation.type, 'payload': jsonDecode(operation.payload)},
      ]);
      final results = {
        for (final result in (response['results'] as List).cast<Map<String, dynamic>>()) result['client_reference'] as String: result,
      };

      var retryLater = 0;
      await _db.transaction(() async {
        for (final operation in batch) {
          final result = results[operation.clientReference];
          final status = result?['status'] as String?;
          final row = _db.update(_db.outbox)..where((o) => o.id.equals(operation.id));

          if (status == 'accepted' || status == 'duplicate') {
            pushed++;
            await row.write(OutboxCompanion(
              status: const Value(OutboxStatus.done),
              httpStatus: Value(result!['http_status'] as int?),
              result: Value(jsonEncode(result['data'])),
              message: const Value(null),
              processedAt: Value(now),
            ));
          } else if (status == 'rejected') {
            rejected++;
            await row.write(OutboxCompanion(
              status: const Value(OutboxStatus.rejected),
              httpStatus: Value(result!['http_status'] as int?),
              message: Value(_rejection(result)),
              processedAt: Value(now),
            ));
          } else {
            retryLater++;
            final attempts = operation.attempts + 1;
            await row.write(OutboxCompanion(
              attempts: Value(attempts),
              httpStatus: Value(result?['http_status'] as int?),
              message: Value((result?['message'] as String?) ?? 'Error del servidor; se reintentará.'),
              nextAttemptAt: Value(now.add(backoff(attempts))),
            ));
          }
        }
      });

      if (retryLater == batch.length) break;
    }

    return (pushed, rejected);
  }

  static Duration backoff(int attempts) => switch (attempts) {
        1 => const Duration(seconds: 30),
        2 => const Duration(minutes: 2),
        3 => const Duration(minutes: 10),
        _ => const Duration(minutes: 30),
      };

  String _rejection(Map<String, dynamic> result) {
    final errors = result['errors'];
    if (errors is Map && errors.isNotEmpty) {
      return errors.values.expand((value) => value is List ? value : [value]).join(' ');
    }
    return (result['message'] as String?) ?? 'El servidor no aceptó la operación.';
  }

  Future<int> _pullDelta(String resource) async {
    var received = 0;
    var cursor = await _db.readState('cursor:$resource');

    while (true) {
      final page = await _api.pull(resource, cursor: cursor, limit: pageSize);
      final records = (page['records'] as List).cast<Map<String, dynamic>>();
      await _db.transaction(() async {
        for (final record in records) {
          final id = _id(record);
          if (record['deleted'] == true) {
            await (_db.delete(_db.syncRecords)..where((r) => r.resource.equals(resource) & r.id.equals(id))).go();
          } else {
            await _db.into(_db.syncRecords).insertOnConflictUpdate(
                  SyncRecordsCompanion.insert(resource: resource, id: id, data: jsonEncode(record)),
                );
          }
        }
        cursor = page['next_cursor'] as String?;
        await _db.writeState('cursor:$resource', cursor);
      });
      received += records.length;
      if (page['has_more'] != true || records.isEmpty) break;
    }

    await _db.writeState('pulled_at:$resource', _now().toIso8601String());
    return received;
  }

  /// Reads every page first; the local table is replaced only when the whole set arrived.
  Future<int> _pullFull(String resource) async {
    final records = <Map<String, dynamic>>[];
    String? cursor;

    while (true) {
      final page = await _api.pull(resource, cursor: cursor, limit: pageSize);
      records.addAll((page['records'] as List).cast<Map<String, dynamic>>());
      cursor = page['next_cursor'] as String?;
      if (page['has_more'] != true || cursor == null) break;
    }

    await _db.transaction(() async {
      await (_db.delete(_db.syncRecords)..where((r) => r.resource.equals(resource))).go();
      await _db.batch((batch) => batch.insertAll(_db.syncRecords, [
            for (final record in records) SyncRecordsCompanion.insert(resource: resource, id: _id(record), data: jsonEncode(record)),
          ]));
    });
    await _db.writeState('pulled_at:$resource', _now().toIso8601String());
    return records.length;
  }

  /// A resource the user can no longer see (role changed) is removed locally.
  Future<void> _forget(String resource) => _db.transaction(() async {
        await (_db.delete(_db.syncRecords)..where((r) => r.resource.equals(resource))).go();
        await _db.writeState('cursor:$resource', null);
        await _db.writeState('pulled_at:$resource', null);
      });

  Future<void> _purgeDone() => (_db.delete(_db.outbox)
        ..where((o) => o.status.equals(OutboxStatus.done) & o.processedAt.isSmallerThanValue(_now().subtract(keepDoneFor))))
      .go();

  static String _id(Map<String, dynamic> record) => (record['id'] ?? record['customer_id']).toString();
}
