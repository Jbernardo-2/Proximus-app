import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decimal_value.dart';
import '../data/order_draft.dart';
import '../data/preventa_models.dart';

/// The order being taken for a customer, shared by the cart and the product search
/// while the order screen is open. Discarded when it closes.
class OrderDraftController extends AutoDisposeFamilyNotifier<OrderDraft?, String> {
  @override
  OrderDraft? build(String customerId) => null;

  void start(String routeStopId) {
    if (state != null) return;
    final today = DateTime.now();
    state = OrderDraft(
      customerId: arg,
      routeStopId: routeStopId,
      day: today,
      deliveryDate: DateTime(today.year, today.month, today.day + 1),
    );
  }

  /// A presentation already in the order gets its quantity replaced; a new one is added
  /// at the end (the cart shows the newest first).
  void put(LocalProduct product, LocalPresentation presentation, DecimalValue quantity) {
    final draft = state;
    if (draft == null) return;
    state = draft.setQuantity(product, presentation, quantity);
  }

  void remove(String presentationId) => state = state?.remove(presentationId);

  void terms({String? paymentTerm, DateTime? deliveryDate}) => state = state?.withTerms(paymentTerm: paymentTerm, deliveryDate: deliveryDate);
}

final orderDraftProvider = NotifierProvider.autoDispose.family<OrderDraftController, OrderDraft?, String>(OrderDraftController.new);
