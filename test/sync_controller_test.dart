import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/api.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/sync/outbox_service.dart';
import 'package:proximus_app/sync/sync_engine.dart';

/// An engine that breaks with something that is not a server answer.
class BrokenEngine extends SyncEngine {
  BrokenEngine(AppDatabase db) : super(db: db, api: ProximusApi(baseUrl: 'http://test'), outbox: OutboxService(db));

  @override
  Future<SyncReport> sync() async => throw StateError('dato local dañado');

  @override
  Future<SyncReport> pushOnly() async => throw StateError('dato local dañado');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an unexpected failure ends the sync visibly instead of spinning forever', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      syncEngineProvider.overrideWithValue(BrokenEngine(db)),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await container.read(syncProvider.notifier).sync();
    final status = container.read(syncProvider);

    expect(status.running, isFalse);
    expect(status.lastReport?.error?.isNetwork, isFalse);
    expect(status.lastReport?.error?.message, contains('dato local dañado'));
  });
}
