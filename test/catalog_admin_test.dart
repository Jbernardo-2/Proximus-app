import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/modules.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/features/catalogo/application/catalog_admin.dart';
import 'package:proximus_app/features/catalogo/data/catalog_models.dart';
import 'package:proximus_app/features/catalogo/presentation/product_admin_screen.dart';
import 'package:proximus_app/features/catalogo/presentation/product_form_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore;

DecimalValue d(String value) => DecimalValue.parse(value);

/// A product as GET /products/{id} answers it.
Map<String, dynamic> productResponse() => {
  'id': 'p1',
  'sku': 'ARZ-001',
  'name': 'Arroz Precioso 1 lb',
  'description': null,
  'allows_decimal': false,
  'tracks_lots': true,
  'tracks_expiration': false,
  'is_active': true,
  'category': {'id': 'c1', 'name': 'Granos'},
  'brand': {'id': 'b1', 'name': 'Precioso'},
  'base_unit': {'id': 'u1', 'name': 'Libra', 'symbol': 'lb'},
  'presentations': [
    {
      'id': 'pr-f', 'name': 'Fardo x24', 'barcode': '7401', 'conversion_factor': '24.000000', 'sale_price': '400.0000',
      'is_base': false, 'is_sellable': true, 'is_purchasable': true, 'is_active': true,
      'price_tiers': [{'id': 't1', 'min_quantity': '10.000000', 'max_quantity': null, 'unit_price': '380.0000', 'starts_at': null, 'ends_at': null, 'is_active': true}],
    },
    {'id': 'pr-u', 'name': 'Unidad', 'barcode': null, 'conversion_factor': '1.000000', 'sale_price': '18.0000', 'is_base': true, 'is_sellable': true, 'is_purchasable': false, 'is_active': true, 'price_tiers': []},
  ],
  'suppliers': [
    {'id': 's-l', 'supplier_id': 's1', 'product_presentation_id': 'pr-f', 'supplier_sku': 'DS-88', 'cost_price': '350.0000', 'is_preferred': true, 'is_active': true, 'notes': null, 'supplier': {'id': 's1', 'name': 'Distribuidora Sol', 'code': 'DS'}},
  ],
};

Session session(List<String> abilities) => Session(serverUrl: 'http://test', token: 't', user: const {'id': 7, 'name': 'Lara', 'role': 'supervisor'}, device: const {'code': 'S001'}, abilities: abilities);

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('a product from the server brings its presentations, price tiers and suppliers', () {
    final product = ProductData.fromJson(productResponse());

    expect(product.baseUnit.label, 'Libra (lb)');
    expect(product.presentations.first.tiers.single.unitPrice, d('380'));
    expect(product.presentations.first.tiers.single.maxQuantity, isNull);
    expect(product.suppliers.single.supplier.name, 'Distribuidora Sol');
    expect(product.presentationName('pr-f'), 'Fardo x24');
    expect(OptionKind.unit.create('Libra', symbol: 'lb'), {'name': 'Libra', 'symbol': 'lb', 'decimal_places': 0, 'is_active': true});
  });

  test('the products module shows only to whoever the server lets manage the catalog on the phone', () {
    final manifest = SyncManifest.fromJson(const {});
    bool shows(List<String> abilities) => modulesFor(manifest, session(abilities)).any((module) => module.path == '/catalog');

    expect(shows(['catalog:manage']), isTrue);
    expect(shows(['inventory:operate', 'deliveries:prepare']), isFalse, reason: 'the warehouse keeper manages products on the web only');
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
          secureStoreProvider.overrideWithValue(MemorySecureStore(session(['catalog:manage']))),
          apiProvider.overrideWithValue(null),
          productDataProvider('p1').overrideWith((ref) async => ProductData.fromJson(productResponse())),
        ],
        child: MaterialApp(home: child),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a new product with a scanned code offers it as its SKU and waits for what is required', (tester) async {
      await pump(tester, const ProductFormScreen(barcode: '7409999000111'));

      FilledButton create() => tester.widget<FilledButton>(find.ancestor(of: find.text('Crear producto'), matching: find.byWidgetPredicate((widget) => widget is FilledButton)));
      expect(create().onPressed, isNull);
      await tester.tap(find.text('Usar el código de barras'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '7409999000111'), findsWidgets);
      expect(find.text('Usar el código de barras'), findsNothing, reason: 'the SKU already is the code');
      expect(create().onPressed, isNull, reason: 'name, category, unit and price are still missing');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the product page shows its presentations with their tiers and its suppliers', (tester) async {
      await pump(tester, const ProductAdminScreen(productId: 'p1'));

      expect(find.text('Arroz Precioso 1 lb'), findsOneWidget);
      expect(find.text('Lote'), findsOneWidget);
      expect(find.textContaining('1 escala'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Distribuidora Sol'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('L 350.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
