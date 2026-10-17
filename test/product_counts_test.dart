import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/features/bodega/application/count_actions.dart';
import 'package:proximus_app/features/bodega/application/warehouse_run_actions.dart';
import 'package:proximus_app/features/bodega/data/product_counts.dart';
import 'package:proximus_app/features/bodega/data/warehouse_catalog.dart';
import 'package:proximus_app/features/bodega/presentation/count_sheet.dart';
import 'package:proximus_app/features/bodega/presentation/counts_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore;
import 'warehouse_catalog_test.dart' show products, stocks;

DecimalValue d(String value) => DecimalValue.parse(value);

/// A count as the server answers it.
Map<String, dynamic> countJson(String number, String counted, String expected, String difference, {String? notes}) => {
  'count_number': number,
  'warehouse': {'name': 'Bodega central'},
  'notes': notes,
  'posted_at': '2026-10-16T15:30:00Z',
  'created_by': {'name': 'Rosa'},
  'items': [
    {'product': {'id': 'p1', 'name': 'Arroz 1 lb', 'base_unit_symbol': 'u'}, 'counted_quantity': counted, 'expected_quantity': expected, 'difference': difference},
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('a count reads what there was, what was counted and the adjustment the server made', () {
    final count = ProductCount.fromJson(countJson('CON-2026-000009', '17.000000', '20.000000', '-3.000000', notes: 'Bolsas rotas'));

    expect((count.counted, count.expected, count.difference), (d('17'), d('20'), d('-3')));
    expect(count.notes, 'Bolsas rotas');
    expect(count.countedBy, 'Rosa');
  });

  test('a count by boxes and loose units adds up in base units', () {
    final product = warehouseProducts(products: products, stocks: stocks).first.product;

    expect(countedTotal(product.presentations, {'p1-f': d('3'), 'p1-u': d('5')}), d('77'));
    expect(countedTotal(product.presentations, {'p1-f': null, 'p1-u': null}), isNull, reason: 'nothing typed is not a count of zero');
    expect(countedTotal(product.presentations, {'p1-u': d('0')}), d('0'));
  });

  group('screens', () {
    late List<Override> overrides;

    setUp(() => overrides = [
      secureStoreProvider.overrideWithValue(MemorySecureStore(null)),
      apiProvider.overrideWithValue(null),
      manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({'default_warehouse': {'id': 'w1', 'name': 'Bodega central'}}))),
      localRecordsProvider('products').overrideWith((ref) => Stream.value(products)),
      localRecordsProvider('stocks').overrideWith((ref) => Stream.value(const [])),
      liveResourceProvider('stocks').overrideWith((ref) async => stocks),
      liveResourceProvider('warehouses').overrideWith((ref) async => const [{'id': 'w1', 'name': 'Bodega central', 'is_default': true}]),
      productCountsProvider.overrideWith((ref) async => [
        ProductCount.fromJson(countJson('CON-2026-000009', '17.000000', '20.000000', '-3.000000')),
        ProductCount.fromJson(countJson('CON-2026-000010', '20.000000', '20.000000', '0.000000')),
      ]),
    ]);

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(384 * 3, 820 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: child)));
      await tester.pumpAndSettle();
    }

    testWidgets('counting is blind: boxes and units add up, and the system stock is not shown', (tester) async {
      final item = warehouseProducts(products: products, stocks: stocks).first;
      await pump(tester, Scaffold(body: CountSheet(item: item)));

      expect(find.textContaining('20'), findsNothing, reason: 'the 20 in the system must not steer the count');
      await tester.enterText(find.byType(TextField).at(0), '3');
      await tester.enterText(find.byType(TextField).at(1), '5');
      await tester.pump();
      expect(find.text('Total contado: 77 u'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the list shows each count the server applied with its difference', (tester) async {
      await pump(tester, const CountsScreen());

      expect(find.text('-3'), findsOneWidget);
      expect(find.text('cuadra'), findsOneWidget);
      expect(find.textContaining('CON-2026-000009'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
