import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/modules.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/formatting.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/preventa/data/preventista_repository.dart';
import 'package:proximus_app/features/preventa/presentation/daily_route_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

Map<String, dynamic> stopJson(int order, {String status = 'pending', Map<String, dynamic> extra = const {}}) => {
      'id': 's$order',
      'route_stop_id': 's$order',
      'date': '2026-10-14',
      'visit_order': order,
      'status': status,
      'route': {'id': 'r1', 'name': 'Ruta Centro'},
      'customer': {
        'id': 'c$order',
        'code': 'CLI-$order',
        'business_name': 'Pulpería con un nombre bastante largo número $order',
        'address': 'Barrio El Centro, avenida principal, frente a la iglesia católica',
        'phone': '9999-000$order',
      },
      ...extra,
    };

OutboxData queued(int id, String type, Map<String, dynamic> payload, {String status = OutboxStatus.pending}) => OutboxData(
      id: id,
      clientReference: 'M001:$id',
      type: type,
      payload: jsonEncode(payload),
      status: status,
      summary: '',
      attempts: 0,
      createdAt: DateTime(2026, 10, 14, 8),
    );

Session session(List<String> abilities) => Session(
      serverUrl: 'http://test',
      token: 't',
      user: const {'id': 1, 'name': 'Ana', 'role': 'preventista'},
      device: const {'code': 'M001'},
      abilities: abilities,
    );

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('money keeps the web format and never rounds through double', () {
    expect(money(DecimalValue.parse('1234567.005')), 'L 1,234,567.01');
    expect(money(DecimalValue.parse('0')), 'L 0.00');
    expect(money(DecimalValue.parse('-50.5')), '-L 50.50');
  });

  test('balances follow the payments and credit orders recorded on the phone', () {
    final balances = const PreventistaRepository().balances(
      credits: [
        {'customer_id': 'c1', 'allows_credit': true, 'credit_limit': '1000', 'outstanding': '300', 'overdue': '100', 'committed': '0', 'available_credit': '700'},
      ],
      outbox: [
        queued(1, 'customer.payment', {'customer_id': 'c1', 'amount': '120'}),
        queued(2, 'order.create', {'customer_id': 'c1', 'payment_term': 'credit', 'items': [{'quantity': '4', 'unit_price': '50'}]}),
        queued(3, 'order.create', {'customer_id': 'c1', 'payment_term': 'cash', 'items': [{'quantity': '1', 'unit_price': '999'}]}),
        queued(4, 'customer.payment', {'customer_id': 'c1', 'amount': '500'}, status: OutboxStatus.rejected),
      ],
      pulledAt: null,
    );

    expect(balances['c1']!.outstanding.toFixed(2), '180.00');
    expect(balances['c1']!.available.toFixed(2), '620.00', reason: '700 + 120 paid - 200 on credit');
  });

  test('two routes on the same day are listed one after the other, not mixed', () {
    Map<String, dynamic> onRoute(int order, String id, String name) => {...stopJson(order), 'id': '$id-$order', 'route_stop_id': '$id-$order', 'route': {'id': id, 'name': name}};
    final route = const PreventistaRepository().mergeRouteActivity(
      records: [onRoute(1, 'r2', 'Ruta Norte'), onRoute(2, 'r1', 'Ruta Centro'), onRoute(1, 'r1', 'Ruta Centro'), onRoute(2, 'r2', 'Ruta Norte')],
      outbox: [
        queued(1, 'customer.create', {
          'id': 'nuevo',
          'business_name': 'Pulpería Nueva',
          'address': 'Kennedy',
          'route_stop': {'id': 'stop-nuevo', 'sales_route_id': 'r2', 'visit_day': 3},
        }),
      ],
      pulledAt: null,
      now: DateTime(2026, 10, 14, 10),
    );

    expect(route.routeNames, ['Ruta Centro', 'Ruta Norte']);
    expect(route.stops.map((stop) => stop.routeStopId), ['r1-1', 'r1-2', 'r2-1', 'r2-2', 'stop-nuevo']);
    expect(route.stops.last.routeName, 'Ruta Norte', reason: 'the new customer goes to the end of its own route');
    expect(route.stops.last.visitOrder, 3);
  });

  test('the menu shows what the server allows, not a list per role', () {
    final manifest = SyncManifest.fromJson({
      'resources': {
        'route_activity': {'mode': 'full', 'available': true},
        'customers': {'mode': 'full', 'available': true},
        'delivery_runs': {'mode': 'full', 'available': false},
      },
      'operations': ['order.create'],
    });

    expect(modulesFor(manifest, session(const ['orders:manage'])).map((m) => m.label), ['Ruta del día', 'Clientes']);
    expect(modulesFor(manifest, session(const ['reports:view'])).map((m) => m.label), contains('Reportes'));
  });

  testWidgets('the daily route fits a small phone and shows the day at a glance', (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 740 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final route = const PreventistaRepository().mergeRouteActivity(
      records: [stopJson(1, status: 'order_taken', extra: {'has_order': true, 'orders_total': '1250.5', 'has_payment': true, 'payments_total': '200'}), stopJson(2)],
      outbox: [queued(1, 'visit.no_sale', {'customer_id': 'c2', 'route_stop_id': 's2'})],
      pulledAt: DateTime(2026, 10, 14, 7),
      now: DateTime(2026, 10, 14, 10),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(null),
        manifestProvider.overrideWithValue(const AsyncData(null)),
        dailyRouteProvider.overrideWithValue(AsyncData(route)),
        customerBalancesProvider.overrideWithValue({
          'c1': CustomerBalance(
            allowsCredit: true,
            limit: DecimalValue.parse('5000'),
            outstanding: DecimalValue.parse('2300'),
            overdue: DecimalValue.parse('100'),
            available: DecimalValue.parse('2700'),
          ),
        }),
        outboxCountsProvider.overrideWith((ref) => Stream.value((pending: 1, rejected: 0))),
      ],
      child: const MaterialApp(home: DailyRouteScreen()),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Ruta Centro'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('L 1,250.50'), findsOneWidget);
    expect(find.text('L 200.00'), findsOneWidget);
    expect(find.text('Pedido tomado'), findsOneWidget);
    expect(find.text('Abonó'), findsOneWidget);
    expect(find.text('1 por enviar'), findsOneWidget);
    expect(find.textContaining('L 2,300.00'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Por enviar'), 200);
    expect(tester.takeException(), isNull);
    expect(find.text('Por enviar'), findsOneWidget, reason: 'the no-sale visit of stop 2 is still on the phone');
  });
}
