import 'dart:convert';

import '../../../core/location_capture.dart';
import '../../../data/database.dart';
import '../../../core/decimal_value.dart';
import '../../preventa/data/preventa_models.dart' show LocalCustomer, LocalOperationState;
import 'delivery_models.dart';
import 'outcome_draft.dart';

/// The driver's runs as they should look right now: what the server sent plus
/// what was recorded on the phone and the server does not reflect yet.
List<LocalDeliveryRun> mergeDeliveryRuns({required List<Map<String, dynamic>> records, required List<OutboxData> outbox, required List<Map<String, dynamic>> customers, required DateTime? pulledAt}) {
  final contacts = {for (final json in customers) json['id'].toString(): LocalCustomer.fromJson(json)};
  final runs = {
    for (final json in records)
      json['id'].toString(): () {
        final run = LocalDeliveryRun.fromJson(json);
        return run.copyWith(stops: [for (final stop in run.stops) contacts[stop.customerId] == null ? stop : stop.copyWith(customer: contacts[stop.customerId])]);
      }(),
  };

  for (final operation in outbox) {
    if (operation.type != 'delivery.depart' && operation.type != 'delivery.outcome') continue;
    // Accepted before the last download: the server data already includes it.
    if (operation.status == OutboxStatus.done && pulledAt != null && !(operation.processedAt?.isAfter(pulledAt) ?? false)) continue;
    final payload = (jsonDecode(operation.payload) as Map).cast<String, dynamic>();
    final run = runs[payload['delivery_run_id']?.toString()];
    if (run == null) continue;

    if (operation.type == 'delivery.depart') {
      runs[run.id] = operation.status == OutboxStatus.rejected
          ? run.copyWith(departureRejection: operation.message ?? 'El servidor no aceptó la salida.')
          : run.copyWith(departurePending: run.status == 'loaded');
      continue;
    }

    runs[run.id] = run.copyWith(
      stops: [
        for (final stop in run.stops)
          if (stop.id != payload['run_order_id']?.toString())
            stop
          else if (operation.status == OutboxStatus.rejected)
            stop.copyWith(operationState: LocalOperationState.rejected, rejectionMessage: operation.message ?? 'El servidor no aceptó la entrega.')
          else
            applyOutcome(stop, payload, state: operation.status == OutboxStatus.pending ? LocalOperationState.pending : LocalOperationState.accepted),
      ],
    );
  }

  return runs.values.toList();
}

/// The stop as the server will leave it once it gets this delivery: waiting for the
/// payment when something was delivered, finished when nothing was.
LocalDeliveryStop applyOutcome(LocalDeliveryStop stop, Map<String, dynamic> payload, {required LocalOperationState state}) {
  final results = {for (final item in (payload['items'] as List? ?? const []).cast<Map>()) item['id'].toString(): item};
  final items = [
    for (final item in stop.items)
      results[item.id] == null
          ? item
          : item.withOutcome(
              delivered: DecimalValue.parse(results[item.id]!['delivered_quantity'] ?? '0'),
              returned: DecimalValue.parse(results[item.id]!['returned_quantity'] ?? '0'),
              damaged: DecimalValue.parse(results[item.id]!['damaged_quantity'] ?? '0'),
              missing: DecimalValue.parse(results[item.id]!['missing_quantity'] ?? '0'),
            ),
  ];
  final delivered = items.fold(DecimalValue.zero, (total, item) => total + item.deliveredTotal);
  final anyDelivered = items.any((item) => !(item.delivered ?? DecimalValue.zero).isZero);
  final allRequested = items.every((item) => (item.delivered ?? DecimalValue.zero) == item.requested);
  final outcome = allRequested ? 'delivered' : (anyDelivered ? 'partially_delivered' : 'not_delivered');

  return stop.copyWith(
    items: items,
    status: delivered.isZero ? outcome : 'awaiting_payment',
    statusLabel: delivered.isZero ? 'No entregado' : 'Pendiente de cobro',
    outcomeStatus: outcome,
    deliveredTotal: delivered,
    balanceDue: delivered,
    receiverName: payload['receiver_name']?.toString(),
    outcomeReasonLabel: payload['outcome_reason_label']?.toString(),
    operationState: state,
  );
}

/// The runs the driver still has to work on, in the order they matter: today's first,
/// then the newest. Finished runs (waiting to be settled) are left out.
List<LocalDeliveryRun> runsToWork(List<LocalDeliveryRun> runs, {DateTime? now}) {
  final today = now ?? DateTime.now();
  bool isToday(LocalDeliveryRun run) => run.scheduledDate != null && run.scheduledDate!.year == today.year && run.scheduledDate!.month == today.month && run.scheduledDate!.day == today.day;

  return [
    for (final run in runs)
      if (run.needsDriver) run,
  ]..sort((a, b) {
    if (isToday(a) != isToday(b)) return isToday(a) ? -1 : 1;
    return (b.scheduledDate ?? DateTime(0)).compareTo(a.scheduledDate ?? DateTime(0));
  });
}

/// Payloads of the driver's operations (contract section 4).
abstract final class DeliveryOperations {
  static Map<String, dynamic> outcome({required String runId, required String stopId, required OutcomeDraft draft, required DateTime at, required LocationCapture location, String? reasonLabel}) => {
    'delivery_run_id': runId,
    'run_order_id': stopId,
    'receiver_name': draft.anyDelivered ? draft.receiverName.trim() : null,
    'outcome_reason': draft.allDelivered ? null : draft.reason,
    'outcome_notes': draft.notes.trim().isEmpty ? null : draft.notes.trim(),
    'items': draft.payloadItems(),
    'location': location.toPayload(at),
    // Kept on the phone to show the reason before the server answers; the server ignores it.
    'outcome_reason_label': draft.allDelivered ? null : reasonLabel,
  };

  static Map<String, dynamic> depart({required String runId, required DateTime at, required LocationCapture location}) => {'delivery_run_id': runId, 'location': location.toPayload(at)};
}
