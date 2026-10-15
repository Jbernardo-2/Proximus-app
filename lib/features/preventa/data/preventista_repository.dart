import 'dart:convert';

import '../../../core/decimal_value.dart';
import '../../../data/database.dart';
import 'preventa_models.dart';

/// The route as the preventista should see it right now: what the server sent
/// plus what was recorded on the phone and is not reflected there yet.
final class DailyRoute {
  const DailyRoute({required this.stops, required this.date, required this.today});

  final List<LocalRouteActivity> stops;

  /// Day the downloaded route belongs to; null when nothing was downloaded.
  final String? date;
  final String today;

  /// Routes of the day in the order their stops are listed.
  List<String> get routeNames => stops.map((stop) => stop.routeName).toSet().toList();

  /// The route on the phone is from another day (e.g. synced yesterday, no signal today).
  bool get isStale => date != null && date != today;

  List<LocalRouteActivity> get pendingStops => stops.where((stop) => !stop.isCompleted).toList();
  List<LocalRouteActivity> get visitedStops => stops.where((stop) => stop.isCompleted).toList();

  int get attended => stops.where((stop) => stop.isCompleted).length;
  int get pending => stops.length - attended;
  int get withOrder => stops.where((stop) => stop.activity.hasOrder).length;
  int get withNoSale => stops.where((stop) => stop.activity.hasNoSale && !stop.activity.hasOrder).length;
  DecimalValue get sold => stops.fold(DecimalValue.zero, (total, stop) => total + stop.activity.ordersTotal);
  DecimalValue get collected => stops.fold(DecimalValue.zero, (total, stop) => total + stop.activity.paymentsTotal);
  double get progress => stops.isEmpty ? 0 : attended / stops.length;
}

final class PreventistaRepository {
  const PreventistaRepository();

  static const _routeOperations = {'customer.create', 'order.create', 'visit.no_sale', 'customer.payment'};

