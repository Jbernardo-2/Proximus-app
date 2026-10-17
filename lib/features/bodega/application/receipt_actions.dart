import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api.dart';
import '../data/receipts.dart';
import 'warehouse_run_actions.dart';

ProximusApi _api(Ref ref) => ref.read(apiProvider) ?? (throw ApiException('Inicia sesión con señal para trabajar en bodega.'));

/// The latest posted entries, read now.
final receiptsProvider = FutureProvider.autoDispose<List<PostedReceipt>>((ref) async {
  ref.watch(apiProvider);
  final response = await _api(ref).get('/inventory/documents', query: {'status': 'posted', 'per_page': 50});
  return postedReceipts((response['data'] as List).cast<Map<String, dynamic>>());
});

final receiptDetailProvider = FutureProvider.autoDispose.family<PostedReceipt, String>((ref, id) async {
  ref.watch(apiProvider);
  final response = await _api(ref).get('/inventory/documents/$id');
  return PostedReceipt.fromJson((response['data'] as Map).cast<String, dynamic>());
});

final suppliersProvider = Provider.autoDispose<Map<String, String>>((ref) => {
  for (final supplier in ref.watch(liveResourceProvider('suppliers')).value ?? const <Map<String, dynamic>>[]) supplier['id'].toString(): supplier['name']?.toString() ?? '',
});

final receiptActionsProvider = Provider.autoDispose<ReceiptActions>((ref) => ReceiptActions(ref));

class ReceiptActions {
  ReceiptActions(this._ref);

  final Ref _ref;

  /// Posts the whole entry at once: the stock goes up now or nothing is saved.
  Future<PostedReceipt> post(Map<String, dynamic> payload) async {
    final response = await _api(_ref).post('/inventory/receipts', payload);
    _ref.invalidate(receiptsProvider);
    _ref.invalidate(liveResourceProvider('stocks'));
    return PostedReceipt.fromJson((response['data'] as Map).cast<String, dynamic>());
  }
}
