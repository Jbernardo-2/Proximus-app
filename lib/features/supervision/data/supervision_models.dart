import '../../../core/decimal_value.dart';

DecimalValue _d(Object? value) => value == null ? DecimalValue.zero : DecimalValue.parse(value);

/// The day at a glance, as the web dashboard shows it to management.
final class ManagementPanel {
  const ManagementPanel({required this.sold, required this.collected, required this.credit, required this.overdue, required this.overdueCustomers, required this.pending, required this.runs});

  factory ManagementPanel.fromJson(Map<String, dynamic> json) {
    final today = (json['today'] as Map?) ?? const {};
    final receivables = (json['receivables'] as Map?) ?? const {};
    return ManagementPanel(
      sold: _d(today['sold']),
      collected: _d(today['collected']),
      credit: _d(today['credit']),
      overdue: _d(receivables['overdue']),
      overdueCustomers: (receivables['overdue_customers'] as num?)?.toInt() ?? 0,
      pending: {for (final item in (json['pending'] as List? ?? const []).cast<Map>()) item['key'].toString(): (item['count'] as num?)?.toInt() ?? 0},
      runs: [for (final run in (json['runs'] as List? ?? const []).cast<Map>()) RunProgress.fromJson(run.cast<String, dynamic>())],
    );
  }

  final DecimalValue sold;
  final DecimalValue collected;
  final DecimalValue credit;
  final DecimalValue overdue;
  final int overdueCustomers;

  /// By key: unassigned_orders, runs_awaiting_settlement, stock_shortages, stock_to_replenish.
  final Map<String, int> pending;
  final List<RunProgress> runs;
}

/// A run on its way: how many stops are done and what came in.
final class RunProgress {
  const RunProgress({required this.id, required this.runNumber, required this.status, required this.statusLabel, required this.driverName, required this.stops, required this.completedStops, required this.delivered, required this.collected, this.lastCompletedAt});

  factory RunProgress.fromJson(Map<String, dynamic> json) => RunProgress(
    id: json['id'].toString(),
    runNumber: json['run_number']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    statusLabel: json['status_label']?.toString() ?? '',
    driverName: json['driver_name']?.toString() ?? '',
    stops: (json['stops'] as num?)?.toInt() ?? 0,
    completedStops: (json['completed_stops'] as num?)?.toInt() ?? 0,
    delivered: _d(json['delivered_total']),
    collected: _d(json['collected_total']),
    lastCompletedAt: DateTime.tryParse(json['last_completed_at']?.toString() ?? '')?.toLocal(),
  );

  final String id;
  final String runNumber;
  final String status;
  final String statusLabel;
  final String driverName;
  final int stops;
  final int completedStops;
  final DecimalValue delivered;
  final DecimalValue collected;
  final DateTime? lastCompletedAt;

  double get progress => stops == 0 ? 0 : completedStops / stops;
  bool get awaitsSettlement => status == 'awaiting_settlement';
}

/// One salesperson's route today.
final class RouteProgress {
  const RouteProgress({required this.id, required this.name, required this.stops, required this.withOrder, required this.noSale, required this.pending, required this.sold, required this.collected, this.lastActivityAt});

  factory RouteProgress.fromJson(Map<String, dynamic> json) => RouteProgress(
    id: (json['id'] as num).toInt(),
    name: json['name']?.toString() ?? '',
    stops: (json['stops'] as num?)?.toInt() ?? 0,
    withOrder: (json['with_order'] as num?)?.toInt() ?? 0,
    noSale: (json['no_sale'] as num?)?.toInt() ?? 0,
    pending: (json['pending'] as num?)?.toInt() ?? 0,
    sold: _d(json['sold']),
    collected: _d(json['collected']),
    lastActivityAt: DateTime.tryParse(json['last_activity_at']?.toString() ?? '')?.toLocal(),
  );

  final int id;
  final String name;
  final int stops;
  final int withOrder;
  final int noSale;
  final int pending;
  final DecimalValue sold;
  final DecimalValue collected;
  final DateTime? lastActivityAt;

  int get visited => stops - pending;
  double get progress => stops == 0 ? 0 : visited / stops;
}

/// A stop of a salesperson's route, as their phone reports it.
final class RouteStopActivity {
  const RouteStopActivity({required this.visitOrder, required this.customerName, required this.status, required this.ordersTotal, required this.paymentsTotal, this.activityAt, this.noSaleReason});

  factory RouteStopActivity.fromJson(Map<String, dynamic> json) => RouteStopActivity(
    visitOrder: (json['visit_order'] as num?)?.toInt() ?? 0,
    customerName: (json['customer'] as Map?)?['business_name']?.toString() ?? '',
    status: json['status']?.toString() ?? 'pending',
    ordersTotal: _d(json['orders_total']),
    paymentsTotal: _d(json['payments_total']),
    activityAt: DateTime.tryParse(json['activity_at']?.toString() ?? '')?.toLocal(),
    noSaleReason: (json['visit'] as Map?)?['type_label']?.toString(),
  );

