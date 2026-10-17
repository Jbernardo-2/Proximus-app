import 'dart:convert';

import '../../../core/decimal_value.dart';
import '../../../data/database.dart';

/// One order line to pick. Keyed by the order line: a run assembled offline has no run lines yet.
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

  /// Null while nobody has picked it.
  final DecimalValue? prepared;

  PickLine withPrepared(DecimalValue? value) => PickLine(
    orderItemId: orderItemId,
    productId: productId,
    presentationId: presentationId,
    productName: productName,
    presentationName: presentationName,
    requested: requested,
    conversionFactor: conversionFactor,
    prepared: value,
  );
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
    this.pendingAssignId,
  });

  final String orderId;
  final String orderNumber;
  final String customerName;
  final String? routeName;
  final DecimalValue total;
  final List<PickLine> lines;

  /// Stop number on the route: when stock is short, earlier stops are filled first.
  final int visitOrder;

  /// The server's run order; null until the assignment reaches it.
  final String? runOrderId;

  /// The queued assignment not sent yet: removing the order just drops it from the queue.
  final int? pendingAssignId;

  RunOrder copyWith({List<PickLine>? lines, String? runOrderId}) => RunOrder(
    orderId: orderId,
    orderNumber: orderNumber,
    customerName: customerName,
    routeName: routeName,
    total: total,
    lines: lines ?? this.lines,
    visitOrder: visitOrder,
    runOrderId: runOrderId ?? this.runOrderId,
    pendingAssignId: pendingAssignId,
  );
}

final class WarehouseRun {
  const WarehouseRun({
    required this.id,
    required this.status,
    required this.warehouseId,
    required this.driverName,
    required this.orders,
    this.runNumber,
    this.scheduledDate,
    this.vehicle,
    this.preparationStartedBy,
    this.pending = false,
    this.loadedOnPhone = false,
    this.rejections = const [],
  });

  final String id;

  /// Null until the server numbers a run made on the phone.
  final String? runNumber;

  /// draft, preparing or loaded.
  final String status;
  final String? warehouseId;
  final DateTime? scheduledDate;
  final String driverName;
  final String? vehicle;
  final int? preparationStartedBy;
  final List<RunOrder> orders;

  /// Something about this run is still on the phone.
  final bool pending;

  /// Loaded on this phone, so the downloaded stock does not show it left yet.
  final bool loadedOnPhone;

  /// What the server refused, to show on the run.
  final List<String> rejections;

  String get title => runNumber ?? 'Jornada nueva';

  bool get isDraft => status == 'draft';
  bool get isPreparing => status == 'preparing';
  bool get isLoaded => status == 'loaded';

  /// Who may pick it: the keeper who started it, or any supervisor.
  bool preparableBy(int userId, {required bool supervises}) => isPreparing && (supervises || preparationStartedBy == null || preparationStartedBy == userId);

  List<PickLine> get lines => [for (final order in orders) ...order.lines];

  WarehouseRun copyWith({String? runNumber, String? status, int? preparationStartedBy, List<RunOrder>? orders, bool? pending, bool? loadedOnPhone, List<String>? rejections}) => WarehouseRun(
    id: id,
    runNumber: runNumber ?? this.runNumber,
    status: status ?? this.status,
    warehouseId: warehouseId,
    scheduledDate: scheduledDate,
    driverName: driverName,
    vehicle: vehicle,
    preparationStartedBy: preparationStartedBy ?? this.preparationStartedBy,
    orders: orders ?? this.orders,
    pending: pending ?? this.pending,
    loadedOnPhone: loadedOnPhone ?? this.loadedOnPhone,
    rejections: rejections ?? this.rejections,
  );
}

/// A confirmed order that waits for a run, as the warehouse assigns it.
final class DispatchOrder {
  const DispatchOrder({required this.order, required this.warehouseId, this.requestedDate, this.routeId});

  final RunOrder order;
  final String? warehouseId;
  final String? routeId;
  final DateTime? requestedDate;
}

DecimalValue _d(Object? value) => DecimalValue.parse(value);

