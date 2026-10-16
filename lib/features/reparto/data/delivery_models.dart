import '../../../core/decimal_value.dart';
import '../../preventa/data/preventa_models.dart' show LocalCustomer, LocalOperationState;

DecimalValue _decimal(Object? value) => value == null ? DecimalValue.zero : DecimalValue.parse(value);

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse(value.toString());

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// A product loaded for a stop, as the warehouse loaded it, and what happened to it
/// once the driver recorded the delivery.
final class LocalDeliveryItem {
  const LocalDeliveryItem({
    required this.id,
    required this.productName,
    required this.presentationName,
    required this.unitPrice,
    required this.requested,
    required this.loaded,
    this.productId,
    this.presentationId,
    this.delivered,
    this.returned,
    this.damaged,
    this.missing,
  });

  factory LocalDeliveryItem.fromJson(Map<String, dynamic> json) => LocalDeliveryItem(
    id: json['id'].toString(),
    productId: json['product_id']?.toString(),
    presentationId: json['product_presentation_id']?.toString(),
    productName: json['product_name']?.toString() ?? '',
    presentationName: json['presentation_name']?.toString() ?? '',
    unitPrice: _decimal(json['unit_price']),
    requested: _decimal(json['requested_quantity']),
    loaded: _decimal(json['loaded_quantity']),
    delivered: json['delivered_quantity'] == null ? null : _decimal(json['delivered_quantity']),
    returned: json['returned_quantity'] == null ? null : _decimal(json['returned_quantity']),
    damaged: json['damaged_quantity'] == null ? null : _decimal(json['damaged_quantity']),
    missing: json['missing_quantity'] == null ? null : _decimal(json['missing_quantity']),
  );

  final String id;
  final String? productId;
  final String? presentationId;
  final String productName;
  final String presentationName;
  final DecimalValue unitPrice;
  final DecimalValue requested;
  final DecimalValue loaded;

  /// Null until the delivery of the stop is recorded.
  final DecimalValue? delivered;
  final DecimalValue? returned;
  final DecimalValue? damaged;
  final DecimalValue? missing;

  /// The warehouse loaded less than was ordered.
  bool get isShort => loaded.compareTo(requested) < 0;
  DecimalValue get loadedTotal => loaded * unitPrice;
  DecimalValue get deliveredTotal => (delivered ?? DecimalValue.zero) * unitPrice;

  LocalDeliveryItem withOutcome({required DecimalValue delivered, required DecimalValue returned, required DecimalValue damaged, required DecimalValue missing}) => LocalDeliveryItem(
    id: id,
    productId: productId,
    presentationId: presentationId,
    productName: productName,
    presentationName: presentationName,
    unitPrice: unitPrice,
    requested: requested,
    loaded: loaded,
    delivered: delivered,
    returned: returned,
    damaged: damaged,
    missing: missing,
  );
}

/// Where a stop stands for the driver.
enum StopProgress {
  /// Nothing recorded yet.
  pending,

  /// Delivered something, the payment is still missing.
  awaitingPayment,

  /// Finished: delivered and paid, partially delivered, or not delivered.
  done,
}

/// One customer of the run with what goes for them.
final class LocalDeliveryStop {
  const LocalDeliveryStop({
    required this.id,
    required this.visitOrder,
    required this.status,
    required this.statusLabel,
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.customerAddress,
    required this.paymentTerm,
    required this.items,
    required this.deliveredTotal,
    required this.collectedTotal,
    required this.balanceDue,
    required this.operationState,
    this.orderNumber,
    this.customer,
    this.outcomeStatus,
    this.rejectionMessage,
    this.receiverName,
    this.outcomeReasonLabel,
  });

