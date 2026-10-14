import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../data/database.dart';
import '../features/preventa/data/preventista_repository.dart';
import '../sync/outbox_service.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_manifest.dart';

const appVersion = '0.1.0';
const deviceName = 'Teléfono Android';

final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('Se inyecta en main().'));

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final sessionProvider = AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

final apiProvider = Provider<ProximusApi?>((ref) {
  final session = ref.watch(sessionProvider).value;
  return session == null ? null : ProximusApi(baseUrl: session.serverUrl, token: session.token);
});

final outboxProvider = Provider<OutboxService>((ref) => OutboxService(ref.watch(databaseProvider)));

final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final api = ref.watch(apiProvider);
  return api == null ? null : SyncEngine(db: ref.watch(databaseProvider), api: api, outbox: ref.watch(outboxProvider));
});

class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() => ref.read(secureStoreProvider).session();

  Future<void> login({required String email, required String password, required String serverUrl}) async {
    final store = ref.read(secureStoreProvider);
    final db = ref.read(databaseProvider);
    await store.saveServerUrl(serverUrl);
    final api = ProximusApi(baseUrl: serverUrl);
    final response = await api.login(
      email: email,
      password: password,
      installationId: await store.installationId(),
      deviceName: deviceName,
      appVersion: appVersion,
    );
    final device = response['device'] as Map<String, dynamic>?;
    if (device == null) {
      throw ApiException('El servidor no registró este teléfono.');
    }

    final session = Session(
      serverUrl: serverUrl,
      token: response['token'] as String,
      user: (response['user'] as Map).cast<String, dynamic>(),
      device: device,
      abilities: (response['abilities'] as List).cast<String>(),
    );

    final owner = await store.dataOwner();
    if (owner != null && owner != session.userId) {
      final pending = await (db.selectOnly(db.outbox)
            ..addColumns([db.outbox.id.count()])
            ..where(db.outbox.status.equals(OutboxStatus.pending)))
          .map((row) => row.read(db.outbox.id.count()) ?? 0)
          .getSingle();
      if (pending > 0) {
        await ProximusApi(baseUrl: serverUrl, token: session.token).logout().catchError((_) {});
        throw ApiException('Hay $pending operaciones de otro usuario sin enviar. Ese usuario debe iniciar sesión y sincronizar primero.');
      }
      await db.wipe();
    }

    await ref.read(outboxProvider).adoptServerSeries((device['series'] as Map).cast<String, dynamic>());
    await store.saveDataOwner(session.userId);
    await store.saveSession(session);
    state = AsyncData(session);
  }

  /// Sends what is pending first. Local data stays for the same user's next login.
  Future<int> logout() async {
    final engine = ref.read(syncEngineProvider);
    try {
      await engine?.pushOnly();
      await ref.read(apiProvider)?.logout();
    } catch (_) {
      // Without signal the session still closes on the phone; the token expires on the server.
    }
    await ref.read(secureStoreProvider).clearSession();
    state = const AsyncData(null);
    return _pendingCount();
  }

  /// The server no longer accepts this session (blocked phone or expired token).
  Future<void> endSession() async {
    await ref.read(secureStoreProvider).clearSession();
    state = const AsyncData(null);
  }

  Future<int> _pendingCount() async {
    final db = ref.read(databaseProvider);
    return (db.selectOnly(db.outbox)
          ..addColumns([db.outbox.id.count()])
          ..where(db.outbox.status.equals(OutboxStatus.pending)))
        .map((row) => row.read(db.outbox.id.count()) ?? 0)
        .getSingle();
  }
}

class SyncStatus {
  const SyncStatus({this.running = false, this.lastReport, this.notice});

  final bool running;
  final SyncReport? lastReport;

  /// Message to show once: a blocked phone or an expired session.
  final String? notice;

  SyncStatus copyWith({bool? running, SyncReport? lastReport, String? notice}) =>
      SyncStatus(running: running ?? this.running, lastReport: lastReport ?? this.lastReport, notice: notice);
}

final syncProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);

/// Runs a sync when the session starts, when signal returns and every 15 minutes.
class SyncController extends Notifier<SyncStatus> {
  static const interval = Duration(minutes: 15);

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  @override
  SyncStatus build() {
    final engine = ref.watch(syncEngineProvider);
    ref.onDispose(() {
      _timer?.cancel();
      _connectivity?.cancel();
    });

    if (engine != null) {
      _timer = Timer.periodic(interval, (_) => sync());
      _connectivity = Connectivity().onConnectivityChanged.listen((results) {
        if (!results.contains(ConnectivityResult.none)) sync();
      });
      Future.microtask(sync);
    }
    return const SyncStatus();
  }

  Future<void> sync({bool pushOnly = false}) async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null || state.running) return;
    state = state.copyWith(running: true);

    try {
      final report = pushOnly ? await engine.pushOnly() : await engine.sync();
      state = SyncStatus(lastReport: report);
    } on DeviceRevokedException catch (error) {
      state = SyncStatus(notice: error.message);
      await ref.read(sessionProvider.notifier).endSession();
    } on SessionExpiredException {
      state = const SyncStatus(notice: 'Tu sesión expiró. Inicia sesión de nuevo; lo pendiente se conserva.');
      await ref.read(sessionProvider.notifier).endSession();
    }
  }
}

/// Live counters of the queue for badges.
final outboxCountsProvider = StreamProvider<({int pending, int rejected})>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.outbox).watch().map((rows) => (
        pending: rows.where((row) => row.status == OutboxStatus.pending).length,
        rejected: rows.where((row) => row.status == OutboxStatus.rejected).length,
      ));
});

/// Local records of one resource, decoded.
final localRecordsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, resource) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.syncRecords)..where((r) => r.resource.equals(resource)))
      .watch()
      .map((rows) => [for (final row in rows) decodeRecord(row.data)]);
});

Map<String, dynamic> decodeRecord(String data) => (jsonDecode(data) as Map).cast<String, dynamic>();

/// A value of [SyncState], live.
final syncStateProvider = StreamProvider.family<String?, String>((ref, key) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.syncState)..where((s) => s.key.equals(key))).watchSingleOrNull().map((row) => row?.value);
});

final lastSyncProvider = Provider<AsyncValue<DateTime?>>(
  (ref) => ref.watch(syncStateProvider('last_sync_at')).whenData((value) => value == null ? null : DateTime.tryParse(value)),
);

final manifestProvider = Provider<AsyncValue<SyncManifest?>>(
  (ref) => ref.watch(syncStateProvider('manifest')).whenData(
        (value) => value == null ? null : SyncManifest.decode(value),
      ),
);

final outboxRowsProvider = StreamProvider<List<OutboxData>>(
  (ref) => ref.watch(outboxProvider).watch(),
);

final preventistaRepositoryProvider = Provider<PreventistaRepository>(
  (ref) => const PreventistaRepository(),
);

/// Today's route with what the phone recorded and the server has not reflected yet.
final dailyRouteProvider = Provider<AsyncValue<DailyRoute>>((ref) {
  final records = ref.watch(localRecordsProvider('route_activity'));
  final outbox = ref.watch(outboxRowsProvider);
  final pulledAt = ref.watch(syncStateProvider('pulled_at:route_activity'));

  if (records.isLoading || outbox.isLoading || pulledAt.isLoading) return const AsyncLoading();
  final error = records.error ?? outbox.error ?? pulledAt.error;
  if (error != null) return AsyncError(error, StackTrace.current);

  return AsyncData(ref.read(preventistaRepositoryProvider).mergeRouteActivity(
        records: records.requireValue,
        outbox: outbox.requireValue,
        pulledAt: pulledAt.requireValue == null ? null : DateTime.tryParse(pulledAt.requireValue!),
      ));
});
