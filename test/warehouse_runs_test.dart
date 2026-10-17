import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/bodega/data/warehouse_runs.dart';
import 'package:proximus_app/features/bodega/presentation/warehouse_run_screen.dart';

import 'delivery_run_test.dart' show MemorySecureStore;

DecimalValue d(String value) => DecimalValue.parse(value);

final now = DateTime(2026, 10, 16, 9);

Map<String, dynamic> dispatchJson(String id, String customer, List<(String item, String presentation, String quantity)> items) => {
  'id': id,
  'order_number': 'PED-$id',
  'customer_name': customer,
  'warehouse_id': 'w1',
  'route_name': 'Ruta Norte',
  'total': '100.0000',
  'items': [
    for (final item in items)
      {'id': item.$1, 'product_id': 'prod-${item.$2}', 'product_presentation_id': item.$2, 'product_name': 'Arroz ${item.$2}', 'presentation_name': 'Fardo', 'quantity': item.$3},
  ],
};

final dispatch = [
  dispatchJson('o1', 'Pulpería Rosa', [('i1', 'arroz', '4'), ('i2', 'frijol', '2')]),
  dispatchJson('o2', 'Tienda Juan', [('i3', 'arroz', '3')]),
  dispatchJson('o3', 'Mini Súper', [('i4', 'frijol', '1')]),
];

OutboxData op(int id, String type, Map<String, dynamic> payload, {String status = OutboxStatus.pending, Map<String, dynamic>? result, String? message}) => OutboxData(
  id: id,
  clientReference: 'B001:$id',
  type: type,
  payload: jsonEncode(payload),
  status: status,
  summary: '',
  attempts: 0,
  createdAt: now,
  processedAt: status == OutboxStatus.pending ? null : now,
  result: result == null ? null : jsonEncode(result),
  message: message,
);

/// A run assembled and picked on a phone with no signal at all.
List<OutboxData> offlineDay() => [
  op(1, 'delivery.create', {'id': 'run1', 'warehouse_id': 'w1', 'driver_id': 4, 'scheduled_date': '2026-10-16'}),
  op(2, 'delivery.assign', {'delivery_run_id': 'run1', 'order_id': 'o1'}),
  op(3, 'delivery.assign', {'delivery_run_id': 'run1', 'order_id': 'o2'}),
  op(4, 'delivery.prepare_start', {'delivery_run_id': 'run1'}),
];

