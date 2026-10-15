import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/sync/sync_screen.dart';
import 'package:proximus_app/sync/background_sync.dart';
import 'package:proximus_app/sync/operation_view.dart';
import 'package:proximus_app/sync/outbox_service.dart';
import 'package:proximus_app/sync/sync_engine.dart';

import 'sync_engine_test.dart' show FakeApi;

OutboxData row(int id, String type, Map<String, dynamic> payload, {String status = OutboxStatus.pending, int attempts = 0, int? http, String? message, Map<String, dynamic>? result}) =>
    OutboxData(
      id: id,
      clientReference: 'M001:$id',
      type: type,
      payload: jsonEncode(payload),
      status: status,
      summary: 'Pulpería Doña Marta',
      attempts: attempts,
      createdAt: DateTime(2026, 10, 14, 8),
      httpStatus: http,
      message: message,
      result: result == null ? null : jsonEncode(result),
    );

class MemorySecureStore extends SecureStore {
  MemorySecureStore(this.current);

  Session? current;

  @override
  Future<Session?> session() async => current;

  @override
  Future<void> clearSession() async => current = null;
}

void main() {
  final order = {'customer_id': 'c1', 'payment_term': 'credit', 'items': [{'quantity': '2', 'unit_price': '25'}]};

  test('each operation says where it stands', () {
    expect(OperationView.of(row(1, 'order.create', order), sending: false, offline: false).state, OperationState.saved);
    expect(OperationView.of(row(1, 'order.create', order), sending: false, offline: true).state, OperationState.waitingSignal);
    expect(OperationView.of(row(1, 'order.create', order), sending: true, offline: true).state, OperationState.sending);
    expect(OperationView.of(row(1, 'order.create', order, attempts: 2), sending: false, offline: false).state, OperationState.retrying);

    final accepted = OperationView.of(row(1, 'order.create', order, status: OutboxStatus.done, result: {'order_number': 'PED-2026-000031'}), sending: false, offline: false);
    expect(accepted.state, OperationState.accepted);
    expect(accepted.serverNumber, 'PED-2026-000031');
    expect(accepted.details, contains(('Total', 'L 50.00')));
    expect(accepted.details, contains(('Condición', 'Crédito')));
  });

  test('a rejection comes with what to do about it', () {
    final payment = OperationView.of(
      row(2, 'customer.payment', {'customer_id': 'c1', 'receipt_number': 'ABO-M001-000004', 'amount': '100', 'receipt': {'number': 'ABO-M001-000004'}},
          status: OutboxStatus.rejected, http: 422, message: 'La aplicación a deudas debe sumar exactamente el abono.'),
      sending: false,
      offline: false,
    );
    expect(payment.customerHoldsReceipt, isTrue);
    expect(payment.recommendation, contains('comprobante impreso'));

    expect(OperationView.recommend('order.create', 403, 'This action is unauthorized.'), contains('ya no está asignado'));
    expect(OperationView.recommend('order.create', 422, 'La presentación seleccionada no está disponible para venta.'), contains('dejó de venderse'));
  });

  test('retrying a rejected operation sends it again with the same reference, and the clock offset is recorded', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final outbox = OutboxService(db);
    final api = FakeApi()
      ..manifestBody = {
        'server_time': DateTime(2026, 10, 14, 9, 10).toIso8601String(),
        'resources': <String, dynamic>{},
      };
    final engine = SyncEngine(db: db, api: api, outbox: outbox, clock: () => DateTime(2026, 10, 14, 9));
    final queued = await outbox.enqueue(deviceCode: 'M001', type: 'visit.no_sale', summary: 'Pulpería', build: (_) async => {'customer_id': 'c1'});

    api.answer = (_) => 'rejected';
    await engine.sync();
    expect((await db.select(db.outbox).getSingle()).status, OutboxStatus.rejected);
    expect(await db.readState('clock_offset_seconds'), '600', reason: 'the phone is 10 minutes behind');

    await outbox.retry(queued.id);
    api.answer = (_) => 'accepted';
    await engine.sync();

    final again = await db.select(db.outbox).getSingle();
    expect(again.status, OutboxStatus.done);
    expect(api.pushed.last.single['client_reference'], queued.clientReference);
  });

  test('the background task stays out of the way while the app is open', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 10, 14, 9);
    final store = MemorySecureStore(Session(serverUrl: 'http://127.0.0.1:9', token: 't', user: const {'id': 1}, device: const {'code': 'M001'}, abilities: const []));

    await db.writeState(foregroundHeartbeatKey, now.subtract(const Duration(minutes: 1)).toIso8601String());
    expect(await runBackgroundSync(store: store, database: db, clock: () => now), isTrue);
    expect(await db.readState('manifest'), isNull, reason: 'it did not sync while the app was open');

    expect(await runBackgroundSync(store: MemorySecureStore(null), database: db, clock: () => now), isTrue, reason: 'nothing to do without a session');
  });

  testWidgets('the activity screen shows a rejected payment and lets it be retried', (tester) async {
    await initializeDateFormatting('es');
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final payment = {
      'customer_id': 'c1',
      'receipt_number': 'ABO-M001-000004',
      'amount': '100',
      'payment_lines': [{'method': 'cash', 'amount': '100'}],
      'allocations': [{'receivable_id': 'r1', 'amount': '100'}],
      'receipt': {'number': 'ABO-M001-000004'},
    };
    await tester.runAsync(() async {
      await db.into(db.outbox).insert(OutboxCompanion.insert(
            clientReference: 'M001:pay',
            type: 'customer.payment',
            payload: jsonEncode(payment),
            createdAt: DateTime(2026, 10, 14, 8),
            summary: const Value('Pulpería Doña Marta'),
            status: const Value(OutboxStatus.rejected),
            httpStatus: const Value(422),
            message: const Value('La aplicación a deudas debe sumar exactamente el abono.'),
          ));
      await db.into(db.outbox).insert(OutboxCompanion.insert(clientReference: 'M001:ord', type: 'order.create', payload: jsonEncode(order), createdAt: DateTime(2026, 10, 14, 8, 30)));
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), apiProvider.overrideWithValue(null), sessionProvider.overrideWith(() => _NoSession())],
      child: const MaterialApp(home: SyncScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rechazadas · 1'), findsOneWidget);
    expect(find.textContaining('Guardado en el teléfono'), findsOneWidget);
    await tester.tap(find.text('Abono · Pulpería Doña Marta'));
    await tester.pumpAndSettle();
    expect(find.textContaining('comprobante impreso'), findsOneWidget);
    expect(find.text('Ver o reimprimir comprobante'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await tester.tap(find.text('Reintentar'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('Rechazadas · 1'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}

class _NoSession extends SessionController {
  @override
  Future<Session?> build() async => null;
}
