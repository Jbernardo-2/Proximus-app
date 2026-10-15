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
import 'package:proximus_app/features/preventa/data/customer_profile.dart';
import 'package:proximus_app/features/preventa/data/payment_draft.dart';
import 'package:proximus_app/features/preventa/data/preventa_models.dart';
import 'package:proximus_app/features/preventa/documents/payment_receipt.dart';
import 'package:proximus_app/features/preventa/presentation/payment_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

DecimalValue d(String value) => DecimalValue.parse(value);

final debts = [
  LocalReceivable(id: 'r-new', customerId: 'c1', documentNumber: 'PED-2026-000030', originalAmount: d('500'), outstanding: d('500'), isOverdue: false, dueDate: DateTime(2026, 10, 30)),
  LocalReceivable(id: 'r-old', customerId: 'c1', documentNumber: 'SAL-1', originalAmount: d('300'), outstanding: d('300'), isOverdue: true, dueDate: DateTime(2026, 10, 1)),
];

class MemorySecureStore extends SecureStore {
  MemorySecureStore(this.current);

  Session? current;

  @override
  Future<Session?> session() async => current;
}

void main() {
  test('the amount pays the oldest debts first and can be redistributed by hand', () {
    var draft = PaymentDraft.start(debts).withAmount(d('350'));
    expect(draft.allocations, {'r-old': d('300'), 'r-new': d('50')});
    expect(draft.lines.single.amount, d('350'), reason: 'a single method follows the amount');
    expect(draft.problems(methodsRequiringReference: const {}), isEmpty);

    draft = draft.withAllocation('r-old', d('100'));
    expect(draft.amount, d('150'));
    expect(draft.lines.single.amount, d('150'));

    draft = draft.withLines([PaymentLine(method: 'cash', amount: d('100')), PaymentLine(method: 'card', amount: d('50'))]);
    expect(draft.problems(methodsRequiringReference: const {'card'}), ['Falta la referencia del pago.']);
    draft = draft.withLines([PaymentLine(method: 'cash', amount: d('100')), PaymentLine(method: 'card', amount: d('40'), reference: 'POS-1')]);
    expect(draft.problems(methodsRequiringReference: const {'card'}), ['Las formas de pago no suman el abono.']);
  });

  test('nothing above the debt and nothing that does not add up', () {
    final draft = PaymentDraft.start(debts);
    expect(draft.withAmount(d('900')).problems(methodsRequiringReference: const {}), contains('El abono no puede ser mayor que la deuda (800.00).'));
    expect(draft.problems(methodsRequiringReference: const {}), contains('Escribe el monto del abono.'));
    expect(parseAmount('1,250.50'), d('1250.5'));
    expect(parseAmount('12.345'), isNull);
  });

  test('the receipt prints as an 80 mm ticket and as a letter page', () async {
    final receipt = PaymentReceipt(
      number: 'ABO-M001-000001',
      issuedAt: DateTime(2026, 10, 14, 9, 30),
      company: const {'commercial_name': 'Distribuidora Proximus', 'rtn': '0801', 'address': 'Tegucigalpa'},
      customerName: 'Pulpería Doña Marta',
      customerCode: 'CLI-1',
      collectedBy: 'Ana Preventista',
      lines: [(label: 'Efectivo', reference: null, amount: d('350'))],
      allocations: [(document: 'SAL-1', before: d('300'), applied: d('300')), (document: 'PED-2026-000030', before: d('500'), applied: d('50'))],
      total: d('350'),
      debtBefore: d('800'),
    );

    for (final format in ReceiptFormat.values) {
      final bytes = await buildReceiptPdf(receipt, format);
      expect(utf8.decode(bytes.sublist(0, 5), allowMalformed: true), '%PDF-');
    }
    expect(PaymentReceipt.fromJson(receipt.toJson()).debtAfter, d('450'));
  });

  testWidgets('registering a payment issues a receipt numbered by the phone', (tester) async {
    await initializeDateFormatting('es');
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final session = Session(
      serverUrl: 'http://test',
      token: 't',
      user: const {'id': 7, 'name': 'Ana Preventista', 'role': 'preventista'},
      device: const {'code': 'M001'},
      abilities: const ['payments:record'],
    );
    final manifest = SyncManifest.fromJson({
      'operations': ['customer.payment'],
      'company': {'commercial_name': 'Distribuidora Proximus'},
      'catalogs': {
        'payment_methods': [
          {'value': 'cash', 'label': 'Efectivo', 'requires_reference': false},
          {'value': 'bank_transfer', 'label': 'Transferencia', 'requires_reference': false},
        ],
      },
    });
    final profile = CustomerProfile(
      customer: const LocalCustomer(id: 'c1', code: 'CLI-1', businessName: 'Pulpería Doña Marta', address: 'Centro'),
      balance: null,
      receivables: debts,
      orders: const [],
    );
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      secureStoreProvider.overrideWithValue(MemorySecureStore(session)),
      apiProvider.overrideWithValue(null),
      manifestProvider.overrideWithValue(AsyncData(manifest)),
      customerProfileProvider('c1').overrideWithValue(profile),
    ]);
    await tester.runAsync(() async {
      await container.read(sessionProvider.future);
      await container.read(outboxProvider).adoptServerSeries({'customer_payment': {'prefix': 'ABO-M001-', 'last_number': 0}});
    });

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: PaymentScreen(customerId: 'c1'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Monto del abono'), '350');
    await tester.pumpAndSettle();
    expect(find.text('L 300.00'), findsWidgets);
    expect(find.text('Registrar abono de L 350.00'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await tester.tap(find.text('Registrar abono de L 350.00'));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();

    expect(find.text('ABO-M001-000001'), findsOneWidget);
    expect(find.text('Imprimir ticket 80 mm'), findsOneWidget);
    final row = await tester.runAsync(() => db.select(db.outbox).getSingle());
    final payload = jsonDecode(row!.payload) as Map<String, dynamic>;
    expect(row.type, 'customer.payment');
    expect(payload['receipt_number'], 'ABO-M001-000001');
    expect(payload['amount'], '350');
    expect(payload['allocations'], [
      {'receivable_id': 'r-old', 'amount': '300'},
      {'receivable_id': 'r-new', 'amount': '50'},
    ]);
    expect(payload['location']['status'], isNotNull);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      container.dispose();
      await db.close();
    });
  });

  testWidgets('a sync while the payment is open re-applies the amount to the current debts', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    CustomerProfile profileWith(List<LocalReceivable> receivables) => CustomerProfile(
          customer: const LocalCustomer(id: 'c1', code: 'CLI-1', businessName: 'Pulpería Doña Marta', address: 'Centro'),
          balance: null,
          receivables: receivables,
          orders: const [],
        );
    final current = StateProvider<CustomerProfile>((ref) => profileWith(debts));
    final container = ProviderContainer(overrides: [
      apiProvider.overrideWithValue(null),
      manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({'operations': ['customer.payment']}))),
      customerProfileProvider('c1').overrideWith((ref) => ref.watch(current)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: PaymentScreen(customerId: 'c1'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Monto del abono'), '350');
    await tester.pumpAndSettle();

    // Another payment already covered most of SAL-1 (300 -> 100).
    container.read(current.notifier).state = profileWith([
      debts.first,
      LocalReceivable(id: 'r-old', customerId: 'c1', documentNumber: 'SAL-1', originalAmount: d('300'), outstanding: d('100'), isOverdue: true, dueDate: DateTime(2026, 10, 1)),
    ]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Las deudas se actualizaron'), findsOneWidget);
    expect(find.text('L 100.00'), findsWidgets, reason: 'SAL-1 now takes only what it still owes');
    expect(find.text('L 250.00'), findsOneWidget, reason: 'the rest goes to the newer debt');
    expect(find.text('Registrar abono de L 350.00'), findsOneWidget);
  });

  testWidgets('applying or cancelling an amount on one debt closes the dialog cleanly', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final profile = CustomerProfile(
      customer: const LocalCustomer(id: 'c1', code: 'CLI-1', businessName: 'Pulpería Doña Marta', address: 'Centro'),
      balance: null,
      receivables: debts,
      orders: const [],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(null),
        manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({'operations': ['customer.payment']}))),
        customerProfileProvider('c1').overrideWithValue(profile),
      ],
      child: const MaterialApp(home: PaymentScreen(customerId: 'c1')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SAL-1'));
    await tester.pumpAndSettle();
    expect(find.text('Aplicar a SAL-1'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Monto').last, '120');
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Registrar abono de L 120.00'), findsOneWidget);

    await tester.tap(find.text('PED-2026-000030'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Registrar abono de L 120.00'), findsOneWidget);
  });
}
