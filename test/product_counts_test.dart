import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/bodega/data/product_counts.dart';
import 'package:proximus_app/features/bodega/data/warehouse_catalog.dart';
import 'package:proximus_app/features/bodega/presentation/count_sheet.dart';
import 'package:proximus_app/features/bodega/presentation/counts_screen.dart';
import 'package:proximus_app/sync/sync_manifest.dart';

import 'delivery_run_test.dart' show MemorySecureStore;
import 'warehouse_catalog_test.dart' show products, stocks;

DecimalValue d(String value) => DecimalValue.parse(value);

OutboxData countRow(int id, String counted, {String status = OutboxStatus.pending, Map<String, dynamic>? result, String? message}) => OutboxData(
  id: id,
  clientReference: 'B001:$id',
  type: 'inventory.product_count',
  payload: jsonEncode({'warehouse_id': 'w1', 'product_id': 'p1', 'counted_quantity': counted, 'counted_at': DateTime(2026, 10, 16, 8 + id).toUtc().toIso8601String(), 'notes': id == 2 ? 'Bolsas rotas' : null}),
  status: status,
  summary: '',
  attempts: 0,
  createdAt: DateTime(2026, 10, 16, 8 + id),
  result: result == null ? null : jsonEncode(result),
  message: message,
);

final rows = [
  countRow(1, '18'),
  countRow(2, '17', status: OutboxStatus.done, result: {
    'count_number': 'CON-2026-000009',
    'items': [{'expected_quantity': '20.000000', 'counted_quantity': '17.000000', 'difference': '-3.000000'}],
  }),
  countRow(3, '5', status: OutboxStatus.rejected, message: 'La hora del conteo debe ser una fecha anterior a …'),
];

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('counts on the phone carry the server answer once applied, newest first', () {
    final counts = localCounts(rows);

    expect(counts.map((count) => count.outboxId), [3, 2, 1]);
    expect(counts[1].countNumber, 'CON-2026-000009');
    expect(counts[1].difference, d('-3'));
    expect(counts[1].notes, 'Bolsas rotas');
    expect(counts[0].isRejected, isTrue);
    expect(counts[2].isPending, isTrue);
    expect(counts[2].difference, isNull);
  });

  test('a count by boxes and loose units adds up in base units', () {
    final product = warehouseProducts(products: products, stocks: stocks).first.product;

    expect(countedTotal(product.presentations, {'p1-f': d('3'), 'p1-u': d('5')}), d('77'));
    expect(countedTotal(product.presentations, {'p1-f': null, 'p1-u': null}), isNull, reason: 'nothing typed is not a count of zero');
    expect(countedTotal(product.presentations, {'p1-u': d('0')}), d('0'));
  });

  group('screens', () {
    late List<Override> overrides;

    setUp(() => overrides = [
      secureStoreProvider.overrideWithValue(MemorySecureStore(null)),
      apiProvider.overrideWithValue(null),
      manifestProvider.overrideWithValue(AsyncData(SyncManifest.fromJson({'default_warehouse': {'id': 'w1', 'name': 'Bodega central'}}))),
      localRecordsProvider('products').overrideWith((ref) => Stream.value(products)),
      localRecordsProvider('stocks').overrideWith((ref) => Stream.value(stocks)),
      localRecordsProvider('warehouses').overrideWith((ref) => Stream.value(const [{'id': 'w1', 'name': 'Bodega central', 'is_default': true}])),
      outboxRowsProvider.overrideWith((ref) => Stream.value(rows)),
    ]);

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(384 * 3, 820 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: child)));
      await tester.pumpAndSettle();
    }

    testWidgets('counting is blind: boxes and units add up, and the system stock is not shown', (tester) async {
      final item = warehouseProducts(products: products, stocks: stocks).first;
      await pump(tester, Scaffold(body: CountSheet(item: item)));

      expect(find.textContaining('20'), findsNothing, reason: 'the 20 in the system must not steer the count');
      expect(find.text('Registrar conteo'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), '3');
      await tester.enterText(find.byType(TextField).at(1), '5');
      await tester.pump();
      expect(find.text('Total contado: 77 u'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the list shows the difference the server applied and an estimate while unsent', (tester) async {
      await pump(tester, const CountsScreen());

      expect(find.text('-3'), findsOneWidget);
      expect(find.text('≈ -2'), findsOneWidget, reason: '18 counted against the 20 downloaded');
      expect(find.text('Rechazado'), findsOneWidget);
      expect(find.text('Sin enviar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
