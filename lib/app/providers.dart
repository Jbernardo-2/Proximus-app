import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/location_capture.dart';
import '../core/session.dart';
import '../data/database.dart';
import '../features/preventa/data/customer_profile.dart';
import '../features/preventa/data/preventa_models.dart';
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

/// A login that the server accepted but the phone could not finish.
class LoginStepException implements Exception {
  LoginStepException(this.step, this.cause);

  final String step;
  final Object cause;

  @override
  String toString() => 'El teléfono no pudo $step: $cause';
}

class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() => ref.read(secureStoreProvider).session();

  Future<void> login({required String email, required String password, required String serverUrl}) async {
    final store = ref.read(secureStoreProvider);
    final db = ref.read(databaseProvider);
    await _step('guardar el servidor', () => store.saveServerUrl(serverUrl));
    final installationId = await _step('leer el identificador del teléfono', store.installationId);
    final api = ProximusApi(baseUrl: serverUrl);
    final response = await api.login(
      email: email,
      password: password,
      installationId: installationId,
      deviceName: deviceName,
      appVersion: appVersion,
    );
    final device = response['device'] as Map<String, dynamic>?;
    if (device == null) {
      throw ApiException('El servidor no registró este teléfono.');
    }

    final session = await _step('leer la respuesta del servidor', () async => Session(
      serverUrl: serverUrl,
      token: response['token'] as String,
      user: (response['user'] as Map).cast<String, dynamic>(),
      device: device,
      abilities: (response['abilities'] as List).cast<String>(),
    ));

    final owner = await _step('leer el usuario anterior', store.dataOwner);
    if (owner != null && owner != session.userId) {
      final pending = await _step('revisar la cola local', () => (db.selectOnly(db.outbox)
            ..addColumns([db.outbox.id.count()])
            ..where(db.outbox.status.equals(OutboxStatus.pending)))
          .map((row) => row.read(db.outbox.id.count()) ?? 0)
          .getSingle());
      if (pending > 0) {
        await ProximusApi(baseUrl: serverUrl, token: session.token).logout().catchError((_) {});
        throw ApiException('Hay $pending operaciones de otro usuario sin enviar. Ese usuario debe iniciar sesión y sincronizar primero.');
      }
      await _step('limpiar los datos del usuario anterior', db.wipe);
    }

    await _step('guardar las series del teléfono en la base local', () => ref.read(outboxProvider).adoptServerSeries((device['series'] as Map).cast<String, dynamic>()));
    await _step('guardar el usuario', () => store.saveDataOwner(session.userId));
    await _step('guardar la sesión', () => store.saveSession(session));
    state = AsyncData(session);
  }

  /// Names the step that failed, so a problem on a phone can be told apart from a server answer.
  Future<T> _step<T>(String name, Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 20));
    } on ApiException {
      rethrow;
    } catch (error) {
      throw LoginStepException(name, error);
    }
  }

  /// Sends what is pending first. Local data stays for the same user's next login.
  /// First step of signing out: send what is pending and close the token on the server.
  /// Never keeps the user waiting; without signal the queue stays for the next login.
  Future<void> prepareLogout() async {
    final session = state.value;
    if (session == null) return;
    // Built here from the current session: the shared api/engine providers depend on this
    // controller, so reading them from it would be a circular dependency.
    final api = ProximusApi(baseUrl: session.serverUrl, token: session.token);
    final db = ref.read(databaseProvider);
    final engine = SyncEngine(db: db, api: api, outbox: ref.read(outboxProvider));
    try {
      await Future(() async {
        await engine.pushOnly();
        await api.logout();
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // The session still closes on the phone; the token expires on the server.
    }
  }

  Future<void> logout() async {
    await prepareLogout();
    await endSession();
  }

  /// Closes the session on the phone. It always ends, even if the keystore misbehaves.
  Future<void> endSession() async {
    try {
      await ref.read(secureStoreProvider).clearSession().timeout(const Duration(seconds: 5));
    } catch (_) {
      // The session is dropped from memory anyway; the next start reads a clean keystore.
    }
    state = const AsyncData(null);
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

  /// Something was queued while a cycle was running; send it as soon as that cycle ends.
  bool _pushAgain = false;

  Future<void> sync({bool pushOnly = false}) async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    if (state.running) {
      _pushAgain = true;
      return;
    }
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
    } catch (error) {
      // Any other failure ends the cycle visibly instead of leaving "Sincronizando…" forever.
      state = SyncStatus(
        lastReport: SyncReport(pushed: 0, rejected: 0, pulled: const {}, error: ApiException('Error en el teléfono al sincronizar: $error', status: 0, code: 'local_error')),
      );
    }

    if (_pushAgain) {
      _pushAgain = false;
      await sync(pushOnly: true);
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

/// Credit per customer, adjusted by what the phone recorded after the last download.
final customerBalancesProvider = Provider<Map<String, CustomerBalance>>((ref) {
  final credits = ref.watch(localRecordsProvider('customer_credit')).value ?? const [];
  final outbox = ref.watch(outboxRowsProvider).value ?? const [];
  final pulledAt = ref.watch(syncStateProvider('pulled_at:customer_credit')).value;
  return ref.read(preventistaRepositoryProvider).balances(
        credits: credits,
        outbox: outbox,
        pulledAt: pulledAt == null ? null : DateTime.tryParse(pulledAt),
      );
});

final locationServiceProvider = Provider<LocationCaptureService>((ref) => LocationCaptureService());

/// Local data the customer screens read, refreshed as the database changes.
final customerSourcesProvider = Provider<CustomerSources>((ref) {
  List<Map<String, dynamic>> records(String resource) => ref.watch(localRecordsProvider(resource)).value ?? const [];
  DateTime? pulled(String resource) {
    final value = ref.watch(syncStateProvider('pulled_at:$resource')).value;
    return value == null ? null : DateTime.tryParse(value);
  }

  return CustomerSources(
    customers: records('customers'),
    credits: records('customer_credit'),
    receivables: records('receivables'),
    orders: records('recent_orders'),
    outbox: ref.watch(outboxRowsProvider).value ?? const [],
    pulledAt: {for (final resource in const ['customer_credit', 'receivables', 'recent_orders']) resource: pulled(resource)},
    route: ref.watch(dailyRouteProvider).value,
  );
});

final customerListProvider = Provider<List<LocalCustomer>>(
  (ref) => ref.read(preventistaRepositoryProvider).customers(ref.watch(customerSourcesProvider)),
);

final customerProfileProvider = Provider.family<CustomerProfile?, String>(
  (ref, customerId) => ref.read(preventistaRepositoryProvider).customerProfile(customerId, ref.watch(customerSourcesProvider)),
);

/// Account history needs signal: it is read from the server when the profile opens.
final accountEntriesProvider = FutureProvider.autoDispose.family<List<AccountEntry>, String>((ref, customerId) async {
  final api = ref.watch(apiProvider);
  if (api == null) return const [];
  final response = await api.get('/customers/$customerId/credit');
  final entries = ((response['data'] as Map?)?['recent_entries'] as List?) ?? const [];
  return [for (final entry in entries) AccountEntry.fromJson((entry as Map).cast<String, dynamic>())];
});
