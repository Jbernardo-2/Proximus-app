import '../../../core/decimal_value.dart';
import '../../../core/location_capture.dart';
import '../../../core/ulid.dart';

/// Payloads of the preventista's queue operations, shaped as the server
/// contract expects them (docs/api/sincronizacion-movil.md, section 4).
abstract final class PreventaOperations {
  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  /// `route_stop_id` is required: the server ties a preventista's order to a stop of their route.
  static Map<String, dynamic> order({
    required String customerId,
    required String routeStopId,
    required DateTime takenAt,
    required String paymentTerm,
    required List<({String presentationId, DecimalValue quantity, DecimalValue unitPrice, String? notes})> items,
    required LocationCapture location,
    DateTime? deliveryDate,
    String? notes,
    bool confirm = true,
  }) =>
      {
        'customer_id': customerId,
        'route_stop_id': routeStopId,
        'order_date': _date(takenAt),
        'requested_delivery_date': ?(deliveryDate == null ? null : _date(deliveryDate)),
        'payment_term': paymentTerm,
        'notes': notes,
        'confirm': confirm,
        'items': [
          for (final item in items)
            {
              'product_presentation_id': item.presentationId,
              'quantity': item.quantity.toString(),
              'unit_price': item.unitPrice.toFixed(4),
              'notes': item.notes,
            },
        ],
        'location': location.toPayload(takenAt),
      };

  static Map<String, dynamic> noSale({
    required String customerId,
    String? routeStopId,
    required String reason,
    required DateTime at,
    required LocationCapture location,
    String? notes,
  }) =>
      {'customer_id': customerId, 'route_stop_id': ?routeStopId, 'reason': reason, 'notes': notes, 'location': location.toPayload(at)};

  static Map<String, dynamic> accountPayment({
    required String customerId,
    required String receiptNumber,
    required DecimalValue amount,
    required List<({String method, DecimalValue amount, String? reference})> lines,
    required List<({String receivableId, DecimalValue amount})> allocations,
    required DateTime at,
    required LocationCapture location,
    String? notes,
  }) {
    final paid = lines.fold(DecimalValue.zero, (total, line) => total + line.amount);
    final applied = allocations.fold(DecimalValue.zero, (total, allocation) => total + allocation.amount);
    if (paid != amount || applied != amount) {
      throw ArgumentError('Los métodos de pago y las deudas deben sumar exactamente el abono.');
    }
    return {
      'customer_id': customerId,
      'receipt_number': receiptNumber,
      'amount': amount.toString(),
      'payment_lines': [
        for (final line in lines) {'method': line.method, 'amount': line.amount.toString(), 'reference': line.reference},
      ],
      'allocations': [
        for (final allocation in allocations) {'receivable_id': allocation.receivableId, 'amount': allocation.amount.toString()},
      ],
      'notes': notes,
      'location': location.toPayload(at),
    };
  }

  /// New customer with ids generated here, so an order can follow it in the same queue.
  static Map<String, dynamic> newCustomer({
    required String businessName,
    required String address,
    required int visitDay,
    String? salesRouteId,
    String? businessType,
    String? notes,
    String? contactName,
    String? phone,
    String? whatsapp,
    String? reference,
    LocationCapture? location,
    String? id,
    String? routeStopId,
  }) {
    final position = location?.position;
    return {
      'id': id ?? Ulid.generate(),
      'business_name': businessName,
      'business_type': businessType,
      'address': address,
      'notes': notes,
      'contact_name': contactName,
      'phone': phone,
      'whatsapp': whatsapp,
      'reference': reference,
      'latitude': position?.latitude.toStringAsFixed(7),
      'longitude': position?.longitude.toStringAsFixed(7),
      'is_active': true,
      'route_stop': {
        'id': routeStopId ?? Ulid.generate(),
        'sales_route_id': ?salesRouteId,
        'visit_day': visitDay,
      },
    };
  }
}
