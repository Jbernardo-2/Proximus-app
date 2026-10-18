import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api.dart';
import '../../../core/decimal_value.dart';
import '../../bodega/application/warehouse_run_actions.dart';
import '../../preventa/data/preventa_models.dart' show AccountEntry, LocalReceivable;
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

/// The credit portfolio, debtors first: [pages] grows as the supervisor asks for more.
final portfolioProvider = FutureProvider.autoDispose.family<Portfolio, ({String search, bool overdue, int pages})>((ref, query) async {
  final api = _api(ref);
  final rows = <PortfolioRow>[];
  Map<String, dynamic> totals = const {};
  var hasMore = false;
  for (var page = 1; page <= query.pages; page++) {
    final response = await api.get('/credits', query: {'search': query.search, if (query.overdue) 'overdue': 1, 'page': page});
    rows.addAll([for (final json in (response['data'] as List).cast<Map>()) PortfolioRow.fromJson(json.cast<String, dynamic>())]);
    totals = (response['totals'] as Map).cast<String, dynamic>();
    final meta = (response['meta'] as Map).cast<String, dynamic>();
    hasMore = (meta['current_page'] as num) < (meta['last_page'] as num);
    if (!hasMore) break;
  }
  return Portfolio(
    rows: rows,
    balance: DecimalValue.parse(totals['portfolio_balance'] ?? '0'),
    overdue: DecimalValue.parse(totals['overdue_balance'] ?? '0'),
    debtors: (totals['debtors_count'] as num?)?.toInt() ?? 0,
    hasMore: hasMore,
  );
});

/// One customer's debts and account movements, read now.
final customerCreditProvider = FutureProvider.autoDispose.family<({List<LocalReceivable> debts, List<AccountEntry> entries}), String>((ref, customerId) async {
  final data = ((await _api(ref).get('/customers/$customerId/credit'))['data'] as Map).cast<String, dynamic>();
  return (
    debts: [for (final json in (data['open_receivables'] as List).cast<Map>()) LocalReceivable.fromJson(json.cast<String, dynamic>())],
    entries: [for (final json in (data['recent_entries'] as List).cast<Map>()) AccountEntry.fromJson(json.cast<String, dynamic>())],
  );
});

/// A run read now, as the server sends it, for its stops to be reviewed.
final runRecordProvider = Provider.autoDispose.family<AsyncValue<Map<String, dynamic>?>, String>(
  (ref, runId) => ref.watch(liveResourceProvider('delivery_runs')).whenData((records) => records.where((run) => run['id'].toString() == runId).firstOrNull),
);

final runCorrectionsProvider = Provider.autoDispose<RunCorrections>((ref) => RunCorrections(ref));

/// What a supervisor fixes on a run before settling it, online.
class RunCorrections {
  RunCorrections(this._ref);

  final Ref _ref;

  Future<void> _send(Future<void> Function(ProximusApi api) call) async {
    await call(_ref.read(apiProvider) ?? (throw ApiException('Sin conexión con el servidor.')));
    _ref.invalidate(liveResourceProvider('delivery_runs'));
    _ref.invalidate(managementPanelProvider);
    _ref.invalidate(fieldActivityProvider);
  }

  Future<void> voidPayment(String runId, String runOrderId, String paymentId, String reason) =>
      _send((api) => api.post('/delivery-runs/$runId/orders/$runOrderId/payments/$paymentId/void', {'reason': reason}));

  /// The stop goes back to the driver, who records it again; the run returns to the road.
  Future<void> reopenStop(String runId, String runOrderId) => _send((api) => api.post('/delivery-runs/$runId/orders/$runOrderId/outcome/reopen'));
}
