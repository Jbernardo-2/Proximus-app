import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../data/database.dart';
import 'outbox_service.dart';
import 'sync_engine.dart';

const _taskName = 'proximus.sync';
const _uniqueName = 'proximus-periodic-sync';

/// The app writes this while it is open; the background task stays out of its way.
const foregroundHeartbeatKey = 'foreground_at';
const _foregroundGrace = Duration(minutes: 3);

/// Entry point Android calls in a separate engine, even with the app closed.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    return runBackgroundSync();
  });
}

/// One sync cycle without the UI. Returns false only to ask Android to retry later.
Future<bool> runBackgroundSync({SecureStore? store, AppDatabase? database, DateTime Function()? clock, SyncApi Function(Session session)? api}) async {
  final secure = store ?? SecureStore();
  final session = await secure.session();
  // Opened without signal or expired: only the user can fix it, with the password.
  if (session == null || !session.canSync) return true;

  final db = database ?? AppDatabase();
  try {
    final heartbeat = DateTime.tryParse(await db.readState(foregroundHeartbeatKey) ?? '');
    final now = (clock ?? DateTime.now)();
    if (heartbeat != null && now.difference(heartbeat) < _foregroundGrace) return true;

    final engine = SyncEngine(db: db, api: api?.call(session) ?? ProximusApi(baseUrl: session.serverUrl, token: session.token), outbox: OutboxService(db));
    final report = await engine.sync();
    return report.error == null || report.error!.isNetwork;
  } on DeviceRevokedException {
    await secure.clearSession();
    return true;
  } on SessionExpiredException {
    // Same as in the app: keep the user in, ask for the password when it is opened.
    await secure.saveSession(session.copyWith(needsReauth: true));
    return true;
  } catch (error) {
    debugPrint('Proximus: sincronización en segundo plano falló: $error');
    return false;
  } finally {
    if (database == null) await db.close();
  }
}

/// Every 15 minutes (Android's minimum) when there is a connection.
Future<void> scheduleBackgroundSync() async {
  await Workmanager().initialize(backgroundSyncDispatcher);
  await Workmanager().registerPeriodicTask(
    _uniqueName,
    _taskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

Future<void> cancelBackgroundSync() => Workmanager().cancelByUniqueName(_uniqueName);