  factory LocalDeliveryStop.fromJson(Map<String, dynamic> json) {
    final order = (json['order'] as Map? ?? const {}).cast<String, dynamic>();
    return LocalDeliveryStop(
      id: json['id'].toString(),
      visitOrder: (json['visit_order'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'loaded',
      statusLabel: json['status_label']?.toString() ?? '',
      outcomeStatus: _text(json['outcome_status']),
      orderId: order['id']?.toString() ?? '',
      orderNumber: _text(order['order_number']),
      customerId: order['customer_id']?.toString() ?? '',
      customerName: order['customer_name']?.toString() ?? '',
      customerAddress: order['customer_address']?.toString() ?? '',
      paymentTerm: order['payment_term']?.toString() ?? 'cash',
      items: [for (final item in (json['items'] as List? ?? const []).cast<Map>()) LocalDeliveryItem.fromJson(item.cast<String, dynamic>())],
      deliveredTotal: _decimal(json['delivered_total']),
      collectedTotal: _decimal(json['collected_total']),
      balanceDue: _decimal(json['balance_due']),
      operationState: LocalOperationState.synchronized,
      receiverName: _text(json['receiver_name']),
      outcomeReasonLabel: _text(json['outcome_reason_label']),
    );
  }

  /// Id of the stop on the server (`run_order_id` in operations).
  final String id;
  final int visitOrder;
  final String status;
  final String statusLabel;
  final String? outcomeStatus;
  final String orderId;
  final String? orderNumber;
  final String customerId;
  final String customerName;
  final String customerAddress;
  final String paymentTerm;
  final List<LocalDeliveryItem> items;
  final DecimalValue deliveredTotal;
  final DecimalValue collectedTotal;
  final DecimalValue balanceDue;
  final LocalOperationState operationState;

  /// Contact and location from the downloaded customers, when the phone has them.
  final LocalCustomer? customer;
  final String? rejectionMessage;

  /// Who took the merchandise, and why something was not delivered.
  final String? receiverName;
  final String? outcomeReasonLabel;

  /// The delivery of this stop is recorded (on the server or on the phone).
  bool get hasOutcome => status != 'loaded';

  bool get isCredit => paymentTerm == 'credit';
  DecimalValue get loadedTotal => items.fold(DecimalValue.zero, (total, item) => total + item.loadedTotal);
  bool get hasShortItems => items.any((item) => item.isShort);

  StopProgress get progress => switch (status) {
    'awaiting_payment' => StopProgress.awaitingPayment,
    'delivered' || 'partially_delivered' || 'not_delivered' || 'cancelled' => StopProgress.done,
    _ => StopProgress.pending,
  };

  LocalDeliveryStop copyWith({
    LocalCustomer? customer,
    LocalOperationState? operationState,
    String? rejectionMessage,
    String? status,
    String? statusLabel,
    String? outcomeStatus,
    List<LocalDeliveryItem>? items,
    DecimalValue? deliveredTotal,
    DecimalValue? balanceDue,
    String? receiverName,
    String? outcomeReasonLabel,
  }) => LocalDeliveryStop(
    id: id,
    visitOrder: visitOrder,
    status: status ?? this.status,
    statusLabel: statusLabel ?? this.statusLabel,
    outcomeStatus: outcomeStatus ?? this.outcomeStatus,
    orderId: orderId,
    orderNumber: orderNumber,
    customerId: customerId,
    customerName: customerName,
    customerAddress: customerAddress,
    paymentTerm: paymentTerm,
    items: items ?? this.items,
    deliveredTotal: deliveredTotal ?? this.deliveredTotal,
    collectedTotal: collectedTotal,
    balanceDue: balanceDue ?? this.balanceDue,
    operationState: operationState ?? this.operationState,
    customer: customer ?? this.customer,
    rejectionMessage: rejectionMessage ?? this.rejectionMessage,
    receiverName: receiverName ?? this.receiverName,
    outcomeReasonLabel: outcomeReasonLabel ?? this.outcomeReasonLabel,
  );
}

/// A run of the driver: the truck, its stops and whether it already left.
final class LocalDeliveryRun {
  const LocalDeliveryRun({
    required this.id,
    required this.runNumber,
    required this.status,
    required this.stops,
    this.scheduledDate,
    this.vehicleCode,
    this.licensePlate,
    this.warehouseName,
    this.departedAt,
    this.departurePending = false,
    this.departureRejection,
    this.cashCollected,
    this.creditGranted,
  });

  factory LocalDeliveryRun.fromJson(Map<String, dynamic> json) => LocalDeliveryRun(
    cashCollected: _decimal((json['financials'] as Map?)?['cash_expected']),
    creditGranted: _decimal((json['financials'] as Map?)?['credit_total']),
    id: json['id'].toString(),
    runNumber: json['run_number']?.toString() ?? '',
    status: json['status']?.toString() ?? 'loaded',
    scheduledDate: _date(json['scheduled_date']),
    vehicleCode: _text(json['vehicle_code']),
    licensePlate: _text(json['vehicle_license_plate']),
    warehouseName: _text(json['warehouse_name']),
    departedAt: _date(json['departed_at']),
    stops: [for (final stop in (json['orders'] as List? ?? const []).cast<Map>()) LocalDeliveryStop.fromJson(stop.cast<String, dynamic>())]..sort((a, b) => a.visitOrder.compareTo(b.visitOrder)),
  );

  final String id;
  final String runNumber;

  /// Server status: `loaded`, `in_transit` or `awaiting_settlement`.
  final String status;
  final DateTime? scheduledDate;
  final String? vehicleCode;
  final String? licensePlate;
  final String? warehouseName;
  final DateTime? departedAt;
  final List<LocalDeliveryStop> stops;

  /// Cash the driver carries for this run and credit given, as the server last added them up.
  final DecimalValue? cashCollected;
  final DecimalValue? creditGranted;

  /// The driver tapped "Salir" and it has not reached the server yet.
  final bool departurePending;
  final String? departureRejection;

  /// On the road, for the server or for the phone.
  bool get hasLeft => status != 'loaded' || departurePending;

  String get statusLabel => switch (status) {
    'loaded' => departurePending ? 'En ruta' : 'Cargada, sin salir',
    'in_transit' => 'En ruta',
    'awaiting_settlement' => 'Por liquidar',
    _ => status,
  };

  /// Still needs the driver: not out yet, or stops to deliver or collect. A run with
  /// every stop finished only waits for the supervisor to settle it.
  bool get needsDriver => !hasLeft || pendingStops.isNotEmpty;

  List<LocalDeliveryStop> get pendingStops => [
    for (final stop in stops)
      if (stop.progress != StopProgress.done) stop,
  ];

  /// Where to go now: a stop left half done (delivered, not paid) first, then the next in order.
  LocalDeliveryStop? get nextStop {
    final pending = pendingStops;
    return pending.where((stop) => stop.progress == StopProgress.awaitingPayment).firstOrNull ?? pending.firstOrNull;
  }

  List<LocalDeliveryStop> get doneStops => [
    for (final stop in stops)
      if (stop.progress == StopProgress.done) stop,
  ];
  DecimalValue get loadedTotal => stops.fold(DecimalValue.zero, (total, stop) => total + stop.loadedTotal);
  DecimalValue get collectedTotal => stops.fold(DecimalValue.zero, (total, stop) => total + stop.collectedTotal);
  double get progress => stops.isEmpty ? 0 : doneStops.length / stops.length;

  LocalDeliveryRun copyWith({List<LocalDeliveryStop>? stops, bool? departurePending, String? departureRejection}) => LocalDeliveryRun(
    id: id,
    runNumber: runNumber,
    status: status,
    scheduledDate: scheduledDate,
    vehicleCode: vehicleCode,
    licensePlate: licensePlate,
    warehouseName: warehouseName,
    departedAt: departedAt,
    stops: stops ?? this.stops,
    departurePending: departurePending ?? this.departurePending,
    departureRejection: departureRejection ?? this.departureRejection,
    cashCollected: cashCollected,
    creditGranted: creditGranted,
  );
}
