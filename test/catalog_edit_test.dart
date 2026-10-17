import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/api.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/bodega/application/catalog_actions.dart';
import 'package:proximus_app/features/bodega/application/warehouse_run_actions.dart';
import 'package:proximus_app/features/bodega/presentation/product_detail_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore;
import 'warehouse_catalog_test.dart' show productJson, stocks;

/// Answers the barcode call as the server does and remembers what was sent.
class _FakeApi extends ProximusApi {
  _FakeApi() : super(baseUrl: 'http://test');

  final sent = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> data) async {
    sent[path] = data;
    return {'data': {'barcode': data['barcode']}};
  }
}

class _NoSync extends SyncController {
  @override
  SyncStatus build() => const SyncStatus();

  @override
  Future<void> sync({bool pushOnly = false}) async {}
}

Session keeper(List<String> abilities) => Session(serverUrl: 'http://test', token: 't', user: const {'id': 7, 'name': 'Rosa', 'role': 'bodeguero'}, device: const {'code': 'B001'}, abilities: abilities);

void main() {
  test('a new barcode reaches the server and the phone catalog at once, so the scanner finds it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.syncRecords).insert(SyncRecordsCompanion.insert(resource: 'products', id: 'p1', data: jsonEncode(productJson('p1', 'Arroz 1 lb'))));
    final api = _FakeApi();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      apiProvider.overrideWithValue(api),
      syncProvider.overrideWith(_NoSync.new),
    ]);
    addTearDown(container.dispose);

    await container.read(catalogActionsProvider).setBarcode('p1', 'p1-f', '7409999');

    expect(api.sent['/products/p1/presentations/p1-f/barcode'], {'barcode': '7409999'});
    final row = await (db.select(db.syncRecords)..where((r) => r.id.equals('p1'))).getSingle();
    final presentations = (jsonDecode(row.data)['presentations'] as List).cast<Map>();
    expect(presentations.firstWhere((presentation) => presentation['id'] == 'p1-f')['barcode'], '7409999');
    expect(presentations.firstWhere((presentation) => presentation['id'] == 'p1-u')['barcode'], isNull, reason: 'the other presentation is untouched');
  });

  group('product page', () {
    Future<void> pump(WidgetTester tester, List<String> abilities) async {
      tester.view.physicalSize = const Size(384 * 3, 820 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(MemorySecureStore(keeper(abilities))),
          apiProvider.overrideWithValue(null),
          manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({'default_warehouse': {'id': 'w1', 'name': 'Bodega central'}}))),
          localRecordsProvider('products').overrideWith((ref) => Stream.value([productJson('p1', 'Arroz 1 lb', barcode: '7401234567890')])),
          localRecordsProvider('stocks').overrideWith((ref) => Stream.value(const [])),
          liveResourceProvider('stocks').overrideWith((ref) async => stocks),
          liveResourceProvider('warehouses').overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: ProductDetailScreen(productId: 'p1')),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('whoever manages the catalog can change the photo and each barcode', (tester) async {
      await pump(tester, const ['catalog:manage', 'inventory:operate']);

      expect(find.byIcon(Icons.photo_camera), findsOneWidget);
      await tester.scrollUntilVisible(find.byTooltip('Código de barras').last, 200, scrollable: find.byType(Scrollable).first);
      expect(find.byTooltip('Código de barras'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Código de barras').last);
      await tester.pumpAndSettle();
      expect(find.text('Código de Fardo 24'), findsOneWidget);
      expect(find.text('Quitar código'), findsOneWidget, reason: 'the box already has a code');
      expect(tester.takeException(), isNull);
    });

    testWidgets('without the catalog permission the product is read only', (tester) async {
      await pump(tester, const ['inventory:operate']);

      expect(find.byIcon(Icons.photo_camera), findsNothing);
      expect(find.byTooltip('Código de barras'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
