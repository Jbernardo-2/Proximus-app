import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api.dart';
import '../../../core/decimal_value.dart';
import '../../bodega/application/warehouse_run_actions.dart';
import '../data/supervision_models.dart';

ProximusApi _api(Ref ref) => ref.watch(apiProvider) ?? (throw ApiException('Inicia sesión con señal para supervisar.'));

/// Supervision works online, like the warehouse: everything is read when the screen opens.
final managementPanelProvider = FutureProvider.autoDispose<ManagementPanel>((ref) async {
  final response = await _api(ref).get('/dashboard');
  return ManagementPanel.fromJson(((response['data'] as Map)['management'] as Map).cast<String, dynamic>());
});

final fieldActivityProvider = FutureProvider.autoDispose<({List<RouteProgress> routes, List<RunProgress> runs})>((ref) async {
  final data = ((await _api(ref).get('/field-activity'))['data'] as Map).cast<String, dynamic>();
  return (
    routes: [for (final json in (data['salespeople'] as List).cast<Map>()) RouteProgress.fromJson(json.cast<String, dynamic>())],
    runs: [for (final json in (data['runs'] as List).cast<Map>()) RunProgress.fromJson(json.cast<String, dynamic>())],
  );
});

final salespersonStopsProvider = FutureProvider.autoDispose.family<List<RouteStopActivity>, int>((ref, userId) async {
  final data = ((await _api(ref).get('/field-activity/salespeople/$userId'))['data'] as Map).cast<String, dynamic>();
  return [for (final json in (data['stops'] as List).cast<Map>()) RouteStopActivity.fromJson(json.cast<String, dynamic>())];
});

/// Runs waiting for their cash to be counted.
final settlementsProvider = Provider.autoDispose<AsyncValue<List<SettlementView>>>((ref) => ref.watch(liveResourceProvider('delivery_runs')).whenData((records) => [
  for (final json in records)
    if (json['status'] == 'awaiting_settlement') SettlementView.fromJson(json),
]));

final settlementProvider = Provider.autoDispose.family<AsyncValue<SettlementView?>, String>(
  (ref, runId) => ref.watch(settlementsProvider).whenData((runs) => runs.where((run) => run.runId == runId).firstOrNull),
);

final settlementActionsProvider = Provider.autoDispose<SettlementActions>((ref) => SettlementActions(ref));

class SettlementActions {
  SettlementActions(this._ref);

  final Ref _ref;

  /// Closes the run with the cash counted; the server computes the difference again.
  Future<void> settle(SettlementView run, {required DecimalValue counted, String? notes, Map<String, String> creditReasons = const {}}) async {
    final api = _ref.read(apiProvider) ?? (throw ApiException('Sin conexión con el servidor.'));
    await api.post('/delivery-runs/${run.runId}/settle', {
      'cash_declared': counted.toString(),
      'settlement_notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      'credit_reasons': {
        for (final entry in creditReasons.entries)
          if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
      },
    });
    _ref.invalidate(liveResourceProvider('delivery_runs'));
    _ref.invalidate(managementPanelProvider);
    _ref.invalidate(fieldActivityProvider);
  }
}
