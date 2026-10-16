import 'dart:convert';

import '../core/decimal_value.dart';
import '../core/formatting.dart';
import '../data/database.dart';

/// Where an operation recorded on the phone stands, in the user's words.
enum OperationState {
  saved('Guardado en el teléfono'),
  sending('Enviando'),
  waitingSignal('Pendiente por falta de conexión'),
  retrying('Reintentando'),
  accepted('Aceptado por el servidor'),
  rejected('Rechazado');

  const OperationState(this.label);

  final String label;
}

const operationLabels = {
  'customer.create': 'Cliente nuevo',
  'order.create': 'Pedido',
  'visit.no_sale': 'Visita sin venta',
  'customer.payment': 'Abono',
  'delivery.depart': 'Salida de jornada',
  'delivery.outcome': 'Resultado de entrega',
  'delivery.payment': 'Cobro de entrega',
};

/// An outbox row explained: what was recorded, what the server answered and what to do.
final class OperationView {
  OperationView._({
    required this.row,
    required this.payload,
    required this.state,
    required this.details,
    this.serverNumber,
    this.recommendation,
  });

  /// [sending] while a sync cycle runs; [offline] when the last attempt found no signal.
  factory OperationView.of(OutboxData row, {required bool sending, required bool offline}) {
    final payload = (jsonDecode(row.payload) as Map).cast<String, dynamic>();
    final result = row.result == null ? null : (jsonDecode(row.result!) as Map?)?.cast<String, dynamic>();
    final state = switch (row.status) {
      OutboxStatus.done => OperationState.accepted,
      OutboxStatus.rejected => OperationState.rejected,
      _ when sending => OperationState.sending,
      _ when row.attempts > 0 => OperationState.retrying,
      _ when offline => OperationState.waitingSignal,
      _ => OperationState.saved,
    };

    return OperationView._(
      row: row,
      payload: payload,
      state: state,
      details: _details(row.type, payload),
      serverNumber: result?['order_number']?.toString() ?? result?['receipt_number']?.toString() ?? result?['code']?.toString(),
      recommendation: state == OperationState.rejected ? recommend(row.type, row.httpStatus, row.message ?? '') : null,
    );
  }

  final OutboxData row;
  final Map<String, dynamic> payload;
  final OperationState state;

  /// What was recorded, as label/value pairs.
  final List<(String, String)> details;

  /// Number given by the server once accepted (order or customer code).
  final String? serverNumber;
  final String? recommendation;

  String get title => operationLabels[row.type] ?? row.type;
  String get customer => row.summary;
  String? get customerId => payload['customer_id']?.toString() ?? (row.type == 'customer.create' ? payload['id']?.toString() : null);

  /// Receipt snapshot of an account payment, to reprint it.
  Map<String, dynamic>? get receipt => (payload['receipt'] as Map?)?.cast<String, dynamic>();

  /// A rejected payment whose receipt the customer already holds deserves special care.
  bool get customerHoldsReceipt => row.type == 'customer.payment' && receipt != null;

  static List<(String, String)> _details(String type, Map<String, dynamic> payload) {
    DecimalValue value(Object? raw) => raw == null ? DecimalValue.zero : DecimalValue.parse(raw);
    switch (type) {
      case 'order.create':
        final items = (payload['items'] as List? ?? const []).cast<Map>();
        final total = items.fold(DecimalValue.zero, (sum, item) => sum + value(item['quantity']) * value(item['unit_price']));
        return [
          ('Productos', '${items.length}'),
          ('Total', money(total)),
          ('Condición', payload['payment_term'] == 'credit' ? 'Crédito' : 'Contado'),
          if (payload['requested_delivery_date'] != null) ('Entrega', payload['requested_delivery_date'].toString()),
        ];
      case 'customer.payment':
        return [
          if (payload['receipt_number'] != null) ('Comprobante', payload['receipt_number'].toString()),
          ('Monto', money(value(payload['amount']))),
          ('Formas de pago', '${(payload['payment_lines'] as List? ?? const []).length}'),
          ('Deudas', '${(payload['allocations'] as List? ?? const []).length}'),
        ];
      case 'visit.no_sale':
        return [('Motivo', payload['reason']?.toString() ?? ''), if ((payload['notes'] ?? '').toString().isNotEmpty) ('Notas', payload['notes'].toString())];
      case 'customer.create':
        return [('Dirección', payload['address']?.toString() ?? '')];
      default:
        return const [];
    }
  }

  /// What the user should do about a rejection, from what the server said.
  static String recommend(String type, int? httpStatus, String message) {
    final text = message.toLowerCase();
    if (httpStatus == 403 || text.contains('no pertenece') || text.contains('asignad')) {
      return 'El cliente o la visita ya no está asignado a tu ruta. Avísale al supervisor; cuando lo corrija, toca Reintentar.';
    }
    if (type == 'customer.payment') {
      return 'Las deudas del cliente cambiaron antes de enviar el abono. El cliente tiene un comprobante impreso: avísale al supervisor y registren el abono de nuevo sobre las deudas actuales.';
    }
    if (type == 'order.create' && (text.contains('presentación') || text.contains('disponible para venta'))) {
      return 'Un producto dejó de venderse. Toma el pedido de nuevo sin ese producto y descarta este.';
    }
    if (text.contains('crédito')) {
      return 'El servidor no aceptó el crédito. Coordina con el supervisor; cuando lo autorice, toca Reintentar.';
    }
    return 'Revisa los datos con tu supervisor. Si ya se corrigió en el sistema, toca Reintentar; si no aplica, Descártalo.';
  }
}
