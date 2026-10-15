import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/preventa/data/customer_profile.dart';
import 'package:proximus_app/features/preventa/data/preventa_models.dart';
import 'package:proximus_app/features/preventa/data/preventa_operations.dart';
import 'package:proximus_app/features/preventa/data/preventista_repository.dart';
import 'package:proximus_app/features/preventa/presentation/customer_screen.dart';

OutboxData queued(int id, String type, Map<String, dynamic> payload, {String status = OutboxStatus.pending, DateTime? processedAt, Map<String, dynamic>? result}) => OutboxData(
      id: id,
      clientReference: 'M001:0f1e2d3c-$id',
      type: type,
      payload: jsonEncode(payload),
      status: status,
      summary: '',
      attempts: 0,
      createdAt: DateTime(2026, 10, 14, 8),
      processedAt: processedAt,
      result: result == null ? null : jsonEncode(result),
    );

const customerJson = {
  'id': 'c1',
  'code': 'CLI-1',
  'business_name': 'Pulpería Doña Marta',
  'business_type': 'Pulpería',
  'address': 'Barrio El Centro, frente a la escuela',
  'contact_name': 'Marta López',
  'phone': '9999-0001',
};

CustomerSources sources({List<OutboxData> outbox = const [], DateTime? pulledAt}) => CustomerSources(
      customers: const [customerJson],
      credits: const [
        {'customer_id': 'c1', 'allows_credit': true, 'credit_limit': '5000', 'outstanding': '800', 'overdue': '300', 'committed': '0', 'available_credit': '4200'},
      ],
      receivables: const [
        {'id': 'r1', 'customer_id': 'c1', 'document_number': 'SAL-1', 'original_amount': '300', 'outstanding_amount': '300', 'is_overdue': true, 'due_date': '2026-10-01'},
        {'id': 'r2', 'customer_id': 'c1', 'document_number': 'PED-2026-000010', 'original_amount': '500', 'outstanding_amount': '500', 'is_overdue': false, 'due_date': '2026-10-30'},
      ],
      orders: const [
        {'id': 'o1', 'customer_id': 'c1', 'order_number': 'PED-2026-000020', 'client_reference': 'M001:aaa', 'order_date': '2026-10-10', 'status': 'delivered', 'status_label': 'Entregado', 'payment_term': 'cash', 'total': '150.0000', 'items_count': 2},
      ],
      outbox: outbox,
      pulledAt: {'customer_credit': pulledAt, 'receivables': pulledAt, 'recent_orders': pulledAt},
    );

void main() {
  const repository = PreventistaRepository();

  test('open debts already reflect payments applied on the phone', () {
    final profile = repository.customerProfile(
      'c1',
      sources(outbox: [
        queued(1, 'customer.payment', {
          'customer_id': 'c1',
          'amount': '350',
          'allocations': [
            {'receivable_id': 'r1', 'amount': '300'},
            {'receivable_id': 'r2', 'amount': '50'},
          ],
        }),
      ]),
    )!;

    expect(profile.receivables.map((debt) => debt.id), ['r2'], reason: 'the overdue debt was paid in full');
    expect(profile.receivables.single.outstanding.toFixed(2), '450.00');
    expect(profile.balance!.outstanding.toFixed(2), '450.00');
    expect(profile.balance!.available.toFixed(2), '4550.00');
  });

  test('orders on the phone show with a temporary reference and are not duplicated once downloaded', () {
    final pulledAt = DateTime(2026, 10, 14, 9);
    final profile = repository.customerProfile(
      'c1',
      sources(pulledAt: pulledAt, outbox: [
        queued(1, 'order.create', {'customer_id': 'c1', 'order_date': '2026-10-14', 'payment_term': 'credit', 'items': [{'quantity': '3', 'unit_price': '20'}]}),
        queued(2, 'order.create', {'customer_id': 'c1', 'order_date': '2026-10-13', 'items': [{'quantity': '1', 'unit_price': '10'}]},
            status: OutboxStatus.done, processedAt: DateTime(2026, 10, 14, 8), result: {'order_number': 'PED-2026-000021'}),
      ]),
    )!;

    expect(profile.orders.map((order) => order.reference), ['Temporal 0F1E2D3C', 'PED-2026-000020']);
    expect(profile.orders.first.state, LocalOperationState.pending);
    expect(profile.orders.first.total.toFixed(2), '60.00');
  });

  test('a customer registered offline can be found and opened', () {
    final payload = PreventaOperations.newCustomer(businessName: 'Abarrotería Nueva', address: 'Kennedy', visitDay: 3);
    final data = sources(outbox: [queued(1, 'customer.create', payload)]);

    expect(repository.customers(data).map((customer) => customer.businessName), ['Abarrotería Nueva', 'Pulpería Doña Marta']);
    expect(repository.customerProfile(payload['id'] as String, data)!.receivables, isEmpty);
  });

  testWidgets('the customer profile fits a small phone', (tester) async {
    await initializeDateFormatting('es');
    tester.view.physicalSize = const Size(360 * 2, 740 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final profile = repository.customerProfile('c1', sources())!;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(null),
        manifestProvider.overrideWithValue(const AsyncData(null)),
        customerProfileProvider('c1').overrideWithValue(profile),
        accountEntriesProvider('c1').overrideWith((ref) async => [
              AccountEntry.fromJson(const {'type': 'customer_payment', 'type_label': 'Abono', 'receipt_number': 'ABO-M001-000001', 'debit_amount': '0', 'credit_amount': '200', 'occurred_at': '2026-10-12T15:00:00Z'}),
            ]),
      ],
      child: const MaterialApp(home: CustomerScreen(customerId: 'c1')),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Pulpería Doña Marta'), findsOneWidget);
    expect(find.text('L 4,200.00'), findsOneWidget);
    expect(find.text('L 300.00'), findsWidgets);

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('PED-2026-000020'), 200, scrollable: list);
    await tester.scrollUntilVisible(find.text('-L 200.00'), 200, scrollable: list);
    expect(tester.takeException(), isNull);
  });
}
