import 'dart:convert';

import '../../../core/decimal_value.dart';
import '../../../data/database.dart';
import 'delivery_models.dart';

/// Goods coming back to the warehouse for one product.
typedef ClosingReturn = ({String product, String presentation, DecimalValue returned, DecimalValue damaged, DecimalValue missing});

/// What the driver hands to the supervisor at the end of a run: the money by method,
/// the credit given, the goods coming back and what is still open. Settlement itself
/// stays on the web; this is the driver's own count, built from the phone.
final class RunClosing {
  const RunClosing({
    required this.delivered,
    required this.partial,
    required this.notDelivered,
    required this.open,
    required this.deliveries,
    required this.accountPayments,
    required this.accountPaymentCount,
    required this.credit,
    required this.returns,
    required this.unsent,
    required this.rejected,
  });

  factory RunClosing.of(LocalDeliveryRun run, List<OutboxData> outbox, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final customers = {for (final stop in run.stops) stop.customerId};
    final deliveries = <String, DecimalValue>{};
    final accountPayments = <String, DecimalValue>{};
    final returns = <String, ClosingReturn>{};
    var count = 0;

    void add(Map<String, DecimalValue> into, String method, DecimalValue amount) => into[method] = (into[method] ?? DecimalValue.zero) + amount;

    for (final stop in run.stops) {
      for (final payment in stop.payments) {
        add(deliveries, payment.method, payment.amount);
      }
      for (final item in stop.items) {
        final returned = item.returned ?? DecimalValue.zero;
        final damaged = item.damaged ?? DecimalValue.zero;
        final missing = item.missing ?? DecimalValue.zero;
        if (returned.isZero && damaged.isZero && missing.isZero) continue;
        final key = '${item.productId}|${item.presentationName}';
        final before = returns[key];
        returns[key] = (
          product: item.productName,
          presentation: item.presentationName,
          returned: (before?.returned ?? DecimalValue.zero) + returned,
          damaged: (before?.damaged ?? DecimalValue.zero) + damaged,
          missing: (before?.missing ?? DecimalValue.zero) + missing,
        );
      }
    }

    // Account payments taken from the customers of this run since it left, as the web
    // counts them at settlement (before the departure reaches the server: since today).
    final since = run.departedAt?.toLocal() ?? DateTime(today.year, today.month, today.day);
    for (final row in outbox) {
      if (row.type != 'customer.payment' || row.status == OutboxStatus.rejected) continue;
      if (row.createdAt.isBefore(since)) continue;
      final payload = (jsonDecode(row.payload) as Map).cast<String, dynamic>();
      if (!customers.contains(payload['customer_id']?.toString())) continue;
      count++;
      for (final line in (payload['payment_lines'] as List? ?? const []).cast<Map>()) {
        add(accountPayments, line['method'].toString(), DecimalValue.parse(line['amount'] ?? '0'));
      }
    }

    return RunClosing(
      delivered: run.stops.where((stop) => stop.status == 'delivered').length,
      partial: run.stops.where((stop) => stop.status == 'partially_delivered').length,
      notDelivered: run.stops.where((stop) => stop.status == 'not_delivered').length,
      open: run.pendingStops.length,
      deliveries: deliveries,
      accountPayments: accountPayments,
      accountPaymentCount: count,
      credit: run.stops.fold(DecimalValue.zero, (sum, stop) => sum + stop.creditGranted),
      returns: returns.values.toList()..sort((a, b) => a.product.compareTo(b.product)),
      unsent: outbox.where((row) => row.status == OutboxStatus.pending).length,
      rejected: outbox.where((row) => row.status == OutboxStatus.rejected).length,
    );
  }

  final int delivered;
  final int partial;
  final int notDelivered;

  /// Stops still to deliver or to collect.
  final int open;

  /// Collected for deliveries, and for account payments, by method.
  final Map<String, DecimalValue> deliveries;
  final Map<String, DecimalValue> accountPayments;
  final int accountPaymentCount;
  final DecimalValue credit;
  final List<ClosingReturn> returns;

  /// Operations still on the phone, or rejected: the count is not final until they are sorted out.
  final int unsent;
  final int rejected;

  /// Every method used, deliveries and account payments together.
  Map<String, DecimalValue> get byMethod {
    final total = <String, DecimalValue>{...deliveries};
    accountPayments.forEach((method, amount) => total[method] = (total[method] ?? DecimalValue.zero) + amount);
    return total;
  }

  /// The cash the driver must hand over.
  DecimalValue get cash => byMethod['cash'] ?? DecimalValue.zero;
  DecimalValue get collected => byMethod.values.fold(DecimalValue.zero, (sum, amount) => sum + amount);
  bool get isFinal => open == 0 && unsent == 0 && rejected == 0;
}
