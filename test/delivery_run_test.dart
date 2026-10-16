import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/reparto/application/delivery_providers.dart';
import 'package:proximus_app/features/reparto/data/delivery_models.dart';
import 'package:proximus_app/features/reparto/data/delivery_repository.dart';
import 'package:proximus_app/features/reparto/presentation/delivery_run_screen.dart';

Map<String, dynamic> stopJson(int order, {String status = 'loaded', String term = 'cash', String loaded = '3'}) => {
      'id': 'ro$order',
      'visit_order': order,
      'status': status,
      'status_label': status == 'delivered' ? 'Entregado' : 'Cargado',
      'order': {
        'id': 'o$order',
        'order_number': 'PED-2026-00004$order',
        'customer_id': 'c$order',
        'customer_name': 'Pulpería con un nombre bastante largo número $order',
        'customer_address': 'Barrio El Centro, avenida principal, frente a la iglesia católica',
        'payment_term': term,
      },
      'items': [
        {'id': 'i$order', 'product_id': 'p1', 'product_name': 'Arroz 1 lb', 'presentation_name': 'Unidad', 'unit_price': '18.0000', 'requested_quantity': '3.000000', 'loaded_quantity': '$loaded.000000'},
      ],
      'delivered_total': '0.0000',
      'collected_total': status == 'delivered' ? '54.0000' : '0.0000',
      'balance_due': '0.0000',
    };

Map<String, dynamic> runJson({String status = 'loaded'}) => {
      'id': 'run1',
      'run_number': 'RUT-2026-000013',
      'status': status,
      'scheduled_date': '2026-10-15',
      'vehicle_code': 'CAMPO-01',
      'vehicle_license_plate': 'PCA 0001',
      'orders': [stopJson(2, term: 'credit', loaded: '2'), stopJson(1), stopJson(3, status: 'delivered'), stopJson(4, status: 'awaiting_payment')],
    };

OutboxData depart({String status = OutboxStatus.pending, String? message}) => OutboxData(
      id: 1,
      clientReference: 'M001:salida',
      type: 'delivery.depart',
      payload: jsonEncode({'delivery_run_id': 'run1'}),
      status: status,
      summary: 'Jornada RUT-2026-000013',
      attempts: 0,
      createdAt: DateTime(2026, 10, 15, 7),
      message: message,
    );

class MemorySecureStore extends SecureStore {
  MemorySecureStore(this.current);

  Session? current;

  @override
  Future<Session?> session() async => current;
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('the run on the phone: stops in order, contacts attached, and a departure still to send counts as left', () {
    final runs = mergeDeliveryRuns(
      records: [runJson()],
      outbox: const [],
      customers: [
        {'id': 'c1', 'code': 'CAMPO-01', 'business_name': 'Pulpería', 'address': 'Centro', 'phone': '9999-0001'},
      ],
      pulledAt: null,
    );
    final run = runs.single;

    expect(run.stops.map((stop) => stop.visitOrder), [1, 2, 3, 4]);
    expect(run.stops.first.customer?.phone, '9999-0001');
    expect(run.hasLeft, isFalse);
    expect(run.pendingStops.map((stop) => stop.id), ['ro1', 'ro2', 'ro4'], reason: 'awaiting payment still needs the driver');
    expect(run.doneStops.map((stop) => stop.id), ['ro3']);
    expect(run.stops[1].hasShortItems, isTrue);
    expect(run.stops[1].isCredit, isTrue);
    expect(run.loadedTotal.toFixed(2), '198.00');

    final left = mergeDeliveryRuns(records: [runJson()], outbox: [depart()], customers: const [], pulledAt: null).single;
    expect(left.hasLeft, isTrue);
    expect(left.statusLabel, 'En ruta');

    final rejected = mergeDeliveryRuns(records: [runJson()], outbox: [depart(status: OutboxStatus.rejected, message: 'Solo una jornada cargada puede iniciar la ruta.')], customers: const [], pulledAt: null).single;
    expect(rejected.hasLeft, isFalse);
    expect(rejected.departureRejection, contains('jornada cargada'));
  });

