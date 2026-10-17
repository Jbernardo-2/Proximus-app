import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api.dart';
import '../../../core/decimal_value.dart';
import '../data/product_counts.dart';
import 'warehouse_run_actions.dart';

/// The latest counts on the server: the keeper's own, everyone's for a supervisor.
final productCountsProvider = FutureProvider.autoDispose<List<ProductCount>>((ref) async {
  final api = ref.watch(apiProvider);
  if (api == null) throw ApiException('Inicia sesión con señal para trabajar en bodega.');
  final response = await api.get('/inventory/product-counts');
  return [for (final json in (response['data'] as List).cast<Map<String, dynamic>>()) ProductCount.fromJson(json)];
});

final countActionsProvider = Provider.autoDispose<CountActions>((ref) => CountActions(ref));

class CountActions {
  CountActions(this._ref);

  final Ref _ref;

  /// Applies the count now, at the server's time, and returns the difference it made.
  Future<ProductCount> record({required String productId, required String warehouseId, required DecimalValue counted, String? notes}) async {
    final api = _ref.read(apiProvider) ?? (throw ApiException('Sin conexión con el servidor.'));
    final response = await api.post('/inventory/product-counts', {
      'warehouse_id': warehouseId,
      'product_id': productId,
      'counted_quantity': counted.toString(),
      'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
    });
    _ref.invalidate(productCountsProvider);
    _ref.invalidate(liveResourceProvider('stocks'));
    return ProductCount.fromJson((response['data'] as Map).cast<String, dynamic>());
  }
}
