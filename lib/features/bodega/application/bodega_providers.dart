import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/warehouse_catalog.dart';
import 'warehouse_run_actions.dart';

/// The catalog kept on the phone (names, photos, barcodes) with the stock read live;
/// the last downloaded stock shows only until the server answers.
final warehouseProductsProvider = Provider.autoDispose<List<WarehouseProduct>>((ref) => warehouseProducts(
      products: ref.watch(localRecordsProvider('products')).value ?? const [],
      stocks: ref.watch(liveResourceProvider('stocks')).value ?? ref.watch(localRecordsProvider('stocks')).value ?? const [],
    ));

final warehouseProductProvider = Provider.autoDispose.family<WarehouseProduct?, String>(
  (ref, productId) => ref.watch(warehouseProductsProvider).where((item) => item.product.id == productId).firstOrNull,
);

/// Active warehouses by id, the default first; the default one alone until they are read.
final warehouseNamesProvider = Provider.autoDispose<Map<String, String>>((ref) {
  final records = ref.watch(liveResourceProvider('warehouses')).value ?? const <Map<String, dynamic>>[];
  final fallback = ref.watch(manifestProvider).value?.defaultWarehouse;
  final sorted = [...records]..sort((a, b) => (b['is_default'] == true ? 1 : 0) - (a['is_default'] == true ? 1 : 0));
  return {
    for (final warehouse in sorted) warehouse['id'].toString(): warehouse['name']?.toString() ?? '',
    if (records.isEmpty && fallback != null) fallback['id'].toString(): fallback['name']?.toString() ?? 'Bodega',
  };
});

/// What waits for the warehouse; null until the server answers.
final warehouseWorkProvider = Provider.autoDispose<WarehouseWork?>((ref) {
  final session = ref.watch(sessionProvider).value;
  final runs = ref.watch(warehouseRunsProvider).value;
  final orders = ref.watch(availableOrdersProvider).value;
  if (session == null || runs == null || orders == null) return null;
  return WarehouseWork.of(runs: runs, ordersWaiting: orders.length, userId: session.userId);
});
