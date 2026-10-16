import 'dart:convert';

import '../../../core/location_capture.dart';
import '../../../data/database.dart';
import '../../preventa/data/preventa_models.dart' show LocalCustomer;
import 'delivery_models.dart';

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
    if (operation.type != 'delivery.depart') continue;
    // Accepted before the last download: the server data already says it left.
    if (operation.status == OutboxStatus.done && pulledAt != null && !(operation.processedAt?.isAfter(pulledAt) ?? false)) continue;
    final payload = (jsonDecode(operation.payload) as Map).cast<String, dynamic>();
    final run = runs[payload['delivery_run_id']?.toString()];
    if (run == null) continue;
    runs[run.id] = operation.status == OutboxStatus.rejected
        ? run.copyWith(departureRejection: operation.message ?? 'El servidor no aceptó la salida.')
        : run.copyWith(departurePending: run.status == 'loaded');
  }

  return runs.values.toList();
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
  static Map<String, dynamic> depart({required String runId, required DateTime at, required LocationCapture location}) => {'delivery_run_id': runId, 'location': location.toPayload(at)};
}
