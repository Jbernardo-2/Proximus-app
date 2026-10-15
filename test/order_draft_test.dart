import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/features/preventa/data/customer_profile.dart';
import 'package:proximus_app/features/preventa/data/order_draft.dart';
import 'package:proximus_app/features/preventa/data/preventa_models.dart';
import 'package:proximus_app/features/preventa/data/preventista_repository.dart';
import 'package:proximus_app/features/preventa/presentation/order_screen.dart';

DecimalValue d(String value) => DecimalValue.parse(value);

final water = LocalProduct.fromJson({
  'id': 'agua',
  'sku': 'BEB-001',
  'name': 'Agua purificada 600 ml',
  'base_unit': 'und',
  'allows_decimal': false,
  'is_active': true,
  'presentations': [
    {'id': 'agua-und', 'name': 'Unidad', 'conversion_factor': '1', 'sale_price': '10.0000', 'is_base': true, 'is_sellable': true, 'is_active': true, 'price_tiers': []},
    {
      'id': 'agua-fardo',
      'name': 'Fardo 24',
      'conversion_factor': '24',
      'sale_price': '200.0000',
      'is_base': false,
      'is_sellable': true,
      'is_active': true,
      'price_tiers': [
        {'min_quantity': '5', 'max_quantity': null, 'unit_price': '190.0000', 'is_active': true},
      ],
    },
  ],
});

LocalPresentation presentation(String id) => water.presentations.firstWhere((p) => p.id == id);

void main() {
  final day = DateTime(2026, 10, 14);
  OrderDraft empty() => OrderDraft(customerId: 'c1', routeStopId: 's1', day: day);

  test('the same presentation adds up in one line and its tier price follows the quantity', () {
    var draft = empty().add(water, presentation('agua-fardo'), d('3'));
    expect(draft.lines.single.unitPrice.toFixed(2), '200.00');

    draft = draft.add(water, presentation('agua-fardo'), d('2'));
    expect(draft.lines, hasLength(1));
    expect(draft.lines.single.quantity.toString(), '5');
    expect(draft.lines.single.unitPrice.toFixed(2), '190.00', reason: '5 fardos reach the volume price');
    expect(draft.lines.single.hasTierPrice, isTrue);

    draft = draft.add(water, presentation('agua-und'), d('6'));
    expect(draft.total.toFixed(2), '1010.00');
    expect(draft.setQuantity(water, presentation('agua-und'), DecimalValue.zero).lines, hasLength(1));
    expect(draft.remove('agua-fardo').total.toFixed(2), '60.00');
  });

  test('stock and credit warn but never block', () {
    final draft = empty().add(water, presentation('agua-fardo'), d('2')).add(water, presentation('agua-und'), d('3')).withTerms(paymentTerm: 'credit');

    final tight = draft.warnings(available: {'agua': d('50')}, credit: (allowsCredit: true, available: d('300')));
    expect(tight.shortProducts, ['Agua purificada 600 ml'], reason: '2×24 + 3 = 51 units for 50 available');
    expect(tight.creditExceededBy.toFixed(2), '130.00');

    final fine = draft.warnings(available: {'agua': d('51')}, credit: (allowsCredit: true, available: d('430')));
    expect(fine.any, isFalse);

    expect(draft.warnings(available: {'agua': d('100')}, credit: null).creditNotAllowed, isTrue);
    expect(draft.withTerms(paymentTerm: 'cash').warnings(available: {'agua': d('100')}, credit: null).any, isFalse);
  });

  test('quantities are whole numbers unless the product sells fractions', () {
    expect(parseQuantity('3', allowsDecimal: false).toString(), '3');
    expect(parseQuantity('3.0', allowsDecimal: false).toString(), '3');
    expect(parseQuantity('2.5', allowsDecimal: false), isNull);
    expect(parseQuantity('2,5', allowsDecimal: true).toString(), '2.5');
    expect(parseQuantity('0', allowsDecimal: true), isNull);
    expect(parseQuantity('abc', allowsDecimal: true), isNull);
  });

  test('stock in base units is shown in the presentation being sold', () {
    expect(d('290').divide(d('24'), scale: 0).toString(), '12');
    expect(d('10').divide(d('4'), scale: 2).toString(), '2.5');
    expect(d('1.5').divide(d('0.25')).toString(), '6');
  });

  testWidgets('the order screen fits the test phone with two lines and warnings', (tester) async {
    await initializeDateFormatting('es');
    tester.view.physicalSize = const Size(384 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final profile = CustomerProfile(
      customer: const LocalCustomer(id: 'c1', code: 'CLI-1', businessName: 'Pulpería Doña Marta', address: 'Centro'),
      balance: CustomerBalance(allowsCredit: true, limit: d('1000'), outstanding: d('900'), overdue: d('0'), available: d('100')),
      receivables: const [],
      orders: const [],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(null),
        customerProfileProvider('c1').overrideWithValue(profile),
        routeStopForCustomerProvider('c1').overrideWithValue('s1'),
        availableStockProvider.overrideWithValue({'agua': d('10')}),
        productsProvider.overrideWithValue([water]),
      ],
      child: MediaQuery(
        data: const MediaQueryData(size: Size(384, 800), textScaler: TextScaler.linear(1.1)),
        child: const MaterialApp(home: OrderScreen(customerId: 'c1')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Agrega los productos del pedido.'), findsOneWidget);

    await tester.tap(find.text('Agregar producto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agua purificada 600 ml'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Fardo 24'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Cantidad'), '5');
    await tester.pumpAndSettle();
    expect(find.textContaining('precio por volumen'), findsOneWidget);
    expect(find.textContaining('Existencias insuficientes'), findsOneWidget);
    await tester.tap(find.text('Agregar al pedido'));
    await tester.pumpAndSettle();

    expect(find.text('L 950.00'), findsWidgets);
    expect(find.textContaining('5 × Fardo 24 · L 190.00 c/u (volumen)'), findsOneWidget);
    await tester.tap(find.textContaining('Crédito'));
    await tester.pumpAndSettle();
    expect(find.text('Excede el crédito disponible en L 850.00.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
