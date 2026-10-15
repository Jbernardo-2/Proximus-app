import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/decimal_value.dart';
import '../core/location_capture.dart';
import '../core/offline_credential.dart';
import '../core/session.dart';
import '../data/database.dart';
import '../features/preventa/data/customer_profile.dart';
import '../features/preventa/data/preventa_models.dart';
import '../features/preventa/data/preventista_repository.dart';
import '../sync/outbox_service.dart';
import '../sync/sync_engine.dart';
import '../sync/background_sync.dart';
import '../sync/operation_view.dart';
import '../sync/sync_manifest.dart';

const appVersion = '0.1.0';
const deviceName = 'Teléfono Android';

final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('Se inyecta en main().'));

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final sessionProvider = AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

final apiProvider = Provider<ProximusApi?>((ref) {
  final session = ref.watch(sessionProvider).value;
  // No calls to the server while the session is not accepted there (opened offline or expired).
  return session == null || !session.canSync ? null : ProximusApi(baseUrl: session.serverUrl, token: session.token);
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

  /// Online login; without signal, the last user of this phone may enter with the
  /// password checked against the fingerprint kept from the last online login.
  Future<void> login({required String email, required String password, required String serverUrl}) async {
    try {
      await _loginOnline(email: email, password: password, serverUrl: serverUrl);
    } on ApiException catch (error) {
      if (!error.isNetwork) rethrow;
      await _loginOffline(email: email, password: password, networkError: error);
    }
  }

  /// The server stopped accepting this session; the user goes on working on the phone.
  Future<void> markNeedsReauth() async {
    final session = state.value;
    if (session == null || session.needsReauth) return;
    final updated = session.copyWith(needsReauth: true);
    await ref.read(secureStoreProvider).saveSession(updated).catchError((_) {});
    state = AsyncData(updated);
  }

  /// Swaps a token older than a week for a new one, so a session in use never expires offline.
  Future<void> renewIfDue() async {
    final session = state.value;
    if (session == null || !session.shouldRenew(DateTime.now())) return;
    final response = await ProximusApi(baseUrl: session.serverUrl, token: session.token).refresh();
    final renewed = session.copyWith(
      token: response['token'] as String,
      abilities: (response['abilities'] as List).cast<String>(),
      user: (response['user'] as Map).cast<String, dynamic>(),
      device: (response['device'] as Map?)?.cast<String, dynamic>(),
      issuedAt: DateTime.now(),
      expiresAt: DateTime.tryParse(response['expires_at'] as String? ?? ''),
    );
    await ref.read(secureStoreProvider).saveSession(renewed);
    state = AsyncData(renewed);
  }

  Future<void> _loginOnline({required String email, required String password, required String serverUrl}) async {
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
      user: {...(response['user'] as Map).cast<String, dynamic>(), 'email': email.trim().toLowerCase()},
      device: device,
      abilities: (response['abilities'] as List).cast<String>(),
      issuedAt: DateTime.now(),
      expiresAt: DateTime.tryParse(response['expires_at'] as String? ?? ''),
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
    // The password fingerprint for entering without signal next time. Not worth failing the login over.
    try {
      final offlineSession = session.copyWith(token: '').toJson();
      final credential = await Isolate.run(() => OfflineCredential.create(email: email, password: password, session: offlineSession));
      await store.saveOfflineCredential(credential);
    } catch (_) {}
    state = AsyncData(session);
  }

  Future<void> _loginOffline({required String email, required String password, required ApiException networkError}) async {
    final store = ref.read(secureStoreProvider);
    final credential = await store.offlineCredential();
    if (credential == null || credential.email != email.trim().toLowerCase()) {
      throw ApiException('Sin conexión con el servidor. Sin señal solo puede entrar el último usuario que trabajó en este teléfono.');
    }
    if (credential.locked) {
      throw ApiException('Demasiados intentos sin conexión. Conéctate a internet para entrar.');
    }

    final matches = await Isolate.run(() => credential.matches(email, password));
    if (!matches) {
      final failed = credential.withFailedAttempt();
      await store.saveOfflineCredential(failed);
      final left = OfflineCredential.maxAttempts - failed.failedAttempts;
      throw ApiException(left > 0 ? 'Contraseña incorrecta. Te quedan $left intentos sin conexión.' : 'Demasiados intentos sin conexión. Conéctate a internet para entrar.');
    }

    final session = Session.fromJson(credential.session).copyWith(needsReauth: true);
    await store.saveOfflineCredential(OfflineCredential.fromJson({...credential.toJson(), 'failed_attempts': 0}));
    await store.saveSession(session);
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

  /// First step of signing out: send what is pending and close the token on the server.
  /// Never keeps the user waiting; without signal the queue stays for the next login.
  Future<void> prepareLogout() async {
    final session = state.value;
    if (session == null || !session.canSync) return;
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
  /// [forgetCredential] also removes entering without signal (blocked phone).
  Future<void> endSession({bool forgetCredential = false}) async {
    final store = ref.read(secureStoreProvider);
    try {
      await cancelBackgroundSync().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await store.clearSession().timeout(const Duration(seconds: 5));
      if (forgetCredential) await store.clearOfflineCredential().timeout(const Duration(seconds: 5));
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
  Timer? _heartbeat;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  AppLifecycleListener? _lifecycle;

  @override
  SyncStatus build() {
    final engine = ref.watch(syncEngineProvider);
    // Each build owns what it starts; clear it so a rebuild (session change) never releases it twice.
    ref.onDispose(() {
      _timer?.cancel();
      _heartbeat?.cancel();
      _connectivity?.cancel();
      _lifecycle?.dispose();
      _timer = null;
      _heartbeat = null;
      _connectivity = null;
      _lifecycle = null;
    });

    if (engine != null) {
      _timer = Timer.periodic(interval, (_) => sync());
      _connectivity = Connectivity().onConnectivityChanged.listen((results) {
        if (!results.contains(ConnectivityResult.none)) sync();
      });
      _markForeground(true);
      _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) => _markForeground(true));
      _lifecycle = AppLifecycleListener(
        onResume: () {
          _markForeground(true);
          sync();
        },
        onPause: () => _markForeground(false),
      );
      Future(() async {
        try {
          await scheduleBackgroundSync();
        } catch (_) {
          // Not available on this platform (tests); the app still syncs while open.
        }
      });
      Future.microtask(sync);
    }
    return const SyncStatus();
  }

  /// Tells the background task the app is open (it then stays out of the way) or not.
  void _markForeground(bool open) {
    ref.read(databaseProvider).writeState(foregroundHeartbeatKey, open ? DateTime.now().toIso8601String() : null).catchError((_) {});
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
      if (report.ok && !pushOnly) {
        await ref.read(sessionProvider.notifier).renewIfDue().catchError((_) {});
      }
    } on DeviceRevokedException catch (error) {
      state = SyncStatus(notice: error.message);
      await ref.read(sessionProvider.notifier).endSession(forgetCredential: true);
    } on SessionExpiredException {
      // Not signed out: the user keeps working and enters the password to send what is pending.
      state = const SyncStatus();
      await ref.read(sessionProvider.notifier).markNeedsReauth();
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

/// Sellable catalog on the phone, by name.
final productsProvider = Provider<List<LocalProduct>>((ref) {
  final records = ref.watch(localRecordsProvider('products')).value ?? const [];
  return [
    for (final json in records)
      if (json['deleted'] != true) LocalProduct.fromJson(json),
  ].where((product) => product.isActive && product.sellablePresentations.isNotEmpty).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// Stock available to sell per product (base units) in the default warehouse, minus what
/// orders recorded on the phone already reserve and the last download does not show yet.
final availableStockProvider = Provider<Map<String, DecimalValue>>((ref) {
  final warehouseId = ref.watch(manifestProvider).value?.defaultWarehouse?['id']?.toString();
  final stocks = ref.watch(localRecordsProvider('stocks')).value ?? const [];
  final outbox = ref.watch(outboxRowsProvider).value ?? const [];
  final pulledAt = DateTime.tryParse(ref.watch(syncStateProvider('pulled_at:stocks')).value ?? '');
  final products = {for (final product in ref.watch(productsProvider)) for (final p in product.presentations) p.id: (product.id, p.conversionFactor)};

  final available = <String, DecimalValue>{
    for (final json in stocks)
      if (warehouseId == null || json['warehouse_id']?.toString() == warehouseId) json['product_id'].toString(): LocalStock.fromJson(json).available,
  };
  for (final operation in outbox) {
    if (operation.type != 'order.create' || operation.status == OutboxStatus.rejected) continue;
    if (operation.status == OutboxStatus.done && pulledAt != null && !(operation.processedAt?.isAfter(pulledAt) ?? false)) continue;
    final payload = decodeRecord(operation.payload);
    for (final item in payload['items'] as List? ?? const []) {
      final presentation = products[(item as Map)['product_presentation_id']?.toString()];
      if (presentation == null) continue;
      final used = DecimalValue.parse(item['quantity']) * presentation.$2;
      available[presentation.$1] = (available[presentation.$1] ?? DecimalValue.zero) - used;
    }
  }
  return available;
});

/// A stop of the customer to tie an order to: today's, or any other of the preventista's routes.
final routeStopForCustomerProvider = Provider.family<String?, String>((ref, customerId) {
  final today = ref.watch(dailyRouteProvider).value?.stops.where((stop) => stop.customer.id == customerId).firstOrNull;
  if (today != null) return today.routeStopId;
  for (final route in ref.watch(localRecordsProvider('routes')).value ?? const <Map<String, dynamic>>[]) {
    for (final stop in route['stops'] as List? ?? const []) {
      if ((stop as Map)['customer_id']?.toString() == customerId) return stop['id'].toString();
    }
  }
  for (final operation in ref.watch(outboxRowsProvider).value ?? const <OutboxData>[]) {
    if (operation.type != 'customer.create' || operation.status == OutboxStatus.rejected) continue;
    final payload = decodeRecord(operation.payload);
    if (payload['id']?.toString() == customerId) return (payload['route_stop'] as Map?)?['id']?.toString();
  }
  return null;
});

/// Every operation on the phone explained for the user, newest first.
final operationViewsProvider = Provider<List<OperationView>>((ref) {
  final rows = ref.watch(outboxRowsProvider).value ?? const <OutboxData>[];
  final status = ref.watch(syncProvider);
  final offline = status.lastReport?.error?.isNetwork ?? false;
  return [
    for (final row in rows.reversed) OperationView.of(row, sending: status.running && row.status == OutboxStatus.pending, offline: offline),
  ];
});

/// Seconds the phone clock is off from the server (positive: the phone is behind).
final clockOffsetProvider = Provider<int?>((ref) => int.tryParse(ref.watch(syncStateProvider('clock_offset_seconds')).value ?? ''));
