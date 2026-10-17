import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/decimal_value.dart';
import '../../../core/ulid.dart';
import '../data/warehouse_runs.dart';

final _merged = Provider<({List<WarehouseRun> runs, List<DispatchOrder> available})>((ref) {
  final pulledAt = ref.watch(syncStateProvider('pulled_at:delivery_runs')).value;
  return mergeWarehouseRuns(
    records: ref.watch(localRecordsProvider('delivery_runs')).value ?? const [],
    dispatchOrders: ref.watch(localRecordsProvider('dispatch_orders')).value ?? const [],
    outbox: ref.watch(outboxRowsProvider).value ?? const [],
    pulledAt: pulledAt == null ? null : DateTime.tryParse(pulledAt),
    drivers: ref.watch(driversProvider),
    userId: ref.watch(sessionProvider).value?.userId ?? 0,
  );
});

final warehouseRunsProvider = Provider<List<WarehouseRun>>((ref) => ref.watch(_merged).runs);

final warehouseRunProvider = Provider.family<WarehouseRun?, String>((ref, id) => ref.watch(warehouseRunsProvider).where((run) => run.id == id).firstOrNull);

final availableOrdersProvider = Provider<List<DispatchOrder>>((ref) => ref.watch(_merged).available);

final driversProvider = Provider<Map<String, String>>((ref) => {
  for (final driver in ref.watch(localRecordsProvider('drivers')).value ?? const <Map<String, dynamic>>[]) driver['id'].toString(): driver['name']?.toString() ?? '',
});

final vehiclesProvider = Provider<Map<String, String>>((ref) => {
  for (final vehicle in ref.watch(localRecordsProvider('vehicles')).value ?? const <Map<String, dynamic>>[])
    vehicle['id'].toString(): [vehicle['code'], vehicle['license_plate']].whereType<String>().where((text) => text.isNotEmpty).join(' · '),
});

/// What the keeper picked on this phone and has not sent yet, kept across restarts.
final pickingDraftProvider = Provider.family<Map<String, DecimalValue>, String>((ref, runId) {
  final saved = ref.watch(syncStateProvider('picking:$runId')).value;
  if (saved == null) return const {};
  return {for (final entry in (jsonDecode(saved) as Map).entries) entry.key.toString(): DecimalValue.parse(entry.value)};
});

final warehouseRunActionsProvider = Provider<WarehouseRunActions>((ref) => WarehouseRunActions(ref));

/// Assembling, picking and loading a run: first on the phone, then sent when there is signal.
class WarehouseRunActions {
  WarehouseRunActions(this._ref);

  final Ref _ref;

  Future<void> _queue(String type, String summary, Map<String, dynamic> payload) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null) throw StateError('La sesión se cerró. Inicia sesión de nuevo.');
    await _ref.read(outboxProvider).enqueue(deviceCode: session.deviceCode, type: type, summary: summary, build: (_) async => payload);
    _ref.read(syncProvider.notifier).sync(pushOnly: true);
  }

  /// Returns the id the phone gave the run, so it opens right away.
  Future<String> create({required String warehouseId, required String driverId, String? vehicleId, required DateTime date, String? notes}) async {
    final id = Ulid.generate();
    await _queue('delivery.create', 'Jornada nueva', {
      'id': id,
      'warehouse_id': warehouseId,
      'driver_id': int.tryParse(driverId) ?? driverId,
      'vehicle_id': vehicleId,
      'scheduled_date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'notes': notes,
    });
    return id;
  }

  Future<void> assign(WarehouseRun run, DispatchOrder order) =>
      _queue('delivery.assign', 'Pedido ${order.order.orderNumber} a ${run.title}', {'delivery_run_id': run.id, 'order_id': order.order.orderId});

  /// An assignment still on the phone is just dropped; one the server has is undone there.
  Future<void> unassign(WarehouseRun run, RunOrder order) async {
    if (order.pendingAssignId != null) {
      await _ref.read(outboxProvider).dismiss(order.pendingAssignId!);
      return;
    }
    if (order.runOrderId == null) throw StateError('Sincroniza antes de quitar este pedido.');
    await _queue('delivery.unassign', 'Quitar ${order.orderNumber} de ${run.title}', {'delivery_run_id': run.id, 'run_order_id': order.runOrderId});
  }

  Future<void> startPreparation(WarehouseRun run) => _queue('delivery.prepare_start', 'Preparar ${run.title}', {'delivery_run_id': run.id});

  Future<void> pick(String runId, Map<String, DecimalValue> quantities) {
    final draft = {..._ref.read(pickingDraftProvider(runId)), ...quantities};
    return _ref.read(databaseProvider).writeState('picking:$runId', jsonEncode({for (final entry in draft.entries) entry.key: entry.value.toString()}));
  }

  /// Sends what was picked so far, so the web and the supervisor see the progress.
  Future<void> savePreparation(WarehouseRun run, Map<String, DecimalValue> quantities) async {
    await _queue('delivery.prepare', 'Preparación de ${run.title}', {
      'delivery_run_id': run.id,
      'items': [for (final entry in quantities.entries) {'order_item_id': entry.key, 'prepared_quantity': entry.value.toString()}],
    });
    await _ref.read(databaseProvider).writeState('picking:${run.id}', null);
  }

  Future<void> confirmLoad(WarehouseRun run, Map<String, DecimalValue> quantities) async {
    await savePreparation(run, quantities);
    await _queue('delivery.load', 'Carga de ${run.title}', {'delivery_run_id': run.id});
  }
}
