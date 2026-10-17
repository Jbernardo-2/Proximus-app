import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/features/bodega/data/warehouse_catalog.dart';
import 'package:proximus_app/features/bodega/data/warehouse_runs.dart';
import 'package:proximus_app/features/bodega/presentation/product_detail_screen.dart';
import 'package:proximus_app/features/bodega/presentation/product_search_screen.dart';
import 'package:proximus_app/features/bodega/presentation/warehouse_dashboard.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore;

Map<String, dynamic> productJson(String id, String name, {String? barcode, bool active = true, bool sellable = true}) => {
  'id': id,
  'deleted': false,
  'sku': 'SKU-$id',
  'name': name,
  'brand': 'Marca Sol',
  'category': 'Granos',
  'base_unit': 'u',
  'allows_decimal': false,
  'is_active': active,
  'presentations': [
    {'id': '$id-u', 'name': 'Unidad', 'barcode': null, 'conversion_factor': '1.000000', 'sale_price': '18.0000', 'is_base': true, 'is_sellable': sellable, 'is_active': true, 'price_tiers': []},
    {'id': '$id-f', 'name': 'Fardo 24', 'barcode': barcode, 'conversion_factor': '24.000000', 'sale_price': '400.0000', 'is_base': false, 'is_sellable': sellable, 'is_active': true, 'price_tiers': []},
  ],
};

final products = [
  productJson('p1', 'Arroz 1 lb', barcode: '7401234567890'),
  productJson('p2', 'Frijol rojo', sellable: false),
  productJson('p3', 'Azúcar vieja', active: false),
  {'id': 'p4', 'deleted': true},
];

final stocks = [
  {'warehouse_id': 'w1', 'product_id': 'p1', 'quantity_on_hand': '20.000000', 'quantity_reserved': '6.000000', 'quantity_available': '14.000000'},
  {'warehouse_id': 'w2', 'product_id': 'p1', 'quantity_on_hand': '3.000000', 'quantity_reserved': '0.000000', 'quantity_available': '3.000000'},
];

void main() {
  test('the warehouse sees every active product, sellable or not, with its stock per warehouse', () {
    final items = warehouseProducts(products: products, stocks: stocks);

    expect(items.map((item) => item.product.name), ['Arroz 1 lb', 'Frijol rojo']);
    expect(items.first.onHandIn('w1'), DecimalValue.parse('20'));
    expect(items.first.onHandIn('w2'), DecimalValue.parse('3'));
    expect(items.last.onHandIn('w1'), DecimalValue.zero, reason: 'no stock row means none of it');
  });

  test('a product is found by any word of its name, brand or code, and by a scanned barcode', () {
    final items = warehouseProducts(products: products, stocks: stocks);

    expect(searchWarehouseProducts(items, 'arroz sol').single.product.id, 'p1');
    expect(searchWarehouseProducts(items, 'SKU-p2').single.product.id, 'p2');
    expect(searchWarehouseProducts(items, '74012').single.product.id, 'p1');
    expect(productForBarcode(items, ' 7401234567890 ')?.product.id, 'p1');
    expect(productForBarcode(items, '999'), isNull);
  });

  test('the warehouse work tells apart runs I prepare from the ones another keeper holds', () {
    WarehouseRun run(String status, {int? by}) => WarehouseRun(id: status, status: status, warehouseId: null, driverName: '', orders: const [], preparationStartedBy: by);
    final work = WarehouseWork.of(
      runs: [run('draft'), run('preparing', by: 7), run('preparing', by: 9), run('loaded')],
      ordersWaiting: 3,
      userId: 7,
    );

    expect((work.ordersWaiting, work.drafts, work.preparingMine, work.preparingOthers, work.loaded), (3, 1, 1, 1, 1));
  });

  group('screens', () {
    late List<Override> overrides;

    setUp(() {
      overrides = [
        secureStoreProvider.overrideWithValue(MemorySecureStore(
          Session(serverUrl: 'http://test', token: 't', user: const {'id': 7, 'name': 'Rosa', 'role': 'bodeguero'}, device: const {'code': 'B001'}, abilities: const ['inventory:operate']),
        )),
        apiProvider.overrideWithValue(null),
        manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({
          'default_warehouse': {'id': 'w1', 'name': 'Bodega central'},
        }))),
        localRecordsProvider('products').overrideWith((ref) => Stream.value(products)),
        localRecordsProvider('stocks').overrideWith((ref) => Stream.value(stocks)),
        localRecordsProvider('warehouses').overrideWith((ref) => Stream.value([
          {'id': 'w2', 'name': 'Bodega norte', 'is_default': false},
          {'id': 'w1', 'name': 'Bodega central', 'is_default': true},
        ])),
        localRecordsProvider('delivery_runs').overrideWith((ref) => Stream.value(const [])),
        localRecordsProvider('dispatch_orders').overrideWith((ref) => Stream.value(const [])),
        localRecordsProvider('drivers').overrideWith((ref) => Stream.value(const [])),
        outboxRowsProvider.overrideWith((ref) => Stream.value(const [])),
        syncStateProvider('pulled_at:delivery_runs').overrideWith((ref) => Stream.value(null)),
      ];
    });

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(384 * 3, 820 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: child)));
      await tester.pumpAndSettle();
    }

    testWidgets('the search lists products with the stock of the default warehouse and filters as you type', (tester) async {
      await pump(tester, const ProductSearchScreen());

      expect(find.text('2 de 2 productos'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'frijol');
      await tester.pump();
      expect(find.text('Arroz 1 lb'), findsNothing);
      expect(find.text('Frijol rojo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the product shows its stock in each warehouse and every presentation with its barcode', (tester) async {
      await pump(tester, const ProductDetailScreen(productId: 'p1'));

      expect(find.text('Bodega central'), findsOneWidget);
      expect(find.text('Bodega norte'), findsOneWidget);
      expect(find.text('14 u'), findsOneWidget, reason: 'available in the central warehouse');
      await tester.scrollUntilVisible(find.textContaining('7401234567890'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Sin código de barras'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the warehouse home leads with the product search and what waits to go out', (tester) async {
      await pump(tester, const Scaffold(body: SingleChildScrollView(child: WarehouseDashboard())));

      expect(find.text('Buscar producto'), findsOneWidget);
      expect(find.text('Pedidos sin jornada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
