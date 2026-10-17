import '../../../core/decimal_value.dart';

String? _text(Object? value) => value?.toString();

DecimalValue _decimal(Object? value) => value == null ? DecimalValue.zero : DecimalValue.parse(value);

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse(value.toString());

final class LocalCustomer {
  const LocalCustomer({
    required this.id,
    required this.code,
    required this.businessName,
    required this.address,
    this.businessType,
    this.contactName,
    this.phone,
    this.whatsapp,
    this.reference,
    this.latitude,
    this.longitude,
  });

  factory LocalCustomer.fromJson(Map<String, dynamic> json) => LocalCustomer(
        id: json['id'].toString(),
        code: json['code'] as String? ?? '',
        businessName: json['business_name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        businessType: _text(json['business_type']),
        contactName: _text(json['contact_name']),
        phone: _text(json['phone']),
        whatsapp: _text(json['whatsapp']),
        reference: _text(json['reference']),
        latitude: _text(json['latitude']),
        longitude: _text(json['longitude']),
      );

  final String id;
  final String code;
  final String businessName;
  final String address;
  final String? businessType;
  final String? contactName;
  final String? phone;
  final String? whatsapp;
  final String? reference;
  final String? latitude;
  final String? longitude;

  bool get hasLocation => latitude != null && longitude != null;
}

/// How far an operation recorded on the phone has gone.
enum LocalOperationState { synchronized, pending, accepted, rejected }

/// What happened today at a stop. Sale outcome and payment are independent:
/// a customer can buy and pay an old debt in the same visit.
final class StopActivity {
  StopActivity({
    this.hasOrder = false,
    this.hasNoSale = false,
    this.hasPayment = false,
    this.hasVisit = false,
    DecimalValue? ordersTotal,
    DecimalValue? paymentsTotal,
  })  : ordersTotal = ordersTotal ?? DecimalValue.zero,
        paymentsTotal = paymentsTotal ?? DecimalValue.zero;

  final bool hasOrder;
  final bool hasNoSale;
  final bool hasPayment;
  final bool hasVisit;
  final DecimalValue ordersTotal;
  final DecimalValue paymentsTotal;

  /// Same precedence as the server: an order wins over "no sale".
  String get status => hasOrder
      ? 'order_taken'
      : hasNoSale
          ? 'no_sale'
          : (hasVisit || hasPayment)
              ? 'visited'
              : 'pending';

  bool get isAttended => status != 'pending';

  StopActivity plus({bool order = false, bool noSale = false, bool payment = false, DecimalValue? orderTotal, DecimalValue? paymentTotal}) =>
      StopActivity(
        hasOrder: hasOrder || order,
        hasNoSale: hasNoSale || noSale,
        hasPayment: hasPayment || payment,
        hasVisit: true,
        ordersTotal: ordersTotal + (orderTotal ?? DecimalValue.zero),
        paymentsTotal: paymentsTotal + (paymentTotal ?? DecimalValue.zero),
      );
}

final class LocalRouteActivity {
  const LocalRouteActivity({
    required this.id,
    required this.date,
    required this.routeStopId,
    required this.routeId,
    required this.routeName,
    required this.visitOrder,
    required this.customer,
    required this.activity,
    required this.operationState,
    this.activityAt,
    this.orderId,
    this.orderNumber,
    this.orderReference,
    this.rejectionMessage,
  });

