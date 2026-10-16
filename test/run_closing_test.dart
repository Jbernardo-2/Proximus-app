import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/preventa/documents/payment_receipt.dart' show ReceiptFormat;
import 'package:proximus_app/features/reparto/data/delivery_repository.dart';
import 'package:proximus_app/features/reparto/data/run_closing.dart';
import 'package:proximus_app/features/reparto/documents/run_closing_pdf.dart';
import 'package:proximus_app/features/reparto/presentation/run_closing_screen.dart';
import 'package:proximus_app/features/reparto/presentation/truck_load_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore, runJson, stopJson;

DecimalValue d(String value) => DecimalValue.parse(value);

final today = DateTime(2026, 10, 16, 17);

/// Stop 1 paid on the server (cash 30 + transfer 20, 6 on credit), stop 2 delivered
/// with a return and paid on the phone, stop 3 not delivered, stop 4 still loaded.
Map<String, dynamic> closingRun() => {
  ...runJson(status: 'in_transit'),
  'orders': [
    {
      ...stopJson(1),
      'status': 'delivered',
      'delivered_total': '56.0000',
      'collected_total': '50.0000',
      'balance_due': '6.0000',
      'payments': [
        {'method': 'cash', 'amount': '30.0000', 'status': 'active'},
        {'method': 'bank_transfer', 'amount': '20.0000', 'status': 'active'},
        {'method': 'cash', 'amount': '99.0000', 'status': 'voided'},
      ],
    },
    {
      ...stopJson(2),
      'status': 'awaiting_payment',
      'outcome_status': 'partially_delivered',
      'delivered_total': '36.0000',
      'balance_due': '36.0000',
      'items': [
        {
          'id': 'i2',
          'product_id': 'p1',
          'product_name': 'Arroz 1 lb',
          'presentation_name': 'Unidad',
          'unit_price': '18.0000',
          'requested_quantity': '3.000000',
          'loaded_quantity': '3.000000',
          'delivered_quantity': '2.000000',
          'returned_quantity': '1.000000',
          'damaged_quantity': '0.000000',
          'missing_quantity': '0.000000',
        },
      ],
    },
    {...stopJson(3), 'status': 'not_delivered'},
    stopJson(4),
  ],
};

OutboxData row(int id, String type, Map<String, dynamic> payload, {String status = OutboxStatus.done, DateTime? at}) => OutboxData(
  id: id,
  clientReference: 'M004:$id',
  type: type,
  payload: jsonEncode(payload),
  status: status,
  summary: '',
  attempts: 0,
  createdAt: at ?? today,
  processedAt: status == OutboxStatus.pending ? null : (at ?? today),
);

List<OutboxData> outbox() => [
  row(1, 'delivery.payment', {
    'delivery_run_id': 'run1',
    'run_order_id': 'ro2',
    'allocations': [
      {'method': 'cash', 'amount': '36'},
    ],
  }, status: OutboxStatus.pending),
  row(2, 'customer.payment', {
    'customer_id': 'c3',
    'payment_lines': [
      {'method': 'cash', 'amount': '100'},
      {'method': 'card', 'amount': '50'},
    ],
  }),
  row(3, 'customer.payment', {'customer_id': 'ajeno', 'payment_lines': [{'method': 'cash', 'amount': '500'}]}),
  row(4, 'customer.payment', {'customer_id': 'c3', 'payment_lines': [{'method': 'cash', 'amount': '70'}]}, at: today.subtract(const Duration(days: 1))),
  row(5, 'customer.payment', {'customer_id': 'c3', 'payment_lines': [{'method': 'cash', 'amount': '40'}]}, status: OutboxStatus.rejected),
];

void main() {
  truckLoadTests();

  test('the closing counts every way money came in, the credit, and what goes back to the warehouse', () {
    final rows = outbox();
    final run = mergeDeliveryRuns(records: [closingRun()], outbox: rows, customers: const [], pulledAt: today.subtract(const Duration(hours: 1))).single;
    final closing = RunClosing.of(run, rows, now: today);

    expect(closing.delivered, 1);
    expect(closing.partial, 1, reason: 'stop 2 is paid on the phone');
    expect(closing.notDelivered, 1);
    expect(closing.open, 1);
    expect(closing.deliveries, {'cash': d('66'), 'bank_transfer': d('20')}, reason: 'voided payments do not count');
    expect(closing.accountPayments, {'cash': d('100'), 'card': d('50')}, reason: 'since the departure (today, as it has not reached the server), only customers of this run, never rejected ones');
    expect(closing.accountPaymentCount, 1);
    expect(closing.cash, d('166'));
    expect(closing.collected, d('236'));
    expect(closing.credit, d('6'));
    expect(closing.returns.single.returned, d('1'));
    expect(closing.unsent, 1);
    expect(closing.rejected, 1);
    expect(closing.isFinal, isFalse);
  });

  test('a run that left yesterday counts the account payments since it left, as the web does', () {
    final rows = outbox();
    final run = mergeDeliveryRuns(
      records: [
        {...closingRun(), 'departed_at': today.subtract(const Duration(days: 1, hours: 2)).toUtc().toIso8601String()},
      ],
      outbox: rows,
      customers: const [],
      pulledAt: null,
    ).single;

    expect(RunClosing.of(run, rows, now: today).accountPayments['cash'], d('170'), reason: '100 today + 70 yesterday, after the departure');
  });

  testWidgets('the closing screen leads with the cash to hand over and warns while it is preliminary', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(MemorySecureStore(null)),
        apiProvider.overrideWithValue(null),
        manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({
          'catalogs': {
            'settlement_methods': [
              {'value': 'cash', 'label': 'Efectivo'},
              {'value': 'bank_transfer', 'label': 'Transferencia bancaria'},
            ],
            'payment_methods': [
              {'value': 'card', 'label': 'Tarjeta'},
            ],
          },
        }))),
        outboxRowsProvider.overrideWith((ref) => Stream.value(outbox())),
        syncStateProvider('pulled_at:delivery_runs').overrideWith((ref) => Stream.value(null)),
        localRecordsProvider('delivery_runs').overrideWith((ref) => Stream.value([closingRun()])),
        localRecordsProvider('customers').overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: RunClosingScreen(runId: 'run1')),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Efectivo a entregar'), findsOneWidget);
    expect(find.textContaining('Cierre preliminar'), findsOneWidget);
    expect(find.text('Transferencia bancaria'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Imprimir ticket 80 mm'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Imprimir ticket 80 mm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the closing prints as a ticket and as a letter page', () async {
    final rows = outbox();
    final run = mergeDeliveryRuns(records: [closingRun()], outbox: rows, customers: const [], pulledAt: null).single;
    for (final format in ReceiptFormat.values) {
      final bytes = await buildRunClosingPdf(run: run, closing: RunClosing.of(run, rows, now: today), driver: 'Repartidor', methodLabels: const {'cash': 'Efectivo'}, format: format);
      expect(utf8.decode(bytes.sublist(0, 5), allowMalformed: true), '%PDF-');
    }
  });
}

void truckLoadTests() {
  test('the truck load adds every order up by product and shows what should still be on board', () {
    final rows = outbox();
    final run = mergeDeliveryRuns(records: [closingRun()], outbox: rows, customers: const [], pulledAt: null).single;
    final rice = truckLoad(run).single;

    expect(rice.product, 'Arroz 1 lb');
    expect(rice.loaded, d('12'), reason: '4 stops x 3 loaded');
    expect(rice.delivered, d('2'), reason: 'only stop 2 recorded what it delivered');
    expect(rice.loaded - rice.delivered - rice.missing, d('10'));
  });
}
