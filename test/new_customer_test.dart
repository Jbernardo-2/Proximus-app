import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:proximus_app/core/location_capture.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/preventa/presentation/new_customer_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

class MemorySecureStore extends SecureStore {
  MemorySecureStore(this.current);

  Session? current;

  @override
  Future<Session?> session() async => current;
}

void main() {
  testWidgets('a customer registered without signal is on the phone at once, on the chosen route', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final db = AppDatabase(NativeDatabase.memory());
    final session = Session(
      serverUrl: 'http://test',
      token: 't',
      user: const {'id': 7, 'name': 'Ana Preventista', 'role': 'preventista'},
      device: const {'code': 'M001'},
      abilities: const ['customers:manage'],
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secureStoreProvider.overrideWithValue(MemorySecureStore(session)),
        apiProvider.overrideWithValue(null),
        locationServiceProvider.overrideWithValue(LocationCaptureService(gateway: LocationOff())),
        manifestProvider.overrideWithValue(
          AsyncData(
            SyncManifest.fromJson({
              'operations': ['customer.create'],
            }),
          ),
        ),
        localRecordsProvider('routes').overrideWith(
          (ref) => Stream.value([
            {'id': 'r1', 'name': 'Ruta Centro', 'stops': <Map<String, dynamic>>[]},
            {'id': 'r2', 'name': 'Ruta Norte', 'stops': <Map<String, dynamic>>[]},
          ]),
        ),
      ],
    );
    await tester.runAsync(() => container.read(sessionProvider.future));

    final router = GoRouter(
      initialLocation: '/customers/new',
      routes: [
        GoRoute(path: '/customers/new', builder: (_, _) => const NewCustomerScreen()),
        GoRoute(
          path: '/customer/:id',
          builder: (_, state) => Scaffold(body: Text('Ficha ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar cliente'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe el nombre del negocio.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Elige en qué ruta queda el cliente.'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Elige en qué ruta queda el cliente.'), findsOneWidget, reason: 'with two routes the preventista picks one');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruta Norte').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(TextFormField, 'Nombre del negocio *'), -200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre del negocio *'), 'Pulpería Nueva Esperanza');
    await tester.tap(find.text('Pulpería'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Dirección *'), 'Barrio El Centro');
    await tester.scrollUntilVisible(find.widgetWithText(TextFormField, 'Teléfono'), 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextFormField, 'Teléfono'), '9999-1234');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar cliente'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();

    final row = await tester.runAsync(() => db.select(db.outbox).getSingle());
    final payload = jsonDecode(row!.payload) as Map<String, dynamic>;
    expect(row.type, 'customer.create');
    expect(payload['business_name'], 'Pulpería Nueva Esperanza');
    expect(payload['business_type'], 'Pulpería');
    expect(payload['whatsapp'], '9999-1234', reason: 'same number unless told otherwise');
    expect(payload['route_stop'], {'id': isA<String>(), 'sales_route_id': 'r2', 'visit_day': DateTime.now().weekday});
    expect(find.text('Ficha ${payload['id']}'), findsOneWidget, reason: 'opens the new customer to take an order');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      container.dispose();
      await db.close();
    });
  });
}

/// A phone with location turned off: capture answers at once.
class LocationOff implements LocationGateway {
  @override
  Future<bool> isServiceEnabled() async => false;
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.denied;
  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.denied;
  @override
  Future<Position?> lastKnownPosition() async => null;
  @override
  Future<Position> currentPosition() => throw UnimplementedError();
}