  factory LocalRouteActivity.fromJson(Map<String, dynamic> json) {
    final route = (json['route'] as Map? ?? const {}).cast<String, dynamic>();
    final order = (json['order'] as Map?)?.cast<String, dynamic>();
    final status = json['status'] as String? ?? 'pending';
    return LocalRouteActivity(
      id: json['id'].toString(),
      date: json['date'] as String? ?? '',
      routeStopId: json['route_stop_id'].toString(),
      routeId: route['id']?.toString() ?? '',
      routeName: route['name'] as String? ?? '',
      visitOrder: (json['visit_order'] as num?)?.toInt() ?? 0,
      customer: LocalCustomer.fromJson((json['customer'] as Map).cast<String, dynamic>()),
      activity: StopActivity(
        hasOrder: json['has_order'] as bool? ?? status == 'order_taken',
        hasNoSale: json['has_no_sale'] as bool? ?? status == 'no_sale',
        hasPayment: json['has_payment'] as bool? ?? false,
        hasVisit: status != 'pending',
        ordersTotal: _decimal(json['orders_total'] ?? order?['total']),
        paymentsTotal: _decimal(json['payments_total']),
      ),
      operationState: LocalOperationState.synchronized,
      activityAt: _date(json['activity_at']),
      orderId: order?['id']?.toString(),
      orderNumber: order?['order_number'] as String?,
    );
  }

  final String id;

  /// Day the server prepared this route for (yyyy-MM-dd).
  final String date;
  final String routeStopId;
  final String routeId;
  final String routeName;
  final int visitOrder;
  final LocalCustomer customer;
  final StopActivity activity;
  final LocalOperationState operationState;
  final DateTime? activityAt;
  final String? orderId;
  final String? orderNumber;

  /// Client reference of an order still on the phone, to open it before the server numbers it.
  final String? orderReference;
  final String? rejectionMessage;

  /// Key to open this visit's order, if it has one.
  String? get orderKey => orderReference ?? orderId;

  String get status => activity.status;
  bool get isCompleted => activity.isAttended;

  LocalRouteActivity copyWith({
    StopActivity? activity,
    LocalOperationState? operationState,
    String? orderId,
    String? orderNumber,
    String? orderReference,
    String? rejectionMessage,
  }) =>
      LocalRouteActivity(
        id: id,
        date: date,
        routeStopId: routeStopId,
        routeId: routeId,
        routeName: routeName,
        visitOrder: visitOrder,
        customer: customer,
        activity: activity ?? this.activity,
        operationState: operationState ?? this.operationState,
        activityAt: activityAt,
        orderId: orderId ?? this.orderId,
        orderNumber: orderNumber ?? this.orderNumber,
        orderReference: orderReference ?? this.orderReference,
        rejectionMessage: rejectionMessage ?? this.rejectionMessage,
      );
}

final class LocalPriceTier {
  const LocalPriceTier({
    required this.minimum,
    required this.unitPrice,
    required this.isActive,
    this.maximum,
    this.startsAt,
    this.endsAt,
  });

  factory LocalPriceTier.fromJson(Map<String, dynamic> json) => LocalPriceTier(
        minimum: _decimal(json['min_quantity']),
        maximum: json['max_quantity'] == null ? null : DecimalValue.parse(json['max_quantity']),
        unitPrice: _decimal(json['unit_price']),
        isActive: json['is_active'] != false,
        startsAt: _date(json['starts_at']),
        endsAt: _date(json['ends_at']),
      );

  final DecimalValue minimum;
  final DecimalValue? maximum;
  final DecimalValue unitPrice;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;

  bool appliesTo(DecimalValue quantity, DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return isActive &&
        quantity.compareTo(minimum) >= 0 &&
        (maximum == null || quantity.compareTo(maximum!) <= 0) &&
        (startsAt == null || !startsAt!.isAfter(date)) &&
        (endsAt == null || !endsAt!.isBefore(date));
  }
}

final class LocalPresentation {
  const LocalPresentation({
    required this.id,
    required this.name,
    required this.conversionFactor,
    required this.salePrice,
    required this.isBase,
    required this.isSellable,
    required this.isActive,
    required this.priceTiers,
    this.barcode,
  });

  factory LocalPresentation.fromJson(Map<String, dynamic> json) => LocalPresentation(
        id: json['id'].toString(),
        name: json['name'] as String? ?? '',
        barcode: _text(json['barcode']),
        conversionFactor: _decimal(json['conversion_factor']),
        salePrice: _decimal(json['sale_price']),
        isBase: json['is_base'] == true,
        isSellable: json['is_sellable'] == true,
        isActive: json['is_active'] == true,
        priceTiers: [
          for (final tier in json['price_tiers'] as List? ?? const []) LocalPriceTier.fromJson((tier as Map).cast<String, dynamic>()),
        ],
      );