  testWidgets('the run fits the test phone and the driver leaves without signal', (tester) async {
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
      localRecordsProvider('delivery_runs').overrideWith((ref) => Stream.value([runJson()])),
      localRecordsProvider('customers').overrideWith((ref) => Stream.value(const [])),
    ]);
    await tester.runAsync(() => container.read(sessionProvider.future));

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: DeliveryRunScreen())));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('RUT-2026-000013'), findsOneWidget);
    expect(find.text('Cargada, sin salir'), findsOneWidget);
    expect(find.textContaining('A 1 parada le falta mercadería'), findsOneWidget);
    expect(find.text('1 de 4 entregas terminadas'), findsOneWidget);
    expect(find.byType(DeliveryStopCard), findsWidgets);

    await tester.tap(find.text('Salir a ruta'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Salir'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();

    final row = await tester.runAsync(() => db.select(db.outbox).getSingle());
    expect(row!.type, 'delivery.depart');
    expect(jsonDecode(row.payload)['delivery_run_id'], 'run1');
    expect(container.read(deliveryRunProvider('run1'))!.hasLeft, isTrue);
    expect(find.text('Salir a ruta'), findsNothing);
    expect(find.textContaining('Salida guardada en el teléfono'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      container.dispose();
      await db.close();
    });
  });

  test('only runs that need the driver show, today first and then the newest', () {
    Map<String, dynamic> run(String id, String date, {String status = 'in_transit', bool finished = false}) => {
          ...runJson(status: status),
          'id': id,
          'run_number': 'RUT-$id',
          'scheduled_date': date,
          'orders': [stopJson(1, status: finished ? 'delivered' : 'loaded')],
        };
    final runs = mergeDeliveryRuns(
      records: [
        run('viejo', '2026-10-12'),
        run('terminado', '2026-10-10', status: 'awaiting_settlement', finished: true),
        run('entregado-sin-liquidar', '2026-10-14', finished: true),
        run('ayer', '2026-10-14'),
        run('hoy', '2026-10-15', status: 'loaded'),
      ],
      outbox: const [],
      customers: const [],
      pulledAt: null,
    );

    expect(runsToWork(runs, now: DateTime(2026, 10, 15, 9)).map((run) => run.id), ['hoy', 'ayer', 'viejo']);
  });

  testWidgets('with several runs the driver picks one; finished ones only leave a note', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final today = DateTime.now();
    String day(int back) => today.subtract(Duration(days: back)).toIso8601String().substring(0, 10);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        outboxRowsProvider.overrideWith((ref) => Stream.value(const <OutboxData>[])),
        syncStateProvider('pulled_at:delivery_runs').overrideWith((ref) => Stream.value(null)),
        secureStoreProvider.overrideWithValue(MemorySecureStore(null)),
        apiProvider.overrideWithValue(null),
        localRecordsProvider('delivery_runs').overrideWith((ref) => Stream.value([
              {...runJson(status: 'in_transit'), 'id': 'a', 'run_number': 'RUT-VIEJA', 'scheduled_date': day(3)},
              {...runJson(), 'id': 'b', 'run_number': 'RUT-HOY', 'scheduled_date': day(0)},
              {...runJson(status: 'awaiting_settlement'), 'id': 'c', 'run_number': 'RUT-LISTA', 'scheduled_date': day(5), 'orders': [stopJson(1, status: 'delivered')]},
            ])),
        localRecordsProvider('customers').overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: DeliveryRunScreen()),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Tienes 2 jornadas sin terminar'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Jornada RUT-HOY')).dy, lessThan(tester.getTopLeft(find.text('Jornada RUT-VIEJA')).dy));
    expect(find.text('Jornada RUT-LISTA'), findsNothing);
    expect(find.text('1 jornada terminada espera la liquidación del supervisor.'), findsOneWidget);
    expect(find.byType(DeliveryStopCard), findsNothing, reason: 'stops of different runs are never mixed');

  });

  test('a stop is finished only when delivered and paid, partially delivered or not delivered', () {
    LocalDeliveryStop stop(String status) => LocalDeliveryStop.fromJson(stopJson(1, status: status));
    expect(stop('loaded').progress, StopProgress.pending);
    expect(stop('awaiting_payment').progress, StopProgress.awaitingPayment);
    for (final status in ['delivered', 'partially_delivered', 'not_delivered']) {
      expect(stop(status).progress, StopProgress.done);
    }
  });
}
