import 'dart:convert';

import '../../../core/decimal_value.dart';
import '../../../data/database.dart';
import 'preventa_models.dart';
import 'preventista_repository.dart';

/// Everything the phone knows about one customer, including what was recorded
/// here and not reflected by the last download yet.
final class CustomerProfile {
  const CustomerProfile({
    required this.customer,
    required this.balance,
    required this.receivables,
    required this.orders,
    this.todayStop,
  });

  final LocalCustomer customer;
  final CustomerBalance? balance;
  final List<LocalReceivable> receivables;
  final List<LocalOrderSummary> orders;

  /// The customer's stop on today's route, if it has one.
  final LocalRouteActivity? todayStop;

  DecimalValue get openDebt => receivables.fold(DecimalValue.zero, (total, debt) => total + debt.outstanding);
}

/// Sources already decoded from the local database, as the profile needs them.
final class CustomerSources {
  const CustomerSources({
    required this.customers,
    required this.credits,
    required this.receivables,
    required this.orders,
    required this.outbox,
    required this.pulledAt,
    this.route,
  });

  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> credits;
  final List<Map<String, dynamic>> receivables;
  final List<Map<String, dynamic>> orders;
  final List<OutboxData> outbox;

  /// Last download time per resource.
  final Map<String, DateTime?> pulledAt;
  final DailyRoute? route;
}

extension CustomerProfiles on PreventistaRepository {
  /// Customers the preventista can work with: downloaded ones plus those registered here.
  List<LocalCustomer> customers(CustomerSources sources) {
    final byId = {for (final json in sources.customers) json['id'].toString(): LocalCustomer.fromJson(json)};
    for (final operation in sources.outbox) {
      if (operation.type != 'customer.create' || operation.status == OutboxStatus.rejected) continue;
      final payload = (jsonDecode(operation.payload) as Map).cast<String, dynamic>();
      byId.putIfAbsent(payload['id'].toString(), () => LocalCustomer.fromJson(payload));
    }
    return byId.values.toList()..sort((a, b) => a.businessName.toLowerCase().compareTo(b.businessName.toLowerCase()));
  }

  CustomerProfile? customerProfile(String customerId, CustomerSources sources) {
    final stop = sources.route?.stops.where((item) => item.customer.id == customerId).firstOrNull;
    final customer = customers(sources).where((item) => item.id == customerId).firstOrNull ?? stop?.customer;
    if (customer == null) return null;

    return CustomerProfile(
      customer: customer,
      balance: balances(credits: sources.credits, outbox: sources.outbox, pulledAt: sources.pulledAt['customer_credit'])[customerId],
      receivables: _receivables(customerId, sources),
      orders: _orders(customerId, sources),
      todayStop: stop,
    );
  }

  /// Open debts minus what the phone already applied to each one.
  List<LocalReceivable> _receivables(String customerId, CustomerSources sources) {
    final applied = <String, DecimalValue>{};
    for (final operation in _notYetDownloaded(sources.outbox, 'customer.payment', sources.pulledAt['receivables'])) {
      final payload = (jsonDecode(operation.payload) as Map).cast<String, dynamic>();
      if (payload['customer_id']?.toString() != customerId) continue;
      for (final allocation in payload['allocations'] as List? ?? const []) {
        final id = (allocation as Map)['receivable_id'].toString();
        applied[id] = (applied[id] ?? DecimalValue.zero) + DecimalValue.parse(allocation['amount']);
      }
    }

    final debts = <LocalReceivable>[];
    for (final json in sources.receivables) {
      if (json['customer_id']?.toString() != customerId) continue;
      final debt = LocalReceivable.fromJson(json);
      final left = debt.outstanding - (applied[debt.id] ?? DecimalValue.zero);
      if (left.isNegative || left.isZero) continue;
      debts.add(LocalReceivable(
        id: debt.id,
        customerId: debt.customerId,
        documentNumber: debt.documentNumber,
        originalAmount: debt.originalAmount,
        outstanding: left,
        isOverdue: debt.isOverdue,
        issuedAt: debt.issuedAt,
        dueDate: debt.dueDate,
      ));
    }
    return debts..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));
  }

  /// Downloaded orders plus the ones still on the phone (or rejected), newest first.
  List<LocalOrderSummary> _orders(String customerId, CustomerSources sources) {
    final orders = [
      for (final json in sources.orders)
        if (json['customer_id']?.toString() == customerId) LocalOrderSummary.fromJson(json),
    ];
    final known = {for (final order in orders) order.clientReference};

    for (final operation in sources.outbox) {
      if (operation.type != 'order.create') continue;
      final payload = (jsonDecode(operation.payload) as Map).cast<String, dynamic>();
      if (payload['customer_id']?.toString() != customerId || known.contains(operation.clientReference)) continue;
      if (operation.status == OutboxStatus.done && !_isAfter(operation.processedAt, sources.pulledAt['recent_orders'])) continue;

      final result = operation.result == null ? null : (jsonDecode(operation.result!) as Map?)?.cast<String, dynamic>();
      orders.add(LocalOrderSummary(
        id: result?['id']?.toString(),
        customerId: customerId,
        orderNumber: result?['order_number'] as String?,
        clientReference: operation.clientReference,
        orderDate: DateTime.tryParse(payload['order_date']?.toString() ?? '') ?? operation.createdAt,
        status: operation.status,
        statusLabel: switch (operation.status) {
          OutboxStatus.pending => 'Por enviar',
          OutboxStatus.rejected => 'Rechazado',
          _ => 'Enviado',
        },
        paymentTerm: payload['payment_term']?.toString() ?? 'cash',
        total: PreventistaRepository.orderTotal(payload),
        itemsCount: (payload['items'] as List? ?? const []).length,
        state: switch (operation.status) {
          OutboxStatus.pending => LocalOperationState.pending,
          OutboxStatus.rejected => LocalOperationState.rejected,
          _ => LocalOperationState.accepted,
        },
        rejectionMessage: operation.status == OutboxStatus.rejected ? operation.message : null,
      ));
    }

    return orders..sort((a, b) => b.orderDate.compareTo(a.orderDate));
  }

  static Iterable<OutboxData> _notYetDownloaded(List<OutboxData> outbox, String type, DateTime? pulledAt) => outbox.where(
        (operation) =>
            operation.type == type &&
            operation.status != OutboxStatus.rejected &&
            (operation.status == OutboxStatus.pending || _isAfter(operation.processedAt, pulledAt)),
      );

  static bool _isAfter(DateTime? processedAt, DateTime? pulledAt) => pulledAt == null || (processedAt?.isAfter(pulledAt) ?? false);
}
