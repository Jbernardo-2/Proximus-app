import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/features/bodega/application/warehouse_run_actions.dart';
import 'package:proximus_app/features/bodega/data/warehouse_runs.dart';
import 'package:proximus_app/features/bodega/presentation/warehouse_run_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore;

DecimalValue d(String value) => DecimalValue.parse(value);

/// A run line as the server sends it; [picked] is what the keeper saved, if anything.
Map<String, dynamic> line(String id, String presentation, String requested, {String? picked}) => {
  'order_item_id': id,
  'product_id': 'prod-$presentation',
  'product_presentation_id': presentation,
  'product_name': 'Producto $presentation',
  'presentation_name': 'Fardo',
  'requested_quantity': requested,
  // Frijol comes in sacks of 24 pounds: the stock is counted in pounds.
  'conversion_factor': presentation == 'frijol' ? '24.000000' : '1.000000',
  'prepared_quantity': picked ?? '0.000000',
  'picked_at': picked == null ? null : '2026-10-16T15:00:00Z',
};

Map<String, dynamic> runJson({String status = 'preparing', String? pickedI1}) => {
  'id': 'run1',
  'run_number': 'RUT-2026-000030',
  'status': status,
  'warehouse': {'id': 'w1'},
  'driver_name': 'Carlos',
  'preparation_started_by': 7,
  'orders': [
    // Sent out of order on purpose: the stops are sorted by visit.
    {'id': 'ro2', 'visit_order': 2, 'order': {'id': 'o2', 'order_number': 'PED-o2', 'customer_name': 'Tienda Juan'}, 'requested_total': '30.0000', 'items': [line('i3', 'arroz', '3')]},
    {'id': 'ro1', 'visit_order': 1, 'order': {'id': 'o1', 'order_number': 'PED-o1', 'customer_name': 'Pulpería Rosa'}, 'requested_total': '70.0000', 'items': [line('i1', 'arroz', '4', picked: pickedI1), line('i2', 'frijol', '2')]},
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('a run from the server keeps its stops in visit order and only reviewed lines count as picked', () {
    final run = warehouseRunFromJson(runJson(pickedI1: '4.000000'));

    expect(run.orders.map((order) => order.visitOrder), [1, 2]);
    expect(run.lines.map((line) => line.prepared), [d('4'), null, null]);
    final groups = pickGroups(run);
    expect(groups.map((group) => (group.presentationId, group.requested)), [('arroz', d('7')), ('frijol', d('2'))]);
    expect(groups.first.prepared, isNull, reason: 'stop 2 still has its rice to review');
    expect(warehouseRuns([runJson(), {...runJson(), 'id': 'run2', 'status': 'in_transit'}]).single.id, 'run1', reason: 'the warehouse leaves out runs already on the road');
  });

  group('stock', () {
    final run = warehouseRunFromJson(runJson());
    final onHand = {'prod-arroz': d('5'), 'prod-frijol': d('30')};
    bool integers(String _) => false;

    test('each product is checked in base units against the warehouse, as the server does', () {
      final stock = stockForRun(run, onHand: onHand);

      expect(stock['prod-arroz']!.missing, d('2'));
      expect(stock['prod-frijol']!.needed, d('48'), reason: '2 sacks of 24');
      expect(stock['prod-frijol']!.missing, d('18'));
      expect(stockForRun(run, onHand: onHand, typed: {'i1': d('2'), 'i3': d('3'), 'i2': d('1')}).values.any((product) => product.isShort), isFalse);
      expect(stockForRun(run, onHand: onHand, typed: {'i1': d('4')}, unpickedAsRequested: false)['prod-arroz']!.isShort, isFalse, reason: 'unreviewed lines never block what is typed');
    });

    test('what is short goes to the earlier stops first, in whole sacks', () {
      expect(fillByVisit(run, ['i1', 'i3'], onHand: onHand, allowsDecimal: integers), {'i1': d('4'), 'i3': d('1')});
      expect(fillByVisit(run, ['i3'], onHand: onHand, allowsDecimal: integers), {'i3': d('1')}, reason: 'stop 1 keeps its share while unpicked');
      expect(fillByVisit(run, ['i2'], onHand: onHand, allowsDecimal: integers), {'i2': d('1')}, reason: '30 pounds fill one sack of 24');
    });
  });

  test('an order reviewed all at zero cannot go on the truck', () {
    final run = warehouseRunFromJson({
      ...runJson(),
      'orders': [
        {'id': 'ro1', 'visit_order': 1, 'order': {'id': 'o1', 'order_number': 'PED-o1', 'customer_name': 'Pulpería Rosa'}, 'requested_total': '0', 'items': [line('i1', 'arroz', '4', picked: '0')]},
      ],
    });

    expect(emptyOrders(run).single.orderNumber, 'PED-o1');
  });

  testWidgets('the picking screen reads the run and the stock live, by product or by order', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(MemorySecureStore(
          Session(serverUrl: 'http://test', token: 't', user: const {'id': 7, 'name': 'Rosa', 'role': 'bodeguero'}, device: const {'code': 'B001'}, abilities: const []),
        )),
        apiProvider.overrideWithValue(null),
        manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({'default_warehouse': {'id': 'w1', 'name': 'Bodega central'}}))),
        liveResourceProvider('delivery_runs').overrideWith((ref) async => [runJson()]),
        liveResourceProvider('stocks').overrideWith((ref) async => const [
          {'warehouse_id': 'w1', 'product_id': 'prod-arroz', 'quantity_on_hand': '5.000000'},
          {'warehouse_id': 'w1', 'product_id': 'prod-frijol', 'quantity_on_hand': '100.000000'},
        ]),
        localRecordsProvider('products').overrideWith((ref) => Stream.value(const [])),
        localRecordsProvider('stocks').overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: WarehouseRunScreen(runId: 'run1')),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('RUT-2026-000030'), findsOneWidget);
    expect(find.text('0 de 2 productos revisados'), findsOneWidget);
    expect(find.textContaining('No alcanza 1 producto'), findsOneWidget);
    expect(find.text('Hay 5 u · faltan 2'), findsOneWidget);
    expect(find.text('Faltan 2 por revisar'), findsOneWidget);

    await tester.tap(find.text('Por pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Pulpería Rosa'), findsOneWidget);
    expect(find.text('PED-o1 · 0 de 2 líneas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