  DailyRoute mergeRouteActivity({
    required List<Map<String, dynamic>> records,
    required List<OutboxData> outbox,
    required DateTime? pulledAt,
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final stops = <String, LocalRouteActivity>{
      for (final record in records) record['route_stop_id'].toString(): LocalRouteActivity.fromJson(record),
    };
    final routeDate = records.isEmpty ? null : records.first['date'] as String?;

    for (final operation in outbox) {
      if (!_routeOperations.contains(operation.type)) continue;
      // Accepted before the last download: the server data already includes it.
      if (operation.status == OutboxStatus.done && pulledAt != null && !(operation.processedAt?.isAfter(pulledAt) ?? false)) {
        continue;
      }
      final payload = (jsonDecode(operation.payload) as Map).cast<String, dynamic>();

      if (operation.type == 'customer.create') {
        final stop = _newCustomerStop(payload, stops.values, routeDate ?? today, now ?? DateTime.now());
        if (stop != null) stops.putIfAbsent(stop.routeStopId, () => stop);
        continue;
      }

      final stopId = payload['route_stop_id']?.toString();
      final current = stopId != null
          ? stops[stopId]
          : stops.values.where((stop) => stop.customer.id == payload['customer_id']?.toString()).firstOrNull;
      if (current == null) continue;

      final rejected = operation.status == OutboxStatus.rejected;
      final result = operation.result == null ? null : (jsonDecode(operation.result!) as Map?)?.cast<String, dynamic>();
      final activity = rejected
          ? current.activity
          : switch (operation.type) {
              'order.create' => current.activity.plus(order: true, orderTotal: orderTotal(payload)),
              'visit.no_sale' => current.activity.plus(noSale: true),
              'customer.payment' => current.activity.plus(payment: true, paymentTotal: DecimalValue.parse(payload['amount'])),
              _ => current.activity,
            };

      stops[current.routeStopId] = current.copyWith(
        activity: activity,
        operationState: _combine(current.operationState, operation.status),
        orderId: operation.type == 'order.create' ? (result?['id'])?.toString() : null,
        orderNumber: operation.type == 'order.create' ? (result?['order_number'] as String?) : null,
        rejectionMessage: rejected ? operation.message : null,
      );
    }

    // A preventista with two routes the same day sees one route after the other.
    final ordered = stops.values.toList()
      ..sort((a, b) {
        final byRoute = a.routeName.compareTo(b.routeName);
        return byRoute != 0 ? byRoute : a.visitOrder.compareTo(b.visitOrder);
      });
    return DailyRoute(stops: ordered, date: routeDate, today: today);
  }

  /// Total of an order payload, exactly as the server will add it up.
  static DecimalValue orderTotal(Map<String, dynamic> payload) => [
        for (final item in payload['items'] as List? ?? const [])
          DecimalValue.parse((item as Map)['quantity']) * DecimalValue.parse(item['unit_price'] ?? '0'),
      ].fold(DecimalValue.zero, (total, line) => total + line);

  /// A customer registered on the phone for today's route shows up as one more stop.
  LocalRouteActivity? _newCustomerStop(Map<String, dynamic> payload, Iterable<LocalRouteActivity> stops, String date, DateTime now) {
    final stop = (payload['route_stop'] as Map?)?.cast<String, dynamic>();
    if (stop == null || stop['id'] == null || (stop['visit_day'] as num?)?.toInt() != now.weekday) return null;
    final routeId = stop['sales_route_id']?.toString() ?? stops.firstOrNull?.routeId ?? '';
    final sameRoute = stops.where((item) => item.routeId == routeId);
    final lastOrder = sameRoute.fold<int>(0, (last, item) => item.visitOrder > last ? item.visitOrder : last);
    return LocalRouteActivity(
      id: stop['id'].toString(),
      date: date,
      routeStopId: stop['id'].toString(),
      routeId: routeId,
      routeName: sameRoute.firstOrNull?.routeName ?? stops.firstOrNull?.routeName ?? '',
      visitOrder: (stop['visit_order'] as num?)?.toInt() ?? lastOrder + 1,
      customer: LocalCustomer.fromJson(payload),
      activity: StopActivity(),
      operationState: LocalOperationState.pending,
    );
  }

  /// Pending wins (something still has to travel), then rejected (needs attention).
  static LocalOperationState _combine(LocalOperationState current, String status) {
    final next = switch (status) {
      OutboxStatus.pending => LocalOperationState.pending,
      OutboxStatus.rejected => LocalOperationState.rejected,
      _ => LocalOperationState.accepted,
    };
    const rank = {
      LocalOperationState.synchronized: 0,
      LocalOperationState.accepted: 1,
      LocalOperationState.rejected: 2,
      LocalOperationState.pending: 3,
    };
    return rank[next]! > rank[current]! ? next : current;
  }

  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

/// Credit of a customer as the preventista should see it now.
final class CustomerBalance {
  const CustomerBalance({required this.allowsCredit, required this.limit, required this.outstanding, required this.overdue, required this.available});

  final bool allowsCredit;
  final DecimalValue limit;
  final DecimalValue outstanding;
  final DecimalValue overdue;
  final DecimalValue available;
}

extension CustomerBalances on PreventistaRepository {
  /// Downloaded credit adjusted by local operations the download does not include yet:
  /// a payment lowers the debt and frees credit; a credit order uses credit.
  Map<String, CustomerBalance> balances({
    required List<Map<String, dynamic>> credits,
    required List<OutboxData> outbox,
    required DateTime? pulledAt,
  }) {
    final paid = <String, DecimalValue>{};
    final ordered = <String, DecimalValue>{};

    for (final operation in outbox) {
      if (operation.status == OutboxStatus.rejected) continue;
      if (operation.status == OutboxStatus.done && pulledAt != null && !(operation.processedAt?.isAfter(pulledAt) ?? false)) continue;
      final payload = (jsonDecode(operation.payload) as Map).cast<String, dynamic>();
      final customerId = payload['customer_id']?.toString();
      if (customerId == null) continue;

      if (operation.type == 'customer.payment') {
        paid[customerId] = (paid[customerId] ?? DecimalValue.zero) + DecimalValue.parse(payload['amount']);
      } else if (operation.type == 'order.create' && payload['payment_term'] == 'credit') {
        ordered[customerId] = (ordered[customerId] ?? DecimalValue.zero) + PreventistaRepository.orderTotal(payload);
      }
    }

    return {
      for (final json in credits)
        json['customer_id'].toString(): () {
          final credit = LocalCustomerCredit.fromJson(json);
          final payments = paid[credit.customerId] ?? DecimalValue.zero;
          final orders = ordered[credit.customerId] ?? DecimalValue.zero;
          final outstanding = credit.outstanding - payments;
          return CustomerBalance(
            allowsCredit: credit.allowsCredit,
            limit: credit.limit,
            outstanding: outstanding.isNegative ? DecimalValue.zero : outstanding,
            overdue: credit.overdue,
            available: credit.available + payments - orders,
          );
        }(),
    };
  }
}
