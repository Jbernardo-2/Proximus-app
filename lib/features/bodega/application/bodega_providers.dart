import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/warehouse_catalog.dart';
import 'warehouse_run_actions.dart';

final warehouseProductsProvider = Provider<List<WarehouseProduct>>((ref) => warehouseProducts(
      products: ref.watch(localRecordsProvider('products')).value ?? const [],
      stocks: ref.watch(localRecordsProvider('stocks')).value ?? const [],
    ));

final warehouseProductProvider = Provider.family<WarehouseProduct?, String>(
  (ref, productId) => ref.watch(warehouseProductsProvider).where((item) => item.product.id == productId).firstOrNull,
);

/// Active warehouses by id, the default first; the default one alone when they were not downloaded.
final warehouseNamesProvider = Provider<Map<String, String>>((ref) {
  final records = ref.watch(localRecordsProvider('warehouses')).value ?? const [];
  final fallback = ref.watch(manifestProvider).value?.defaultWarehouse;
  final sorted = [...records]..sort((a, b) => (b['is_default'] == true ? 1 : 0) - (a['is_default'] == true ? 1 : 0));
  return {
    for (final warehouse in sorted) warehouse['id'].toString(): warehouse['name']?.toString() ?? '',
    if (records.isEmpty && fallback != null) fallback['id'].toString(): fallback['name']?.toString() ?? 'Bodega',
  };
});

final warehouseWorkProvider = Provider<WarehouseWork?>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null) return null;
  return WarehouseWork.of(runs: ref.watch(warehouseRunsProvider), ordersWaiting: ref.watch(availableOrdersProvider).length, userId: session.userId);
});