  final String id;
  final String name;
  final String? barcode;

  /// Base units contained in one of this presentation.
  final DecimalValue conversionFactor;
  final DecimalValue salePrice;
  final bool isBase;
  final bool isSellable;
  final bool isActive;
  final List<LocalPriceTier> priceTiers;

  bool get canBeSold => isSellable && isActive;

  /// Same rule as the server's PresentationPriceResolver: among active tiers in
  /// force today that cover the quantity, the one with the highest minimum.
  ({DecimalValue unitPrice, LocalPriceTier? tier}) priceFor(DecimalValue quantity, DateTime day) {
    final matching = priceTiers.where((tier) => tier.appliesTo(quantity, day)).toList()
      ..sort((a, b) => b.minimum.compareTo(a.minimum));
    final tier = matching.isEmpty ? null : matching.first;
    return (unitPrice: tier?.unitPrice ?? salePrice, tier: tier);
  }
}

final class LocalProduct {
  const LocalProduct({
    required this.id,
    required this.sku,
    required this.name,
    required this.allowsDecimal,
    required this.isActive,
    required this.presentations,
    this.tracksLots = false,
    this.tracksExpiration = false,
    this.category,
    this.brand,
    this.baseUnit,
    this.imageUrl,
  });

  factory LocalProduct.fromJson(Map<String, dynamic> json) => LocalProduct(
        id: json['id'].toString(),
        sku: json['sku'] as String? ?? '',
        name: json['name'] as String? ?? '',
        category: _text(json['category']),
        brand: _text(json['brand']),
        baseUnit: _text(json['base_unit']),
        allowsDecimal: json['allows_decimal'] == true,
        tracksLots: json['tracks_lots'] == true,
        tracksExpiration: json['tracks_expiration'] == true,
        isActive: json['is_active'] == true,
        imageUrl: _text(json['image_url']),
        presentations: [
          for (final presentation in json['presentations'] as List? ?? const [])
            LocalPresentation.fromJson((presentation as Map).cast<String, dynamic>()),
        ],
      );

  final String id;
  final String sku;
  final String name;
  final String? category;
  final String? brand;
  final String? baseUnit;
  final bool allowsDecimal;
  final bool isActive;

  /// A warehouse entry of this product needs its lot number / expiry date.
  final bool tracksLots;
  final bool tracksExpiration;
  final String? imageUrl;
  final List<LocalPresentation> presentations;

  List<LocalPresentation> get sellablePresentations => [
        for (final presentation in presentations)
          if (presentation.canBeSold) presentation,
      ];
}

final class LocalStock {
  const LocalStock({required this.warehouseId, required this.productId, required this.onHand, required this.reserved, required this.available});

  factory LocalStock.fromJson(Map<String, dynamic> json) => LocalStock(
        warehouseId: json['warehouse_id'].toString(),
        productId: json['product_id'].toString(),
        onHand: _decimal(json['quantity_on_hand']),
        reserved: _decimal(json['quantity_reserved']),
        available: _decimal(json['quantity_available']),
      );

  final String warehouseId;
  final String productId;

  /// In base units of the product.
  final DecimalValue onHand;
  final DecimalValue reserved;
  final DecimalValue available;
}

final class LocalCustomerCredit {
  const LocalCustomerCredit({
    required this.customerId,
    required this.status,
    required this.allowsCredit,
    required this.limit,
    required this.termDays,
    required this.outstanding,
    required this.overdue,
    required this.committed,
    required this.available,
  });

  factory LocalCustomerCredit.fromJson(Map<String, dynamic> json) => LocalCustomerCredit(
        customerId: json['customer_id'].toString(),
        status: json['status'] as String? ?? 'disabled',
        allowsCredit: json['allows_credit'] == true,
        limit: _decimal(json['credit_limit']),
        termDays: (json['term_days'] as num?)?.toInt() ?? 0,
        outstanding: _decimal(json['outstanding']),
        overdue: _decimal(json['overdue']),
        committed: _decimal(json['committed']),
        available: _decimal(json['available_credit']),
      );