DispatchOrder dispatchOrderFromJson(Map<String, dynamic> json) => DispatchOrder(
  warehouseId: json['warehouse_id']?.toString(),
  routeId: json['sales_route_id']?.toString(),
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
          conversionFactor: item['conversion_factor'] == null ? DecimalValue.parse('1') : _d(item['conversion_factor']),
        ),
    ],
  ),
);

WarehouseRun _runFromJson(Map<String, dynamic> json) => WarehouseRun(
  id: json['id'].toString(),
  runNumber: json['run_number']?.toString(),
  status: json['status']?.toString() ?? 'draft',
  warehouseId: (json['warehouse'] as Map?)?['id']?.toString(),
  scheduledDate: DateTime.tryParse(json['scheduled_date']?.toString() ?? ''),
  driverName: json['driver_name']?.toString() ?? (json['driver'] as Map?)?['name']?.toString() ?? '',
  vehicle: json['vehicle_license_plate']?.toString() ?? json['vehicle_code']?.toString(),
  preparationStartedBy: (json['preparation_started_by'] as num?)?.toInt(),
  orders: [
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
              conversionFactor: item['conversion_factor'] == null ? DecimalValue.parse('1') : _d(item['conversion_factor']),
              // Untouched lines come as zero; only a prepared order counts as picked.
              prepared: stop['prepared_at'] == null ? null : _d(item['prepared_quantity']),
            ),
        ],
      ),
  ],
);

