import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/features/bodega/application/warehouse_run_actions.dart';
import 'package:proximus_app/features/bodega/data/receipts.dart';
import 'package:proximus_app/features/bodega/data/warehouse_catalog.dart';
import 'package:proximus_app/features/bodega/presentation/new_receipt_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore;
import 'warehouse_catalog_test.dart' show productJson;

DecimalValue d(String value) => DecimalValue.parse(value);

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final item = warehouseProducts(products: [productJson('p1', 'Arroz 1 lb', barcode: '7401')], stocks: const []).single;
  final box = item.product.presentations.firstWhere((presentation) => !presentation.isBase);

  test('a whole entry goes in one request, with the supplier only for a supplier receipt', () {
    final line = ReceiptLine(product: item.product, presentation: box, quantity: d('3'), unitCost: d('380.5'), lotNumber: 'L-7', expirationDate: DateTime(2027, 3, 1));
    final payload = receiptPayload(type: ReceiptType.receipt, warehouseId: 'w1', occurredOn: DateTime(2026, 10, 16), lines: [line], supplierId: 's1', reference: ' FAC-889 ', notes: '');

    expect(line.baseQuantity, d('72'), reason: '3 boxes of 24');
    expect(payload, {
      'type': 'receipt',
      'warehouse_id': 'w1',
      'supplier_id': 's1',
      'occurred_on': '2026-10-16',
      'external_reference': 'FAC-889',
      'notes': null,
      'items': [
        {'product_presentation_id': 'p1-f', 'quantity': '3', 'unit_cost': '380.5', 'lot_number': 'L-7', 'expiration_date': '2027-03-01'},
      ],
    });
    expect(receiptPayload(type: ReceiptType.customerReturn, warehouseId: 'w1', occurredOn: DateTime(2026, 10, 16), lines: [line], supplierId: 's1')['supplier_id'], isNull);
  });

  test('the list keeps only what brings merchandise in', () {
    final receipts = postedReceipts([
      {'id': '1', 'document_number': 'REC-1', 'type': 'receipt', 'type_label': 'Entrada de proveedor', 'occurred_on': '2026-10-16', 'items_count': 2},
      {'id': '2', 'document_number': 'AJS-1', 'type': 'adjustment_out', 'type_label': 'Ajuste de salida', 'occurred_on': '2026-10-16', 'items_count': 1},
      {'id': '3', 'document_number': 'DCL-1', 'type': 'customer_return', 'type_label': 'Devolución de cliente', 'occurred_on': '2026-10-15', 'items_count': 1},
    ]);

    expect(receipts.map((receipt) => receipt.number), ['REC-1', 'DCL-1']);
  });

  testWidgets('a keeper without the adjustment permission only sees receipts and customer returns', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(MemorySecureStore(
          Session(serverUrl: 'http://test', token: 't', user: const {'id': 7, 'name': 'Rosa', 'role': 'bodeguero'}, device: const {'code': 'B001'}, abilities: const ['inventory:operate']),
        )),
        apiProvider.overrideWithValue(null),
        manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({'default_warehouse': {'id': 'w1', 'name': 'Bodega central'}}))),
        liveResourceProvider('suppliers').overrideWith((ref) async => const [{'id': 's1', 'name': 'Distribuidora Sol'}]),
        liveResourceProvider('warehouses').overrideWith((ref) async => const []),
        liveResourceProvider('stocks').overrideWith((ref) async => const []),
        localRecordsProvider('products').overrideWith((ref) => Stream.value(const [])),
        localRecordsProvider('stocks').overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: NewReceiptScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Aplicar entrada'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.ancestor(of: find.text('Aplicar entrada'), matching: find.byWidgetPredicate((widget) => widget is FilledButton))).onPressed, isNull, reason: 'no lines yet');
    await tester.tap(find.text('Entrada de proveedor'));
    await tester.pumpAndSettle();
    expect(find.text('Devolución de cliente'), findsWidgets);
    expect(find.text('Ajuste de entrada'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
