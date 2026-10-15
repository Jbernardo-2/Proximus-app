import 'dart:convert';

import '../../../core/decimal_value.dart';
import '../../../data/database.dart';
import 'preventa_models.dart';
import 'preventista_repository.dart';

/// One line of an order as it was sold.
final class OrderDetailLine {
  const OrderDetailLine({
    required this.productName,
    required this.presentationName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.productId,
    this.notes,
  });

  final String? productId;
  final String productName;
  final String presentationName;
  final DecimalValue quantity;
  final DecimalValue unitPrice;
  final DecimalValue lineTotal;
  final String? notes;
}

/// An order to look at, never to change: confirmed on the server or waiting on the phone.
final class OrderDetail {
  const OrderDetail({
    required this.customerId,
    required this.orderDate,
    required this.paymentTerm,
    required this.statusLabel,
    required this.state,
    required this.lines,
    required this.total,
    this.id,
    this.orderNumber,
    this.clientReference,
    this.deliveryDate,
    this.notes,
    this.rejectionMessage,
  });

  final String? id;
  final String customerId;
  final String? orderNumber;
  final String? clientReference;
  final DateTime orderDate;
  final DateTime? deliveryDate;
  final String paymentTerm;
  final String statusLabel;
  final LocalOperationState state;
  final List<OrderDetailLine> lines;
  final DecimalValue total;
  final String? notes;
  final String? rejectionMessage;

  /// Same wording as the order lists: the server number, or a temporary one.
  String get reference => LocalOrderSummary(
        customerId: customerId,
        orderDate: orderDate,
        status: '',
        statusLabel: statusLabel,
        paymentTerm: paymentTerm,
        total: total,
        itemsCount: lines.length,
        state: state,
        orderNumber: orderNumber,
        clientReference: clientReference,
      ).reference;
}

/// Finds an order by its key (the phone's client reference, or the server id) in what
/// was downloaded and in what is still on the phone. The server's copy wins once it exists.
OrderDetail? findOrderDetail(
  String key, {
  required List<Map<String, dynamic>> downloaded,
  required List<OutboxData> outbox,
  required Map<String, ({String productId, String product, String presentation})> presentationNames,
}) {
  final server = downloaded.where((json) => json['id']?.toString() == key || json['client_reference']?.toString() == key).firstOrNull;
  final operation = outbox.where((row) => row.type == 'order.create' && row.clientReference == key).firstOrNull ??
      outbox.where((row) => row.type == 'order.create' && row.result != null && (jsonDecode(row.result!) as Map?)?['id']?.toString() == key).firstOrNull;

  if (server != null && server['items'] is List) {
    return OrderDetail(
      id: server['id']?.toString(),
      customerId: server['customer_id'].toString(),
      orderNumber: server['order_number'] as String?,
      clientReference: server['client_reference'] as String?,
      orderDate: DateTime.tryParse(server['order_date']?.toString() ?? '') ?? DateTime(1970),
      deliveryDate: DateTime.tryParse(server['requested_delivery_date']?.toString() ?? ''),
      paymentTerm: server['payment_term']?.toString() ?? 'cash',
      statusLabel: server['status_label']?.toString() ?? '',
      state: LocalOperationState.synchronized,
      total: DecimalValue.parse(server['total'] ?? '0'),
      notes: _text(server['notes']),
      rejectionMessage: _text(server['cancellation_reason']),
      lines: [
        for (final item in (server['items'] as List).cast<Map>())
          OrderDetailLine(
            productId: item['product_id']?.toString(),
            productName: item['product_name']?.toString() ?? '',
            presentationName: item['presentation_name']?.toString() ?? '',
            quantity: DecimalValue.parse(item['quantity'] ?? '0'),
            unitPrice: DecimalValue.parse(item['unit_price'] ?? '0'),
            lineTotal: DecimalValue.parse(item['line_total'] ?? '0'),
            notes: _text(item['notes']),
          ),
      ],
    );
  }
  if (operation == null) return null;

  final payload = (jsonDecode(operation.payload) as Map).cast<String, dynamic>();
  final result = operation.result == null ? null : (jsonDecode(operation.result!) as Map?)?.cast<String, dynamic>();
  return OrderDetail(
    id: result?['id']?.toString(),
    customerId: payload['customer_id'].toString(),
    orderNumber: result?['order_number'] as String?,
    clientReference: operation.clientReference,
    orderDate: DateTime.tryParse(payload['order_date']?.toString() ?? '') ?? operation.createdAt,
    deliveryDate: DateTime.tryParse(payload['requested_delivery_date']?.toString() ?? ''),
    paymentTerm: payload['payment_term']?.toString() ?? 'cash',
    statusLabel: switch (operation.status) {
      OutboxStatus.pending => 'Por enviar',
      OutboxStatus.rejected => 'Rechazado',
      _ => 'Confirmado',
    },
    state: switch (operation.status) {
      OutboxStatus.pending => LocalOperationState.pending,
      OutboxStatus.rejected => LocalOperationState.rejected,
      _ => LocalOperationState.accepted,
    },
    total: PreventistaRepository.orderTotal(payload),
    notes: _text(payload['notes']),
    rejectionMessage: operation.status == OutboxStatus.rejected ? operation.message : null,
    lines: [
      for (final item in (payload['items'] as List? ?? const []).cast<Map>())
        () {
          final names = presentationNames[item['product_presentation_id']?.toString()];
          final quantity = DecimalValue.parse(item['quantity'] ?? '0');
          final unitPrice = DecimalValue.parse(item['unit_price'] ?? '0');
          return OrderDetailLine(
            productId: names?.productId,
            productName: names?.product ?? 'Producto no disponible en el teléfono',
            presentationName: names?.presentation ?? '',
            quantity: quantity,
            unitPrice: unitPrice,
            lineTotal: quantity * unitPrice,
            notes: _text(item['notes']),
          );
        }(),
    ],
  );
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