({List<WarehouseRun> runs, List<DispatchOrder> available}) merge(List<OutboxData> outbox, {List<Map<String, dynamic>> records = const []}) =>
    mergeWarehouseRuns(records: records, dispatchOrders: dispatch, outbox: outbox, pulledAt: null, drivers: const {'4': 'Carlos'}, userId: 7);

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('a run made on the phone shows its orders and stage before reaching the server', () {
    final merged = merge(offlineDay());
    final run = merged.runs.single;

    expect(run.title, 'Jornada nueva');
    expect(run.driverName, 'Carlos');
    expect(run.status, 'preparing');
    expect(run.preparationStartedBy, 7, reason: 'whoever started it on this phone holds it');
    expect(run.pending, isTrue);
    expect(run.orders.map((order) => order.orderNumber), ['PED-o1', 'PED-o2']);
    expect(merged.available.single.order.orderId, 'o3', reason: 'assigned orders leave the list');
  });

  test('picking groups a presentation across orders and only sends when every line is reviewed', () {
    final run = merge(offlineDay()).runs.single;
    final groups = pickGroups(run);

    expect(groups.map((group) => (group.presentationId, group.requested)), [('arroz', d('7')), ('frijol', d('2'))]);
    expect(preparedQuantities(run, {'i1': d('4'), 'i3': d('3')}), isNull, reason: 'frijol is not reviewed yet');
    final quantities = preparedQuantities(run, {'i1': d('4'), 'i2': d('0'), 'i3': d('1')})!;
    expect(quantities, {'i1': d('4'), 'i2': d('0'), 'i3': d('1')});
    expect(emptyOrders(run, {'i1': d('0'), 'i2': d('0'), 'i3': d('1')}).single.orderId, 'o1', reason: 'the server refuses to load an empty order');
  });

  test('the load on the phone moves the run to ready, and a refusal shows on the run', () {
    final loaded = merge([
      ...offlineDay(),
      op(5, 'delivery.prepare', {'delivery_run_id': 'run1', 'items': [{'order_item_id': 'i1', 'prepared_quantity': '4'}, {'order_item_id': 'i2', 'prepared_quantity': '2'}, {'order_item_id': 'i3', 'prepared_quantity': '3'}]}),
      op(6, 'delivery.load', {'delivery_run_id': 'run1'}),
    ]).runs.single;
    expect(loaded.status, 'loaded');
    expect(loaded.lines.map((line) => line.prepared), [d('4'), d('2'), d('3')]);

    final refused = merge([
      ...offlineDay(),
      op(5, 'delivery.prepare', {'delivery_run_id': 'run1', 'items': []}, status: OutboxStatus.rejected, message: 'La jornada la está preparando Rosa.'),
    ]).runs.single;
    expect(refused.rejections.single, contains('Rosa'));
  });

  test('removing an order the server has frees it again; one still on the phone keeps its queue id to drop it', () {
    final records = [
      {
        'id': 'run9',
        'run_number': 'RUT-2026-000020',
        'status': 'draft',
        'warehouse': {'id': 'w1'},
        'driver_name': 'Carlos',
        'orders': [
          {
            'id': 'ro1',
            'order': {'id': 'o9', 'order_number': 'PED-o9', 'customer_name': 'Bodega Luz'},
            'requested_total': '50.0000',
            'items': [{'order_item_id': 'i9', 'product_id': 'p', 'product_presentation_id': 'arroz', 'product_name': 'Arroz', 'presentation_name': 'Fardo', 'requested_quantity': '5.000000', 'prepared_quantity': '0.000000'}],
          },
        ],
      },
    ];
    final merged = merge([
      op(1, 'delivery.unassign', {'delivery_run_id': 'run9', 'run_order_id': 'ro1'}),
      op(2, 'delivery.assign', {'delivery_run_id': 'run9', 'order_id': 'o3'}),
    ], records: records);

    expect(merged.runs.single.orders.single.pendingAssignId, 2);
    expect(merged.available.map((dispatch) => dispatch.order.orderId), containsAll(['o9', 'o1', 'o2']));
  });

  testWidgets('the picking screen lists each presentation once and holds the load until all are reviewed', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final picked = <String, String>{};

    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(MemorySecureStore(
          Session(serverUrl: 'http://test', token: 't', user: const {'id': 7, 'name': 'Rosa', 'role': 'bodeguero'}, device: const {'code': 'B001'}, abilities: const []),
        )),
        apiProvider.overrideWithValue(null),
        localRecordsProvider('delivery_runs').overrideWith((ref) => Stream.value(const [])),
        localRecordsProvider('dispatch_orders').overrideWith((ref) => Stream.value(dispatch)),
        localRecordsProvider('drivers').overrideWith((ref) => Stream.value(const [{'id': 4, 'name': 'Carlos'}])),
        localRecordsProvider('products').overrideWith((ref) => Stream.value(const [])),
        localRecordsProvider('stocks').overrideWith((ref) => Stream.value(const [])),
        outboxRowsProvider.overrideWith((ref) => Stream.value(offlineDay())),
        syncStateProvider('pulled_at:delivery_runs').overrideWith((ref) => Stream.value(null)),
        syncStateProvider('picking:run1').overrideWith((ref) => Stream.value(picked.isEmpty ? null : jsonEncode(picked))),
      ],
      child: const MaterialApp(home: WarehouseRunScreen(runId: 'run1')),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('0 de 2 productos revisados'), findsOneWidget);
    expect(find.text('Faltan 2 por revisar'), findsOneWidget);
    expect(find.text('Arroz arroz'), findsOneWidget);
  });
}
