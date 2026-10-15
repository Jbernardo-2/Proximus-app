import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/location_capture.dart';
import '../../../data/database.dart';
import '../data/order_draft.dart';
import '../data/payment_draft.dart';
import '../documents/payment_receipt.dart';
import '../data/preventa_models.dart';
import '../data/preventa_operations.dart';

/// Records the preventista's facts: first on the phone, then sent if there is signal.
class PreventaActions {
  PreventaActions(this._ref);

  final Ref _ref;

  Future<void> recordNoSale({
    required LocalCustomer customer,
    String? routeStopId,
    required String reason,
    required LocationSession location,
    String? notes,
  }) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null) throw StateError('La sesión se cerró. Inicia sesión de nuevo.');
    final at = DateTime.now();
    final position = await location.take();
    await _ref.read(outboxProvider).enqueue(
          deviceCode: session.deviceCode,
          type: 'visit.no_sale',
          summary: customer.businessName,
          build: (_) async => PreventaOperations.noSale(
            customerId: customer.id,
            routeStopId: routeStopId,
            reason: reason,
            notes: notes,
            at: at,
            location: position,
          ),
        );
    _send();
  }

  /// Registers a customer with ids made here, so an order or a no-sale visit can
  /// follow right away without signal. Returns the new customer's id.
  Future<String> registerCustomer({
    required String businessName,
    required String address,
    required int visitDay,
    String? salesRouteId,
    String? businessType,
    String? contactName,
    String? phone,
    String? whatsapp,
    String? reference,
    String? notes,
    LocationSession? location,
  }) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null) throw StateError('La sesión se cerró. Inicia sesión de nuevo.');
    // The customer's position is kept for good, so this waits a little longer for a fix.
    final position = await location?.take(grace: const Duration(seconds: 8));
    final payload = PreventaOperations.newCustomer(
      businessName: businessName,
      address: address,
      visitDay: visitDay,
      salesRouteId: salesRouteId,
      businessType: businessType,
      contactName: contactName,
      phone: phone,
      whatsapp: whatsapp,
      reference: reference,
      notes: notes,
      location: position,
    );
    await _ref.read(outboxProvider).enqueue(
          deviceCode: session.deviceCode,
          type: 'customer.create',
          summary: businessName,
          build: (_) async => payload,
        );
    _send();
    return payload['id'] as String;
  }

  /// Saves the order on the phone (confirmed) and sends it if there is signal.
  /// Returns the queued operation so the screen can show its temporary reference.
  Future<OutboxData> placeOrder({required OrderDraft draft, required String customerName, required LocationSession location}) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null) throw StateError('La sesión se cerró. Inicia sesión de nuevo.');
    if (draft.isEmpty) throw StateError('Agrega al menos un producto.');
    final at = DateTime.now();
    final position = await location.take();
    final operation = await _ref.read(outboxProvider).enqueue(
          deviceCode: session.deviceCode,
          type: 'order.create',
          summary: customerName,
          build: (_) async => PreventaOperations.order(
            customerId: draft.customerId,
            routeStopId: draft.routeStopId,
            takenAt: at,
            paymentTerm: draft.paymentTerm,
            deliveryDate: draft.deliveryDate,
            notes: draft.notes,
            items: [
              for (final line in draft.lines) (presentationId: line.presentation.id, quantity: line.quantity, unitPrice: line.unitPrice, notes: null),
            ],
            location: position,
          ),
        );
    _send();
    return operation;
  }

  /// Registers an account payment with a receipt number of this phone's series and
  /// returns the receipt to print or share right away.
  Future<PaymentReceipt> recordPayment({
    required LocalCustomer customer,
    required PaymentDraft draft,
    required LocationSession location,
  }) async {
    final session = _ref.read(sessionProvider).value;
    if (session == null) throw StateError('La sesión se cerró. Inicia sesión de nuevo.');
    final manifest = _ref.read(manifestProvider).value;
    final methodLabels = {for (final option in manifest?.options('payment_methods') ?? const <({String value, String label})>[]) option.value: option.label};
    final at = DateTime.now();
    final position = await location.take();
    late PaymentReceipt receipt;

    await _ref.read(outboxProvider).enqueue(
          deviceCode: session.deviceCode,
          type: 'customer.payment',
          summary: customer.businessName,
          build: (number) async {
            final receiptNumber = await number('customer_payment');
            final applied = [for (final debt in draft.debts) if (draft.allocations.containsKey(debt.id)) debt];
            receipt = PaymentReceipt(
              number: receiptNumber,
              issuedAt: at,
              company: manifest?.company ?? const {},
              customerName: customer.businessName,
              customerCode: customer.code,
              collectedBy: session.userName,
              lines: [
                for (final line in draft.lines) (label: methodLabels[line.method] ?? line.method, reference: line.reference, amount: line.amount),
              ],
              allocations: [
                for (final debt in applied) (document: debt.documentNumber ?? 'Saldo', before: debt.outstanding, applied: draft.allocations[debt.id]!),
              ],
              total: draft.amount,
              debtBefore: draft.totalDebt,
            );
            return {
              ...PreventaOperations.accountPayment(
                customerId: customer.id,
                receiptNumber: receiptNumber,
                amount: draft.amount,
                lines: [for (final line in draft.lines) (method: line.method, amount: line.amount, reference: line.reference)],
                allocations: [for (final entry in draft.allocations.entries) (receivableId: entry.key, amount: entry.value)],
                at: at,
                location: position,
              ),
              // Kept on the phone to reprint the receipt; the server ignores it.
              'receipt': receipt.toJson(),
            };
          },
        );
    _send();
    return receipt;
  }

  void _send() => _ref.read(syncProvider.notifier).sync(pushOnly: true);
}

final preventaActionsProvider = Provider<PreventaActions>(PreventaActions.new);
