import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api.dart';
import '../../../core/decimal_value.dart';
import '../data/warehouse_runs.dart';

/// A resource read from the server right now, every page of it. The warehouse works
/// online: nothing here is kept on the phone.
final liveResourceProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, resource) async {
  final api = ref.watch(apiProvider);
  if (api == null) throw ApiException('Inicia sesión con señal para trabajar en bodega.');
  final records = <Map<String, dynamic>>[];
  String? cursor;
  do {
    final page = await api.pull(resource, cursor: cursor, limit: 500);
    records.addAll((page['records'] as List).cast<Map<String, dynamic>>());
    cursor = page['has_more'] == true ? page['next_cursor'] as String? : null;
  } while (cursor != null);
  return records;
});

final warehouseRunsProvider = Provider.autoDispose<AsyncValue<List<WarehouseRun>>>((ref) => ref.watch(liveResourceProvider('delivery_runs')).whenData(warehouseRuns));

final warehouseRunProvider = Provider.autoDispose.family<AsyncValue<WarehouseRun?>, String>(
  (ref, id) => ref.watch(warehouseRunsProvider).whenData((runs) => runs.where((run) => run.id == id).firstOrNull),
);

final availableOrdersProvider = Provider.autoDispose<AsyncValue<List<DispatchOrder>>>(
  (ref) => ref.watch(liveResourceProvider('dispatch_orders')).whenData((records) => [for (final json in records) dispatchOrderFromJson(json)]),
);

final driversProvider = Provider.autoDispose<Map<String, String>>((ref) => {
  for (final driver in ref.watch(liveResourceProvider('drivers')).value ?? const <Map<String, dynamic>>[]) driver['id'].toString(): driver['name']?.toString() ?? '',
});

final vehiclesProvider = Provider.autoDispose<Map<String, String>>((ref) => {
  for (final vehicle in ref.watch(liveResourceProvider('vehicles')).value ?? const <Map<String, dynamic>>[])
    vehicle['id'].toString(): [vehicle['code'], vehicle['license_plate']].whereType<String>().where((text) => text.isNotEmpty).join(' · '),
});

/// Physical stock per product (base units) of a warehouse, read now.
final liveOnHandProvider = Provider.autoDispose.family<AsyncValue<Map<String, DecimalValue>>, String?>((ref, warehouseId) {
  final fallback = ref.watch(manifestProvider).value?.defaultWarehouse?['id']?.toString();
  return ref.watch(liveResourceProvider('stocks')).whenData((records) => {
    for (final json in records)
      if (json['warehouse_id']?.toString() == (warehouseId ?? fallback)) json['product_id'].toString(): DecimalValue.parse(json['quantity_on_hand'] ?? '0'),
  });
});

final warehouseRunActionsProvider = Provider.autoDispose<WarehouseRunActions>((ref) => WarehouseRunActions(ref));

/// Every step goes to the server and waits for its answer; a refusal comes back as an
/// [ApiException] with the server's message, right when the keeper acts.
class WarehouseRunActions {
  WarehouseRunActions(this._ref);

  final Ref _ref;

  ProximusApi get _api => _ref.read(apiProvider) ?? (throw ApiException('Sin conexión con el servidor.'));

  void _refresh({bool stock = false}) {
    _ref.invalidate(liveResourceProvider('delivery_runs'));
    _ref.invalidate(liveResourceProvider('dispatch_orders'));
    if (stock) _ref.invalidate(liveResourceProvider('stocks'));
  }

  /// Returns the new run's id, so it opens right away.
  Future<String> create({required String warehouseId, required String driverId, String? vehicleId, required DateTime date}) async {
    final response = await _api.post('/delivery-runs', {
      'warehouse_id': warehouseId,
      'driver_id': int.tryParse(driverId) ?? driverId,
      'vehicle_id': vehicleId,
      'scheduled_date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    });
    _refresh();
    return (response['data'] as Map)['id'].toString();
  }

  Future<void> assign(WarehouseRun run, DispatchOrder order) async {
    await _api.post('/delivery-runs/${run.id}/orders', {'order_id': order.order.orderId});
    _refresh();
  }

  Future<void> unassign(WarehouseRun run, RunOrder order) async {
    await _api.delete('/delivery-runs/${run.id}/orders/${order.runOrderId}');
    _refresh();
  }

  Future<void> startPreparation(WarehouseRun run) async {
    await _api.post('/delivery-runs/${run.id}/preparation');
    _refresh(stock: true);
  }

  /// Saves the picked lines; the server refuses what the warehouse does not have.
  Future<void> pick(WarehouseRun run, Map<String, DecimalValue> quantities) async {
    await _api.put('/delivery-runs/${run.id}/picks', {
      'items': [for (final entry in quantities.entries) {'order_item_id': entry.key, 'prepared_quantity': entry.value.toString()}],
    });
    _refresh();
  }

  Future<void> confirmLoad(WarehouseRun run) async {
    await _api.post('/delivery-runs/${run.id}/load');
    _refresh(stock: true);
  }

  void refresh() => _refresh(stock: true);
}
