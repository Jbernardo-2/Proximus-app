import '../../../core/decimal_value.dart';

/// One order line to pick. Keyed by the order line, as the server accepts it.
final class PickLine {
  const PickLine({
    required this.orderItemId,
    required this.productId,
    required this.presentationId,
    required this.productName,
    required this.presentationName,
    required this.requested,
    required this.conversionFactor,
    this.prepared,
  });

  final String orderItemId;
  final String productId;
  final String presentationId;
  final String productName;
  final String presentationName;
  final DecimalValue requested;

  /// Base units per unit of the presentation: the stock is counted in base units.
  final DecimalValue conversionFactor;

  /// What the server holds as picked; null while nobody reviewed the line.
  final DecimalValue? prepared;
}

final class RunOrder {
  const RunOrder({
    required this.orderId,
    required this.orderNumber,
    required this.customerName,
    required this.total,
    required this.lines,
    this.visitOrder = 0,
    this.runOrderId,
    this.routeName,
  });

  final String orderId;
  final String orderNumber;
  final String customerName;
  final String? routeName;
  final DecimalValue total;
  final List<PickLine> lines;

  /// Stop number on the route: when stock is short, earlier stops are filled first.
  final int visitOrder;

  /// The order on the run, to take it off.
  final String? runOrderId;
}

final class WarehouseRun {
  const WarehouseRun({
    required this.id,
    required this.runNumber,
    required this.status,
    required this.warehouseId,
    required this.driverName,
    required this.orders,
    this.scheduledDate,
    this.vehicle,
    this.preparationStartedBy,
  });

  final String id;
  final String runNumber;

  /// draft, preparing or loaded.
  final String status;
  final String? warehouseId;
  final DateTime? scheduledDate;
  final String driverName;
  final String? vehicle;
  final int? preparationStartedBy;
  final List<RunOrder> orders;

  bool get isDraft => status == 'draft';
  bool get isPreparing => status == 'preparing';
  bool get isLoaded => status == 'loaded';

  /// Who may pick it: the keeper who started it, or any supervisor.
  bool preparableBy(int userId, {required bool supervises}) => isPreparing && (supervises || preparationStartedBy == null || preparationStartedBy == userId);

  List<PickLine> get lines => [for (final order in orders) ...order.lines];
}

/// A confirmed order that waits for a run, as the warehouse assigns it.
final class DispatchOrder {
  const DispatchOrder({required this.order, required this.warehouseId, this.requestedDate});

  final RunOrder order;
  final String? warehouseId;
  final DateTime? requestedDate;
}

DecimalValue _d(Object? value) => DecimalValue.parse(value);

DecimalValue _factor(Object? value) => value == null ? DecimalValue.parse('1') : _d(value);

DispatchOrder dispatchOrderFromJson(Map<String, dynamic> json) => DispatchOrder(
  warehouseId: json['warehouse_id']?.toString(),
  requestedDate: DateTime.tryParse(json['requested_delivery_date']?.toString() ?? ''),
  order: RunOrder(
    orderId: json['id'].toString(),
    orderNumber: json['order_number']?.toString() ?? '',
    customerName: json['customer_name']?.toString() ?? '',
    routeName: json['route_name']?.toString(),
    total: _d(json['total']),
    lines: [
      for (final item in (json['items'] as List? ?? const []).cast<Map>())
        PickLine(
          orderItemId: item['id'].toString(),
          productId: item['product_id'].toString(),
          presentationId: item['product_presentation_id'].toString(),
          productName: item['product_name']?.toString() ?? '',
          presentationName: item['presentation_name']?.toString() ?? '',
          requested: _d(item['quantity']),
          conversionFactor: _factor(item['conversion_factor']),
        ),
    ],
  ),
);

/// A run as the server sends it (sync pull or any delivery run response).
WarehouseRun warehouseRunFromJson(Map<String, dynamic> json) {
  final orders = [
    for (final stop in (json['orders'] as List? ?? const []).cast<Map>())
      RunOrder(
        runOrderId: stop['id'].toString(),
        visitOrder: (stop['visit_order'] as num?)?.toInt() ?? 0,
        orderId: (stop['order'] as Map?)?['id']?.toString() ?? '',
        orderNumber: (stop['order'] as Map?)?['order_number']?.toString() ?? '',
        customerName: (stop['order'] as Map?)?['customer_name']?.toString() ?? '',
        routeName: (stop['order'] as Map?)?['route_name']?.toString(),
        total: _d(stop['requested_total']),
        lines: [
          for (final item in (stop['items'] as List? ?? const []).cast<Map>())
            PickLine(
              orderItemId: item['order_item_id'].toString(),
              productId: item['product_id'].toString(),
              presentationId: item['product_presentation_id'].toString(),
              productName: item['product_name']?.toString() ?? '',
              presentationName: item['presentation_name']?.toString() ?? '',
              requested: _d(item['requested_quantity']),
              conversionFactor: _factor(item['conversion_factor']),
              prepared: item['picked_at'] == null ? null : _d(item['prepared_quantity']),
            ),
        ],
      ),
  ]..sort((a, b) => a.visitOrder.compareTo(b.visitOrder));
  return WarehouseRun(
    id: json['id'].toString(),
    runNumber: json['run_number']?.toString() ?? '',
    status: json['status']?.toString() ?? 'draft',
    warehouseId: (json['warehouse'] as Map?)?['id']?.toString(),
    scheduledDate: DateTime.tryParse(json['scheduled_date']?.toString() ?? ''),
    driverName: json['driver_name']?.toString() ?? (json['driver'] as Map?)?['name']?.toString() ?? '',
    vehicle: json['vehicle_license_plate']?.toString() ?? json['vehicle_code']?.toString(),
    preparationStartedBy: (json['preparation_started_by'] as num?)?.toInt(),
    orders: orders,
  );
}