  final String customerId;
  final String status;
  final bool allowsCredit;
  final DecimalValue limit;
  final int termDays;
  final DecimalValue outstanding;
  final DecimalValue overdue;
  final DecimalValue committed;
  final DecimalValue available;
}

final class LocalReceivable {
  const LocalReceivable({
    required this.id,
    required this.customerId,
    required this.originalAmount,
    required this.outstanding,
    required this.isOverdue,
    this.documentNumber,
    this.issuedAt,
    this.dueDate,
  });

  factory LocalReceivable.fromJson(Map<String, dynamic> json) => LocalReceivable(
        id: json['id'].toString(),
        customerId: json['customer_id'].toString(),
        documentNumber: _text(json['document_number']),
        originalAmount: _decimal(json['original_amount']),
        outstanding: _decimal(json['outstanding_amount']),
        isOverdue: json['is_overdue'] == true,
        issuedAt: _date(json['issued_at']),
        dueDate: _date(json['due_date']),
      );

  final String id;
  final String customerId;
  final String? documentNumber;
  final DecimalValue originalAmount;
  final DecimalValue outstanding;
  final bool isOverdue;
  final DateTime? issuedAt;
  final DateTime? dueDate;
}

/// An order of the customer: downloaded from the server or still on the phone.
final class LocalOrderSummary {
  const LocalOrderSummary({
    required this.customerId,
    required this.orderDate,
    required this.status,
    required this.statusLabel,
    required this.paymentTerm,
    required this.total,
    required this.itemsCount,
    required this.state,
    this.id,
    this.orderNumber,
    this.clientReference,
    this.rejectionMessage,
  });

  factory LocalOrderSummary.fromJson(Map<String, dynamic> json) => LocalOrderSummary(
        id: json['id']?.toString(),
        customerId: json['customer_id'].toString(),
        orderNumber: _text(json['order_number']),
        clientReference: _text(json['client_reference']),
        orderDate: _date(json['order_date']) ?? DateTime(1970),
        status: json['status'] as String? ?? '',
        statusLabel: json['status_label'] as String? ?? '',
        paymentTerm: json['payment_term'] as String? ?? 'cash',
        total: _decimal(json['total']),
        itemsCount: (json['items_count'] as num?)?.toInt() ?? 0,
        state: LocalOperationState.synchronized,
      );

  final String? id;
  final String customerId;

  /// Number given by the server; null while the order only exists on the phone.
  final String? orderNumber;
  final String? clientReference;
  final DateTime orderDate;
  final String status;
  final String statusLabel;
  final String paymentTerm;
  final DecimalValue total;
  final int itemsCount;
  final LocalOperationState state;
  final String? rejectionMessage;

  /// What to call it before the server numbers it.
  String get reference {
    if (orderNumber != null) return orderNumber!;
    final tail = (clientReference ?? '').split(':').last;
    return 'Temporal ${(tail.length > 8 ? tail.substring(0, 8) : tail).toUpperCase()}';
  }
}

/// One line of the customer's account history (online only).
final class AccountEntry {
  const AccountEntry({required this.type, required this.typeLabel, required this.debit, required this.credit, this.receiptNumber, this.occurredAt, this.reversed = false});

  factory AccountEntry.fromJson(Map<String, dynamic> json) => AccountEntry(
        type: json['type'] as String? ?? '',
        typeLabel: json['type_label'] as String? ?? '',
        receiptNumber: _text(json['receipt_number']),
        debit: _decimal(json['debit_amount']),
        credit: _decimal(json['credit_amount']),
        occurredAt: _date(json['occurred_at']),
        reversed: json['reversed_at'] != null,
      );

  final String type;
  final String typeLabel;
  final String? receiptNumber;
  final DecimalValue debit;
  final DecimalValue credit;
  final DateTime? occurredAt;
  final bool reversed;
}
