import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/features/bodega/application/warehouse_run_actions.dart';
import 'package:proximus_app/features/supervision/application/supervision_providers.dart';
import 'package:proximus_app/features/supervision/data/supervision_models.dart';
import 'package:proximus_app/features/preventa/data/preventa_models.dart' show AccountEntry, LocalReceivable;
import 'package:proximus_app/features/supervision/presentation/credit_screen.dart';
import 'package:proximus_app/features/supervision/presentation/settlement_screen.dart';
import 'package:proximus_app/features/supervision/presentation/supervisor_dashboard.dart';

import 'delivery_run_test.dart' show MemorySecureStore;

DecimalValue d(String value) => DecimalValue.parse(value);

Map<String, dynamic> item(String product, {String returned = '0', String damaged = '0'}) => {
  'product_id': product,
  'product_presentation_id': '$product-u',
  'product_name': 'Producto $product',
  'presentation_name': 'Unidad',
  'returned_quantity': returned,
  'damaged_quantity': damaged,
  'missing_quantity': '0',
};

/// A run back from the road: 100 delivered, 80 collected (50 cash + 30 transfer), 20 on
/// credit, and 25 of an old debt collected on the way.
Map<String, dynamic> settlingRun() => {
  'id': 'run1',
  'run_number': 'RUT-2026-000040',
  'status': 'awaiting_settlement',
  'driver_name': 'Carlos',
  'financials': {
    'delivered_total': '100.0000',
    'collected_total': '80.0000',
    'credit_total': '20.0000',
    'cash_expected': '75.0000',
    'account_payment_cash': '25.0000',
    'transfer_total': '30.0000',
    'card_total': '0',
    'check_total': '0',
    'other_payment_total': '0',
  },
  'orders': [
    {'id': 'ro1', 'order': {'order_number': 'PED-1', 'customer_name': 'Pulpería Rosa', 'payment_term': 'cash'}, 'balance_due': '20.0000', 'credit_reason': null, 'items': [item('a', returned: '2'), item('b')]},
    {'id': 'ro2', 'order': {'order_number': 'PED-2', 'customer_name': 'Tienda Juan', 'payment_term': 'credit'}, 'balance_due': '0.0000', 'credit_reason': null, 'items': [item('a', returned: '1', damaged: '1')]},
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('the settlement splits the cash to receive and checks the sale balances', () {
    final run = SettlementView.fromJson(settlingRun());

    expect(run.deliveryCash, d('50'));
    expect(run.cashToReceive, d('75'), reason: 'deliveries plus the old debt collected on the way');
    expect(run.balanced, isTrue, reason: '80 collected + 20 credit = 100 delivered');
    expect(run.difference(d('70')), d('-5'));
    expect(run.cashOrdersWithBalance.single.runOrderId, 'ro1', reason: 'only cash orders left with a balance need an agreement');
    expect(run.returns.single.returned, d('3'), reason: 'returns add up per product and presentation');
    expect(run.returns.single.damaged, d('1'));
  });

  test('the management panel reads the day and what waits', () {
    final panel = ManagementPanel.fromJson({
      'today': {'sold': '1500.5000', 'collected': '900.0000', 'credit': '600.5000'},
      'receivables': {'overdue': '320.0000', 'overdue_customers': 3},
      'pending': [{'key': 'runs_awaiting_settlement', 'count': 2}],
      'runs': [{'id': 'r', 'run_number': 'RUT-1', 'status': 'in_transit', 'status_label': 'En ruta', 'driver_name': 'Carlos', 'stops': 10, 'completed_stops': 4}],
    });

    expect(panel.pending['runs_awaiting_settlement'], 2);
    expect(panel.runs.single.progress, 0.4);
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(384 * 3, 820 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(MemorySecureStore(null)),
          apiProvider.overrideWithValue(null),
          liveResourceProvider('delivery_runs').overrideWith((ref) async => [settlingRun()]),
          managementPanelProvider.overrideWith((ref) async => ManagementPanel.fromJson({
            'today': {'sold': '1500.0000', 'collected': '900.0000', 'credit': '600.0000'},
            'receivables': {'overdue': '320.0000', 'overdue_customers': 3},
            'pending': [{'key': 'runs_awaiting_settlement', 'count': 1}, {'key': 'stock_shortages', 'count': 2}],
            'runs': [{'id': 'run1', 'run_number': 'RUT-2026-000040', 'status': 'awaiting_settlement', 'status_label': 'Por liquidar', 'driver_name': 'Carlos', 'stops': 5, 'completed_stops': 5, 'delivered_total': '100.0000'}],
          })),
        ],
        child: MaterialApp(home: child),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the count shows the difference as it is typed and a difference needs a note', (tester) async {
      await pump(tester, const SettlementScreen(runId: 'run1'));

      expect(find.text('La venta cuadra ✓'), findsOneWidget);
      expect(find.text('L 75.00'), findsOneWidget);
      FilledButton settle() => tester.widget<FilledButton>(find.ancestor(of: find.text('Liquidar jornada'), matching: find.byWidgetPredicate((widget) => widget is FilledButton)));
      expect(settle().onPressed, isNull, reason: 'nothing counted yet');

      await tester.enterText(find.byType(TextField).first, '70');
      await tester.pump();
      expect(find.text('Faltan L 5.00'), findsOneWidget);
      expect(settle().onPressed, isNull, reason: 'a difference needs a note');

      await tester.enterText(find.byType(TextField).first, '75');
      await tester.pump();
      expect(find.text('Cuadra ✓'), findsOneWidget);
      expect(settle().onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the supervisor home leads with the day and what waits to be settled', (tester) async {
      await pump(tester, const Scaffold(body: SingleChildScrollView(child: SupervisorDashboard())));

      expect(find.text('L 1,500.00'), findsOneWidget);
      expect(find.text('Liquidar (1)'), findsOneWidget);
      expect(find.text('2 productos con faltante en bodega.'), findsOneWidget);
      expect(find.textContaining('RUT-2026-000040'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
  testWidgets('the credit portfolio leads with who owes most past due, and a customer shows each invoice', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final rosa = PortfolioRow.fromJson({'customer_id': 'c1', 'code': 'CAMPO-01', 'business_name': 'Pulpería Rosa', 'outstanding_balance': '500.0000', 'overdue_balance': '200.0000', 'committed_credit': '0'});

    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(MemorySecureStore(null)),
        apiProvider.overrideWithValue(null),
        portfolioProvider((search: '', overdue: false, pages: 1)).overrideWith((ref) async => Portfolio(rows: [rosa], balance: DecimalValue.parse('500'), overdue: DecimalValue.parse('200'), debtors: 1, hasMore: true)),
        customerCreditProvider('c1').overrideWith((ref) async => (
          debts: [LocalReceivable.fromJson({'id': 'r1', 'customer_id': 'c1', 'document_number': 'FAC-1', 'original_amount': '300', 'outstanding_amount': '200', 'is_overdue': true, 'due_date': '2026-10-01'})],
          entries: [AccountEntry.fromJson({'type': 'customer_payment', 'type_label': 'Abono', 'receipt_number': 'ABO-7', 'debit_amount': '0', 'credit_amount': '100', 'occurred_at': '2026-10-10T10:00:00Z'})],
        )),
      ],
      child: const MaterialApp(home: CreditScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('vencido L 200.00'), findsOneWidget);
    expect(find.text('Ver más clientes'), findsOneWidget);
    await tester.tap(find.text('Pulpería Rosa'));
    await tester.pumpAndSettle();
    expect(find.textContaining('días de atraso'), findsOneWidget);
    expect(find.text('−L 100.00'), findsOneWidget, reason: 'a payment lowers the debt');
    expect(tester.takeException(), isNull);
  });
}
