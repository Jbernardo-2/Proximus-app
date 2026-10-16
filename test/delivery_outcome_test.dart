import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/preventa/data/preventa_models.dart' show LocalOperationState;
import 'package:proximus_app/features/reparto/data/delivery_models.dart';
import 'package:proximus_app/features/reparto/data/delivery_repository.dart';
import 'package:proximus_app/features/reparto/data/outcome_draft.dart';
import 'package:proximus_app/features/reparto/presentation/delivery_outcome_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore, runJson;

DecimalValue d(String value) => DecimalValue.parse(value);

LocalDeliveryStop stop() => LocalDeliveryStop.fromJson({
  'id': 'ro1',
  'visit_order': 1,
  'status': 'loaded',
  'order': {'id': 'o1', 'customer_id': 'c1', 'customer_name': 'Pulpería', 'customer_address': 'Centro', 'payment_term': 'cash'},
  'items': [
    {'id': 'a', 'product_name': 'Arroz', 'presentation_name': 'Unidad', 'unit_price': '18', 'requested_quantity': '3', 'loaded_quantity': '3'},
    {'id': 'b', 'product_name': 'Frijol', 'presentation_name': 'Unidad', 'unit_price': '22', 'requested_quantity': '2', 'loaded_quantity': '2'},
  ],
});

OutboxData outcomeRow(Map<String, dynamic> payload, {String status = OutboxStatus.pending, String? message}) => OutboxData(
  id: 2,
  clientReference: 'M004:entrega',
  type: 'delivery.outcome',
  payload: jsonEncode({'delivery_run_id': 'run1', 'run_order_id': 'ro1', ...payload}),
  status: status,
  summary: 'Pulpería',
  attempts: 0,
  createdAt: DateTime(2026, 10, 15, 9),
  message: message,
);

void main() {
  test('everything delivered only asks who received it', () {
    var draft = OutcomeDraft.start(stop());
    expect(draft.allDelivered, isTrue);
    expect(draft.deliveredTotal.toFixed(2), '98.00');
    expect(draft.problems(), ['Escribe quién recibió la mercadería.']);
    draft = draft.withReceiver('Doña Marta');
    expect(draft.problems(), isEmpty);
    expect(draft.payloadItems().first, {'id': 'a', 'delivered_quantity': '3', 'returned_quantity': '0', 'damaged_quantity': '0', 'missing_quantity': '0'});
  });

  test('what is not delivered adds up to what was loaded, and a return needs its reason', () {
    var draft = OutcomeDraft.start(stop(), receiverName: 'Doña Marta').withDelivered('a', d('1'));
    expect(draft.needsReason, isTrue, reason: 'the rest counts as returned by default');
    expect(draft.problems(), ['Elige el motivo de la devolución.']);

    draft = draft.withLeftover('a', Leftover.damaged);
    expect(draft.needsReason, isFalse, reason: 'damaged and missing are set by the server');
    expect(draft.payloadItems().first, {'id': 'a', 'delivered_quantity': '1', 'returned_quantity': '0', 'damaged_quantity': '2', 'missing_quantity': '0'});
    expect(draft.withDelivered('a', d('9')).lines.first.delivered, d('3'), reason: 'never more than loaded');
    expect(draft.withDelivered('a', d('1.5')).problems(), contains('Arroz se entrega en cantidades enteras.'));

    final nothing = draft.deliverNothing();
    expect(nothing.anyDelivered, isFalse);
    expect(nothing.problems(), ['Elige el motivo de la devolución.'], reason: 'no receiver when nothing was left');
    expect(nothing.withReason('business_closed').problems(), isEmpty);
  });

  test('a delivery saved on the phone moves the stop: to collect, or finished when nothing was left', () {
    List<LocalDeliveryStop> stops(OutboxData row) => mergeDeliveryRuns(records: [runJson(status: 'in_transit')], outbox: [row], customers: const [], pulledAt: null).single.stops;

    final delivered = stops(outcomeRow({
      'receiver_name': 'Doña Marta',
      'items': [
        {'id': 'i1', 'delivered_quantity': '2', 'returned_quantity': '1', 'damaged_quantity': '0', 'missing_quantity': '0'},
      ],
      'outcome_reason_label': 'Cliente rechazó el pedido',
    })).first;
    expect(delivered.progress, StopProgress.awaitingPayment);
    expect(delivered.deliveredTotal.toFixed(2), '36.00');
    expect(delivered.operationState, LocalOperationState.pending);
    expect(delivered.receiverName, 'Doña Marta');
    expect(delivered.outcomeReasonLabel, 'Cliente rechazó el pedido');

    final nothing = stops(outcomeRow({
      'items': [
        {'id': 'i1', 'delivered_quantity': '0', 'returned_quantity': '3', 'damaged_quantity': '0', 'missing_quantity': '0'},
      ],
    })).first;
    expect(nothing.progress, StopProgress.done);
    expect(nothing.statusLabel, 'No entregado');

    final rejected = stops(outcomeRow(const {}, status: OutboxStatus.rejected, message: 'La parada ya fue registrada.')).first;
    expect(rejected.hasOutcome, isFalse);
    expect(rejected.rejectionMessage, 'La parada ya fue registrada.');
  });

  testWidgets('not delivered: pick the reason and save; the departure goes first if it was missing', (tester) async {
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
        'operations': ['delivery.depart', 'delivery.outcome'],
        'catalogs': {
          'delivery_outcome_reasons': [
            {'value': 'business_closed', 'label': 'Negocio cerrado'},
            {'value': 'stock_shortage', 'label': 'Faltante desde bodega'},
          ],
        },
      }))),
      localRecordsProvider('delivery_runs').overrideWith((ref) => Stream.value([runJson()])),
      localRecordsProvider('customers').overrideWith((ref) => Stream.value(const [])),
      localRecordsProvider('products').overrideWith((ref) => Stream.value(const [])),
    ]);
    await tester.runAsync(() => container.read(sessionProvider.future));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Builder(builder: (context) => const DeliveryOutcomeScreen(runId: 'run1', stopId: 'ro1'))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('También se marcará la salida a ruta.'), findsOneWidget);

    await tester.tap(find.text('No se entregó'));
    await tester.pumpAndSettle();
    expect(find.text('Faltante desde bodega'), findsNothing, reason: 'set by the server, not picked');
    expect(find.text('Elige el motivo de la devolución.'), findsOneWidget);
    await tester.tap(find.text('Negocio cerrado'));
    await tester.pumpAndSettle();
    expect(find.text('L 0.00'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar entrega'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump(const Duration(milliseconds: 500));

    final rows = await tester.runAsync(() => (db.select(db.outbox)..orderBy([(row) => OrderingTerm(expression: row.id)])).get());
    expect(rows!.map((row) => row.type), ['delivery.depart', 'delivery.outcome']);
    final payload = jsonDecode(rows.last.payload) as Map<String, dynamic>;
    expect(payload['outcome_reason'], 'business_closed');
    expect(payload['receiver_name'], isNull);
    expect(payload['items'], [
      {'id': 'i1', 'delivered_quantity': '0', 'returned_quantity': '3', 'damaged_quantity': '0', 'missing_quantity': '0'},
    ]);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      container.dispose();
      await db.close();
    });
  });
}
