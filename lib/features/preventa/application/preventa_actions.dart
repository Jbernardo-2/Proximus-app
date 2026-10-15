import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/location_capture.dart';
import '../data/preventa_models.dart';
import '../data/preventa_operations.dart';

/// Records the preventista's facts: first on the phone, then sent if there is signal.
class PreventaActions {
  PreventaActions(this._ref);

  final Ref _ref;

  Future<void> recordNoSale({
    required LocalRouteActivity stop,
    required String reason,
    required LocationSession location,
    String? notes,
  }) async {
    final session = _ref.read(sessionProvider).value!;
    final at = DateTime.now();
    final position = await location.take();
    await _ref.read(outboxProvider).enqueue(
          deviceCode: session.deviceCode,
          type: 'visit.no_sale',
          summary: stop.customer.businessName,
          build: (_) async => PreventaOperations.noSale(
            customerId: stop.customer.id,
            reason: reason,
            notes: notes,
            at: at,
            location: position,
          ),
        );
    _send();
  }

  void _send() => _ref.read(syncProvider.notifier).sync(pushOnly: true);
}

final preventaActionsProvider = Provider<PreventaActions>(PreventaActions.new);
