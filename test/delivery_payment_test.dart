import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/preventa/data/preventista_repository.dart' show CustomerBalance;
import 'package:proximus_app/features/preventa/documents/payment_receipt.dart' show ReceiptFormat;
import 'package:proximus_app/features/reparto/data/delivery_models.dart';
import 'package:proximus_app/features/reparto/data/delivery_repository.dart';
import 'package:proximus_app/features/reparto/data/settlement_draft.dart';
import 'package:proximus_app/features/reparto/documents/delivery_invoice.dart';
import 'package:proximus_app/features/reparto/presentation/delivery_payment_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore, runJson, stopJson;

DecimalValue d(String value) => DecimalValue.parse(value);

const _reference = {'card', 'check'};

/// A run whose first stop was delivered (L 36) and waits for the payment.
Map<String, dynamic> deliveredRun({String term = 'cash'}) => {
  ...runJson(status: 'in_transit'),
  'orders': [
    {
      ...stopJson(1, term: term),
      'status': 'awaiting_payment',
      'outcome_status': 'partially_delivered',
      'delivered_total': '36.0000',
      'balance_due': '36.0000',
      'receiver_name': 'Doña Marta',
      'items': [
        {
          'id': 'i1',
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
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('one method for everything by default; combined methods must add up and credit needs its reason when over the limit', () {
    var draft = SettlementDraft.start(d('100'), credit: false);
    expect(draft.problems(requiringReference: _reference, allowsCredit: false, available: null), isEmpty);
    expect(draft.collected, d('100'));

    draft = draft.updateAt(0, draft.lines.first.copyWith(amount: d('60'))).addMethod('card');
    expect(draft.lines.last.amount, d('40'), reason: 'the new method takes what is left');
    expect(draft.problems(requiringReference: _reference, allowsCredit: false, available: null), ['Falta la referencia del pago.']);
    draft = draft.updateAt(1, draft.lines.last.copyWith(reference: 'POS 1234'));
    expect(draft.problems(requiringReference: _reference, allowsCredit: false, available: null), isEmpty);
    expect(draft.removeAt(1).lines.single.amount, d('100'), reason: 'back to one method, it takes everything');

    final credit = SettlementDraft.start(d('100'), credit: true);
    expect(credit.problems(requiringReference: _reference, allowsCredit: true, available: d('500')), isEmpty);
    expect(credit.problems(requiringReference: _reference, allowsCredit: true, available: d('20')), ['Explica por qué se da crédito por encima de lo autorizado.']);
    expect(credit.withCreditReason('Cliente de años').problems(requiringReference: _reference, allowsCredit: false, available: null), isEmpty);
    expect(credit.collected.isZero, isTrue);
  });

  test('a payment saved on the phone finishes the stop, counts the cash and keeps the invoice to reprint', () {
    final payment = OutboxData(
      id: 3,
      clientReference: 'M004:cobro',
      type: 'delivery.payment',
      payload: jsonEncode({
        'delivery_run_id': 'run1',
        'run_order_id': 'ro1',
        'invoice_number': 'FAC-M004-000001',
        'allocations': [
          {'method': 'cash', 'amount': '30', 'receipt_number': 'REC-M004-000001'},
          {'method': 'credit', 'amount': '6'},
        ],
        'invoice': {'number': 'FAC-M004-000001'},
      }),
      status: OutboxStatus.pending,
      summary: 'Pulpería',
      attempts: 0,
      createdAt: DateTime(2026, 10, 15, 10),
    );
    final run = mergeDeliveryRuns(records: [deliveredRun()], outbox: [payment], customers: const [], pulledAt: null).single;
    final stop = run.stops.first;

    expect(stop.progress, StopProgress.done);
    expect(stop.statusLabel, 'Entrega parcial');
    expect(stop.collectedTotal, d('30'), reason: 'credit is not cash in hand');
    expect(stop.invoice?['number'], 'FAC-M004-000001');
    expect(run.pendingStops, isEmpty);
  });

  test('the invoice prints as an 80 mm ticket and as a letter page, and survives a round trip', () async {
    final invoice = DeliveryInvoice(
      number: 'FAC-M004-000001',
      issuedAt: DateTime(2026, 10, 15, 10, 30),
      company: const {'commercial_name': 'Inversiones Lopez', 'rtn': '0406'},
      customerName: 'Pulpería Doña Marta',
      customerCode: 'CAMPO-01',
      customerAddress: 'Centro',
      runNumber: 'RUT-2026-000013',
      orderNumber: 'PED-2026-000041',
      deliveredBy: 'Repartidor',
      receiverName: 'Doña Marta',
      items: [(name: 'Arroz 1 lb', presentation: 'Unidad', quantity: d('2'), unitPrice: d('18'))],
      lines: [
        (label: 'Efectivo', reference: null, receiptNumber: 'REC-M004-000001', amount: d('30'), isCredit: false),
        (label: 'Crédito', reference: null, receiptNumber: null, amount: d('6'), isCredit: true),
      ],
      total: d('36'),
    );
    for (final format in ReceiptFormat.values) {
      final bytes = await buildInvoicePdf(invoice, format);
      expect(utf8.decode(bytes.sublist(0, 5), allowMalformed: true), '%PDF-');
    }
    final copy = DeliveryInvoice.fromJson(invoice.toJson());
    expect(copy.onCredit, d('6'));
    expect(copy.paid, d('30'));
  });

  testWidgets('cash payment: the invoice and the receipt take the next numbers of this phone', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      secureStoreProvider.overrideWithValue(MemorySecureStore(Session(
        serverUrl: 'http://test',
        token: 't',
        user: const {'id': 4, 'name': 'Repartidor', 'role': 'repartidor'},
        device: const {'code': 'M004'},
        abilities: const ['deliveries:execute'],
      ))),
      apiProvider.overrideWithValue(null),
      manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({
        'operations': ['delivery.payment'],
        'company': {'commercial_name': 'Inversiones Lopez'},
        'catalogs': {
          'settlement_methods': [
            {'value': 'cash', 'label': 'Efectivo', 'requires_reference': false},
            {'value': 'card', 'label': 'Tarjeta', 'requires_reference': true},
            {'value': 'credit', 'label': 'Crédito', 'requires_reference': false},
          ],
        },
      }))),
      localRecordsProvider('delivery_runs').overrideWith((ref) => Stream.value([deliveredRun()])),
      localRecordsProvider('customers').overrideWith((ref) => Stream.value(const [])),
      customerBalancesProvider.overrideWithValue({
        'c1': CustomerBalance(allowsCredit: false, limit: DecimalValue.zero, outstanding: DecimalValue.zero, overdue: DecimalValue.zero, available: DecimalValue.zero),
      }),
    ]);
    await tester.runAsync(() async {
      await container.read(sessionProvider.future);
      await container.read(outboxProvider).adoptServerSeries({
        'invoice': {'prefix': 'FAC-M004-', 'last_number': 0},
        'receipt': {'prefix': 'REC-M004-', 'last_number': 0},
      });
    });

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: DeliveryPaymentScreen(runId: 'run1', stopId: 'ro1'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('L 36.00'), findsWidgets);

    await tester.runAsync(() async {
      await tester.tap(find.text('Cobrar L 36.00 y facturar'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();

    final row = await tester.runAsync(() => db.select(db.outbox).getSingle());
    final payload = jsonDecode(row!.payload) as Map<String, dynamic>;
    expect(row.type, 'delivery.payment');
    expect(payload['invoice_number'], 'FAC-M004-000001');
    expect(payload['allocations'], [
      {'method': 'cash', 'amount': '36', 'reference': null, 'receipt_number': 'REC-M004-000001'},
    ]);
    expect((payload['invoice'] as Map)['items'], [
      {'name': 'Arroz 1 lb', 'presentation': 'Unidad', 'quantity': '2', 'unit_price': '18'},
    ], reason: 'only what was delivered is invoiced');
    expect(find.text('FAC-M004-000001'), findsOneWidget, reason: 'the invoice opens right away to print');
    expect(find.text('Imprimir ticket 80 mm'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      container.dispose();
      await db.close();
    });
  });
}