/// The runs the warehouse works on, in the order it works them.
List<WarehouseRun> warehouseRuns(List<Map<String, dynamic>> records) {
  const stage = {'draft': 0, 'preparing': 1, 'loaded': 2};
  return [
    for (final json in records)
      if (stage.containsKey(json['status'])) warehouseRunFromJson(json),
  ]..sort((a, b) => stage[a.status]!.compareTo(stage[b.status]!));
}

/// Lines of the same presentation picked together, across the orders of the run.
final class PickGroup {
  const PickGroup({required this.presentationId, required this.productId, required this.productName, required this.presentationName, required this.lines});

  final String presentationId;
  final String productId;
  final String productName;
  final String presentationName;

  /// With the order each line belongs to.
  final List<({RunOrder order, PickLine line})> lines;

  DecimalValue get requested => lines.fold(DecimalValue.zero, (total, entry) => total + entry.line.requested);

  /// Null while any line is still unreviewed.
  DecimalValue? get prepared {
    var total = DecimalValue.zero;
    for (final entry in lines) {
      final value = entry.line.prepared;
      if (value == null) return null;
      total = total + value;
    }
    return total;
  }
}

List<PickGroup> pickGroups(WarehouseRun run) {
  final groups = <String, List<({RunOrder order, PickLine line})>>{};
  for (final order in run.orders) {
    for (final line in order.lines) {
      groups.putIfAbsent(line.presentationId, () => []).add((order: order, line: line));
    }
  }
  return [
    for (final entry in groups.entries)
      PickGroup(
        presentationId: entry.key,
        productId: entry.value.first.line.productId,
        productName: entry.value.first.line.productName,
        presentationName: entry.value.first.line.presentationName,
        lines: entry.value,
      ),
  ]..sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
}

/// Orders whose lines were all reviewed at zero: the server will not load the run while one is on it.
List<RunOrder> emptyOrders(WarehouseRun run) => [
  for (final order in run.orders)
    if (order.lines.every((line) => line.prepared != null && line.prepared!.isZero)) order,
];

final class ProductStock {
  const ProductStock({required this.available, required this.needed});

  /// Physical stock of the run's warehouse, in base units.
  final DecimalValue available;

  /// What the run takes, in base units.
  final DecimalValue needed;

  DecimalValue get missing => needed.compareTo(available) > 0 ? needed - available : DecimalValue.zero;
  bool get isShort => !missing.isZero;
}

/// Per product of the run, the warehouse stock against what the run takes: picked lines
/// count what was picked, the rest what was asked. [typed] overrides lines being edited;
/// with [unpickedAsRequested] off only reviewed lines count, as the server checks a pick.
Map<String, ProductStock> stockForRun(
  WarehouseRun run, {
  required Map<String, DecimalValue> onHand,
  Map<String, DecimalValue> typed = const {},
  bool unpickedAsRequested = true,
}) {
  final needed = <String, DecimalValue>{};
  for (final line in run.lines) {
    final value = typed[line.orderItemId] ?? line.prepared ?? (unpickedAsRequested ? line.requested : DecimalValue.zero);
    needed[line.productId] = (needed[line.productId] ?? DecimalValue.zero) + value * line.conversionFactor;
  }
  return {
    for (final entry in needed.entries) entry.key: ProductStock(available: onHand[entry.key] ?? DecimalValue.zero, needed: entry.value),
  };
}

/// Fills [targets] with all they asked for, as far as the stock goes. Stops earlier on
/// the route are served first: an earlier stop keeps its share even while unpicked.
Map<String, DecimalValue> fillByVisit(
  WarehouseRun run,
  Iterable<String> targets, {
  required Map<String, DecimalValue> onHand,
  required bool Function(String productId) allowsDecimal,
}) {
  final entries = [for (final order in run.orders) for (final line in order.lines) (order: order, line: line)];
  final wanted = targets.toSet();
  final result = <String, DecimalValue>{};
  final ordered = entries.where((entry) => wanted.contains(entry.line.orderItemId)).toList()
    ..sort((a, b) => a.order.visitOrder.compareTo(b.order.visitOrder));

  for (final target in ordered) {
    final productId = target.line.productId;
    var left = onHand[productId] ?? DecimalValue.zero;
    for (final other in entries) {
      if (other.line.productId != productId || other.line.orderItemId == target.line.orderItemId) continue;
      // Targets still to fill take what remains after this one.
      if (wanted.contains(other.line.orderItemId) && !result.containsKey(other.line.orderItemId)) continue;
      final value = result[other.line.orderItemId] ?? other.line.prepared;
      // Unpicked lines of earlier stops keep their share; later ones wait for what remains.
      final counted = value ?? (other.order.visitOrder < target.order.visitOrder ? other.line.requested : null);
      if (counted != null) left = left - counted * other.line.conversionFactor;
    }
    final fits = left.isNegative || left.isZero ? DecimalValue.zero : left.divide(target.line.conversionFactor, scale: allowsDecimal(productId) ? 6 : 0);
    result[target.line.orderItemId] = fits.compareTo(target.line.requested) < 0 ? fits : target.line.requested;
  }
  return result;
}
