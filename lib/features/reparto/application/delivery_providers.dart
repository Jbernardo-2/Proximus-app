import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/location_capture.dart';
import '../data/delivery_models.dart';
import '../data/delivery_repository.dart';
import '../data/outcome_draft.dart';

/// The driver's runs with what the phone recorded and the server has not reflected yet.
final deliveryRunsProvider = Provider<AsyncValue<List<LocalDeliveryRun>>>((ref) {
  final records = ref.watch(localRecordsProvider('delivery_runs'));
  final outbox = ref.watch(outboxRowsProvider);
  final pulledAt = ref.watch(syncStateProvider('pulled_at:delivery_runs'));
  final customers = ref.watch(localRecordsProvider('customers')).value ?? const [];

  if (records.isLoading || outbox.isLoading || pulledAt.isLoading) return const AsyncLoading();
  final error = records.error ?? outbox.error ?? pulledAt.error;
  if (error != null) return AsyncError(error, StackTrace.current);

  return AsyncData(
    mergeDeliveryRuns(records: records.requireValue, outbox: outbox.requireValue, customers: customers, pulledAt: pulledAt.requireValue == null ? null : DateTime.tryParse(pulledAt.requireValue!)),
  );
});

final deliveryRunProvider = Provider.family<LocalDeliveryRun?, String>((ref, runId) => ref.watch(deliveryRunsProvider).value?.where((run) => run.id == runId).firstOrNull);

/// Records the driver's facts: first on the phone, then sent if there is signal.
class DeliveryActions {
  DeliveryActions(this._ref);

  final Ref _ref;

  /// The truck leaves the warehouse. Works without signal.
  Future<void> depart(LocalDeliveryRun run, {required LocationSession location}) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null) throw StateError('La sesión se cerró. Inicia sesión de nuevo.');
    if (run.hasLeft) return;
    final at = DateTime.now();
    final position = await location.take();
    await _ref
        .read(outboxProvider)
        .enqueue(
          deviceCode: session.deviceCode,
          type: 'delivery.depart',
          summary: 'Jornada ${run.runNumber}',
          build: (_) async => DeliveryOperations.depart(runId: run.id, at: at, location: position),
        );
    _ref.read(syncProvider.notifier).sync(pushOnly: true);
  }

  /// What was delivered, returned, damaged or missing at a stop. If the driver never
  /// tapped "Salir", the departure is recorded first: the server needs it before.
  Future<void> recordOutcome(LocalDeliveryRun run, LocalDeliveryStop stop, OutcomeDraft draft, {required LocationSession location, String? reasonLabel}) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null) throw StateError('La sesión se cerró. Inicia sesión de nuevo.');
    final problems = draft.problems();
    if (problems.isNotEmpty) throw StateError(problems.first);
    final at = DateTime.now();
    final position = await location.take();
    final outbox = _ref.read(outboxProvider);

    if (!run.hasLeft) {
      await outbox.enqueue(
        deviceCode: session.deviceCode,
        type: 'delivery.depart',
        summary: 'Jornada ${run.runNumber}',
        build: (_) async => DeliveryOperations.depart(runId: run.id, at: at, location: position),
      );
    }
    await outbox.enqueue(
      deviceCode: session.deviceCode,
      type: 'delivery.outcome',
      summary: stop.customerName,
      build: (_) async => DeliveryOperations.outcome(runId: run.id, stopId: stop.id, draft: draft, at: at, location: position, reasonLabel: reasonLabel),
    );
    _ref.read(syncProvider.notifier).sync(pushOnly: true);
  }
}

final deliveryActionsProvider = Provider<DeliveryActions>(DeliveryActions.new);