/// The runs the warehouse works on (draft, preparing, loaded) with what this phone recorded
/// and the server has not reflected yet, and the orders still free to assign.
({List<WarehouseRun> runs, List<DispatchOrder> available}) mergeWarehouseRuns({
  required List<Map<String, dynamic>> records,
  required List<Map<String, dynamic>> dispatchOrders,
  required List<OutboxData> outbox,
  required DateTime? pulledAt,
  required Map<String, String> drivers,
  required int userId,
}) {
  final runs = <String, WarehouseRun>{
    for (final json in records)
      if (const {'draft', 'preparing', 'loaded'}.contains(json['status'])) json['id'].toString(): _runFromJson(json),
  };
  final free = {for (final json in dispatchOrders) json['id'].toString(): dispatchOrderFromJson(json)};
  // Orders freed on the phone come back to the list with what the run knew of them.
  final freed = <String, DispatchOrder>{};

  for (final operation in outbox) {
    if (!operation.type.startsWith('delivery.') || const {'delivery.depart', 'delivery.outcome', 'delivery.payment', 'delivery.settle'}.contains(operation.type)) continue;
    if (operation.status == OutboxStatus.done && pulledAt != null && !(operation.processedAt?.isAfter(pulledAt) ?? false)) continue;
    final payload = (jsonDecode(operation.payload) as Map).cast<String, dynamic>();
    final runId = (operation.type == 'delivery.create' ? payload['id'] : payload['delivery_run_id'])?.toString();
    final pending = operation.status == OutboxStatus.pending;

    if (operation.type == 'delivery.create') {
      if (operation.status == OutboxStatus.rejected) continue;
      final data = operation.result == null ? null : jsonDecode(operation.result!) as Map?;
      runs[runId!] ??= WarehouseRun(
        id: runId,
        runNumber: data?['run_number']?.toString(),
        status: 'draft',
        warehouseId: payload['warehouse_id']?.toString(),
        scheduledDate: DateTime.tryParse(payload['scheduled_date']?.toString() ?? ''),
        driverName: drivers[payload['driver_id']?.toString()] ?? 'Repartidor',
        orders: const [],
        pending: pending,
      );
      continue;
    }

    final run = runs[runId];
    if (run == null) continue;
    if (operation.status == OutboxStatus.rejected) {
      runs[run.id] = run.copyWith(rejections: [...run.rejections, operation.message ?? 'El servidor no aceptó un cambio de esta jornada.']);
      continue;
    }

    switch (operation.type) {
      case 'delivery.assign':
        final order = free.remove(payload['order_id']?.toString()) ?? freed.remove(payload['order_id']?.toString());
        if (order == null || run.orders.any((existing) => existing.orderId == order.order.orderId)) break;
        final data = operation.result == null ? null : jsonDecode(operation.result!) as Map?;
        runs[run.id] = run.copyWith(pending: run.pending || pending, orders: [
          ...run.orders,
          RunOrder(
            orderId: order.order.orderId,
            orderNumber: order.order.orderNumber,
            customerName: order.order.customerName,
            routeName: order.order.routeName,
            total: order.order.total,
            lines: order.order.lines,
            visitOrder: (data?['visit_order'] as num?)?.toInt() ?? run.orders.fold<int>(0, (top, existing) => existing.visitOrder > top ? existing.visitOrder : top) + 1,
            runOrderId: data?['id']?.toString(),
            pendingAssignId: pending ? operation.id : null,
          ),
        ]);
      case 'delivery.unassign':
        final removed = run.orders.where((order) => order.runOrderId == payload['run_order_id']?.toString()).firstOrNull;
        if (removed == null) break;
        freed[removed.orderId] = DispatchOrder(order: removed, warehouseId: run.warehouseId);
        runs[run.id] = run.copyWith(pending: run.pending || pending, orders: [for (final order in run.orders) if (order != removed) order]);
      case 'delivery.prepare_start':
        runs[run.id] = run.copyWith(status: run.isDraft ? 'preparing' : run.status, preparationStartedBy: run.preparationStartedBy ?? userId, pending: run.pending || pending);
      case 'delivery.prepare':
        // Sending again after a refusal: the old refusal no longer applies.
        runs[run.id] = runs[run.id]!.copyWith(rejections: const []);
        final quantities = {
          for (final item in (payload['items'] as List? ?? const []).cast<Map>()) item['order_item_id']?.toString(): _d(item['prepared_quantity']),
        };
        runs[run.id] = runs[run.id]!.copyWith(pending: run.pending || pending, orders: [
          for (final order in run.orders)
            order.copyWith(lines: [for (final line in order.lines) quantities.containsKey(line.orderItemId) ? line.withPrepared(quantities[line.orderItemId]) : line]),
        ]);
      case 'delivery.load':
        runs[run.id] = run.copyWith(status: run.isPreparing ? 'loaded' : run.status, pending: run.pending || pending, loadedOnPhone: true, rejections: const []);
    }
  }

  final assigned = {for (final run in runs.values) for (final order in run.orders) order.orderId};
  final order = {'draft': 0, 'preparing': 1, 'loaded': 2};
  return (
    runs: runs.values.toList()..sort((a, b) => (order[a.status] ?? 3).compareTo(order[b.status] ?? 3)),
    available: [
      for (final dispatch in [...free.values, ...freed.values])
        if (!assigned.contains(dispatch.order.orderId)) dispatch,
    ],
  );
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

  /// Null while any line is still unpicked.
  DecimalValue? preparedWith(Map<String, DecimalValue> draft) {
    var total = DecimalValue.zero;
    for (final entry in lines) {
      final value = draft[entry.line.orderItemId] ?? entry.line.prepared;
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

/// The quantities to send: what was picked on the phone over what the run already had.
/// Null when a line is still unpicked.
Map<String, DecimalValue>? preparedQuantities(WarehouseRun run, Map<String, DecimalValue> draft) {
  final result = <String, DecimalValue>{};
  for (final line in run.lines) {
    final value = draft[line.orderItemId] ?? line.prepared;
    if (value == null) return null;
    result[line.orderItemId] = value;
  }
  return result;
}

/// Orders that would load nothing: the server refuses the load while one is in the run.
List<RunOrder> emptyOrders(WarehouseRun run, Map<String, DecimalValue> quantities) => [
  for (final order in run.orders)
    if (order.lines.every((line) => (quantities[line.orderItemId] ?? DecimalValue.zero).isZero)) order,
];

/// The base units a line takes from the warehouse: what was picked, or what was asked while unpicked.
DecimalValue _baseNeed(PickLine line, Map<String, DecimalValue> draft, {bool unpickedAsRequested = true}) =>
    (draft[line.orderItemId] ?? line.prepared ?? (unpickedAsRequested ? line.requested : DecimalValue.zero)) * line.conversionFactor;

/// Base units already on trucks loaded on this phone that the downloaded stock does not show yet.
Map<String, DecimalValue> committedOnPhone(List<WarehouseRun> runs, {required String exceptRunId}) {
  final committed = <String, DecimalValue>{};
  for (final run in runs) {
    if (run.id == exceptRunId || !run.loadedOnPhone) continue;
    for (final line in run.lines) {
      committed[line.productId] = (committed[line.productId] ?? DecimalValue.zero) + _baseNeed(line, const {});
    }
  }
  return committed;
}

final class ProductStock {
  const ProductStock({required this.available, required this.needed});

  /// Physical stock of the run's warehouse left for this run, in base units.
  final DecimalValue available;

  /// What the run takes now, in base units.
  final DecimalValue needed;

  DecimalValue get missing => needed.compareTo(available) > 0 ? needed - available : DecimalValue.zero;
  bool get isShort => !missing.isZero;
}

/// Per product of the run: what the warehouse has for it against what the run takes,
/// the same check the server makes before loading. With [unpickedAsRequested] off, only
/// what was already picked counts: what is typed is never blocked by lines nobody reviewed.
Map<String, ProductStock> stockForRun(
  WarehouseRun run,
  Map<String, DecimalValue> draft, {
  required Map<String, DecimalValue> onHand,
  required Map<String, DecimalValue> committed,
  bool unpickedAsRequested = true,
}) {
  final needed = <String, DecimalValue>{};
  for (final line in run.lines) {
    needed[line.productId] = (needed[line.productId] ?? DecimalValue.zero) + _baseNeed(line, draft, unpickedAsRequested: unpickedAsRequested);
  }
  return {
    for (final entry in needed.entries)
      entry.key: ProductStock(available: (onHand[entry.key] ?? DecimalValue.zero) - (committed[entry.key] ?? DecimalValue.zero), needed: entry.value),
  };
}

/// Fills [targets] with all they asked for, as far as the stock goes. Stops earlier on
/// the route are served first: an earlier stop keeps its share even while unpicked.
Map<String, DecimalValue> fillByVisit(
  WarehouseRun run,
  Map<String, DecimalValue> draft,
  Iterable<String> targets, {
  required Map<String, DecimalValue> onHand,
  required Map<String, DecimalValue> committed,
  required bool Function(String productId) allowsDecimal,
}) {
  final entries = [for (final order in run.orders) for (final line in order.lines) (order: order, line: line)];
  final wanted = targets.toSet();
  final result = <String, DecimalValue>{};
  final ordered = entries.where((entry) => wanted.contains(entry.line.orderItemId)).toList()
    ..sort((a, b) => a.order.visitOrder.compareTo(b.order.visitOrder));

  for (final target in ordered) {
    final productId = target.line.productId;
    var left = (onHand[productId] ?? DecimalValue.zero) - (committed[productId] ?? DecimalValue.zero);
    for (final other in entries) {
      if (other.line.productId != productId || other.line.orderItemId == target.line.orderItemId) continue;
      // Targets still to fill take what remains after this one.
      if (wanted.contains(other.line.orderItemId) && !result.containsKey(other.line.orderItemId)) continue;
      final value = result[other.line.orderItemId] ?? draft[other.line.orderItemId] ?? other.line.prepared;
      // Unpicked lines of earlier stops keep their share; later ones wait for what remains.
      final counted = value ?? (other.order.visitOrder < target.order.visitOrder ? other.line.requested : null);
      if (counted != null) left = left - counted * other.line.conversionFactor;
    }
    final fits = left.isNegative || left.isZero ? DecimalValue.zero : left.divide(target.line.conversionFactor, scale: allowsDecimal(productId) ? 6 : 0);
    result[target.line.orderItemId] = fits.compareTo(target.line.requested) < 0 ? fits : target.line.requested;
  }
  return result;
}