  final int visitOrder;
  final String customerName;

  /// order_taken, no_sale, visited or pending.
  final String status;
  final DecimalValue ordersTotal;
  final DecimalValue paymentsTotal;
  final DateTime? activityAt;
  final String? noSaleReason;
}

/// What a run hands over at settlement, read from the run as the server sends it.
final class SettlementView {
  const SettlementView({
    required this.runId,
    required this.runNumber,
    required this.driverName,
    required this.delivered,
    required this.collected,
    required this.credit,
    required this.cashToReceive,
    required this.accountPaymentCash,
    required this.transfers,
    required this.otherMethods,
    required this.cashOrdersWithBalance,
    required this.returns,
  });

  factory SettlementView.fromJson(Map<String, dynamic> json) {
    final financials = (json['financials'] as Map?) ?? const {};
    final orders = (json['orders'] as List? ?? const []).cast<Map>();
    final returns = <String, ({String product, String presentation, DecimalValue returned, DecimalValue damaged, DecimalValue missing})>{};
    for (final order in orders) {
      for (final item in (order['items'] as List? ?? const []).cast<Map>()) {
        final key = '${item['product_id']}|${item['product_presentation_id']}';
        final previous = returns[key];
        returns[key] = (
          product: item['product_name']?.toString() ?? '',
          presentation: item['presentation_name']?.toString() ?? '',
          returned: (previous?.returned ?? DecimalValue.zero) + _d(item['returned_quantity']),
          damaged: (previous?.damaged ?? DecimalValue.zero) + _d(item['damaged_quantity']),
          missing: (previous?.missing ?? DecimalValue.zero) + _d(item['missing_quantity']),
        );
      }
    }
    return SettlementView(
      runId: json['id'].toString(),
      runNumber: json['run_number']?.toString() ?? '',
      driverName: json['driver_name']?.toString() ?? '',
      delivered: _d(financials['delivered_total']),
      collected: _d(financials['collected_total']),
      credit: _d(financials['credit_total']),
      cashToReceive: _d(financials['cash_expected']),
      accountPaymentCash: _d(financials['account_payment_cash']),
      transfers: _d(financials['transfer_total']),
      otherMethods: _d(financials['card_total']) + _d(financials['check_total']) + _d(financials['other_payment_total']),
      cashOrdersWithBalance: [
        for (final order in orders)
          if ((order['order'] as Map?)?['payment_term'] == 'cash' && !_d(order['balance_due']).isZero && (order['credit_reason']?.toString().trim().isEmpty ?? true))
            (
              runOrderId: order['id'].toString(),
              label: '${(order['order'] as Map?)?['order_number'] ?? ''} · ${(order['order'] as Map?)?['customer_name'] ?? ''}',
              balance: _d(order['balance_due']),
            ),
      ],
      returns: [
        for (final row in returns.values)
          if (!(row.returned.isZero && row.damaged.isZero && row.missing.isZero)) row,
      ],
    );
  }

  final String runId;
  final String runNumber;
  final String driverName;
  final DecimalValue delivered;
  final DecimalValue collected;
  final DecimalValue credit;

  /// Cash the driver hands over: deliveries plus account payments collected on the way.
  final DecimalValue cashToReceive;
  final DecimalValue accountPaymentCash;
  final DecimalValue transfers;
  final DecimalValue otherMethods;
  final List<({String runOrderId, String label, DecimalValue balance})> cashOrdersWithBalance;
  final List<({String product, String presentation, DecimalValue returned, DecimalValue damaged, DecimalValue missing})> returns;

  DecimalValue get deliveryCash => cashToReceive - accountPaymentCash;

  /// Delivered has to be accounted for: collected by every method plus credit.
  bool get balanced => (collected + credit).compareTo(delivered) == 0;

  /// Counted minus expected: negative is missing, positive is extra.
  DecimalValue difference(DecimalValue counted) => counted - cashToReceive;
}

/// A customer in the credit portfolio: what they owe and how much is past due.
final class PortfolioRow {
  const PortfolioRow({required this.customerId, required this.code, required this.name, required this.outstanding, required this.overdue, required this.committed});

  factory PortfolioRow.fromJson(Map<String, dynamic> json) => PortfolioRow(
    customerId: json['customer_id'].toString(),
    code: json['code']?.toString() ?? '',
    name: json['business_name']?.toString() ?? '',
    outstanding: _d(json['outstanding_balance']),
    overdue: _d(json['overdue_balance']),
    committed: _d(json['committed_credit']),
  );

  final String customerId;
  final String code;
  final String name;
  final DecimalValue outstanding;
  final DecimalValue overdue;

  /// On credit orders not delivered yet.
  final DecimalValue committed;
}

final class Portfolio {
  const Portfolio({required this.rows, required this.balance, required this.overdue, required this.debtors, required this.hasMore});

  final List<PortfolioRow> rows;
  final DecimalValue balance;
  final DecimalValue overdue;
  final int debtors;
  final bool hasMore;
}
