import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/decimal_value.dart';
import '../data/product_counts.dart';

final localCountsProvider = Provider<List<LocalCount>>((ref) => localCounts(ref.watch(outboxRowsProvider).value ?? const []));

final countActionsProvider = Provider<CountActions>((ref) => CountActions(ref));

class CountActions {
  CountActions(this._ref);

  final Ref _ref;

  /// Records what was counted now; the server compares it with the stock at this moment.
  Future<void> record({required String productId, required String productName, required String warehouseId, required DecimalValue counted, String? notes}) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null) throw StateError('La sesión se cerró. Inicia sesión de nuevo.');
    final at = DateTime.now();
    await _ref.read(outboxProvider).enqueue(
      deviceCode: session.deviceCode,
      type: 'inventory.product_count',
      summary: 'Conteo de $productName',
      build: (_) async => {
        'warehouse_id': warehouseId,
        'product_id': productId,
        'counted_quantity': counted.toString(),
        // UTC with its zone, so the server never reads it in another time zone.
        'counted_at': at.toUtc().toIso8601String(),
        'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      },
    );
    _ref.read(syncProvider.notifier).sync(pushOnly: true);
  }
}
