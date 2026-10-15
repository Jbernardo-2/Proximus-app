import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/api.dart';
import 'package:proximus_app/core/product_images.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/preventa/data/order_detail.dart';
import 'package:proximus_app/features/preventa/data/preventa_models.dart';
import 'package:proximus_app/features/preventa/presentation/order_detail_screen.dart';

OutboxData orderRow({String status = OutboxStatus.pending, String? result, String? message}) => OutboxData(
      id: 1,
      clientReference: 'M001:abc12345-6789',
      type: 'order.create',
      payload: jsonEncode({
        'customer_id': 'c1',
        'order_date': '2026-10-15',
        'requested_delivery_date': '2026-10-16',
        'payment_term': 'credit',
        'notes': 'Entregar temprano',
        'items': [
          {'product_presentation_id': 'p1', 'quantity': '3', 'unit_price': '20.0000'},
          {'product_presentation_id': 'gone', 'quantity': '1', 'unit_price': '5'},
        ],
      }),
      status: status,
      summary: 'Pulpería',
      attempts: 0,
      createdAt: DateTime(2026, 10, 15, 9),
      result: result,
      message: message,
    );

const names = {'p1': (productId: 'prod-1', product: 'Arroz 1 lb', presentation: 'Unidad')};

final serverOrder = {
  'id': 'o1',
  'customer_id': 'c1',
  'client_reference': 'M001:abc12345-6789',
  'order_number': 'PED-2026-000030',
  'order_date': '2026-10-15',
  'requested_delivery_date': '2026-10-16',
  'status': 'confirmed',
  'status_label': 'Confirmado',
  'payment_term': 'cash',
  'total': '60.0000',
  'items': [
    {'product_id': 'prod-1', 'product_name': 'Arroz 1 lb', 'presentation_name': 'Unidad', 'quantity': '3.000000', 'unit_price': '20.0000', 'line_total': '60.0000'},
  ],
};

class FakeApi extends ProximusApi {
  FakeApi(this.answers) : super(baseUrl: 'http://test');

  /// Status to answer per URL; missing means the download works.
  final Map<String, int> answers;
  final List<String> requested = [];

  @override
  Future<void> download(String url, String savePath) async {
    requested.add(url);
    final status = answers[url];
    if (status != null) throw ApiException('No se descargó la imagen.', status: status);
    await File(savePath).writeAsBytes([1, 2, 3]);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('an order still on the phone shows its lines, named from the catalog', () {
    final detail = findOrderDetail('M001:abc12345-6789', downloaded: const [], outbox: [orderRow()], presentationNames: names)!;

    expect(detail.reference, 'Temporal ABC12345');
    expect(detail.state, LocalOperationState.pending);
    expect(detail.paymentTerm, 'credit');
    expect(detail.notes, 'Entregar temprano');
    expect(detail.lines.first.productName, 'Arroz 1 lb');
    expect(detail.lines.first.lineTotal.toFixed(2), '60.00');
    expect(detail.lines.last.productName, 'Producto no disponible en el teléfono');
    expect(detail.total.toFixed(2), '65.00');
  });

  test('once downloaded, the server copy wins: number, status and lines as sold', () {
    final accepted = orderRow(status: OutboxStatus.done, result: jsonEncode({'id': 'o1', 'order_number': 'PED-2026-000030'}));

    for (final key in ['M001:abc12345-6789', 'o1']) {
      final detail = findOrderDetail(key, downloaded: [serverOrder], outbox: [accepted], presentationNames: names)!;
      expect(detail.reference, 'PED-2026-000030');
      expect(detail.state, LocalOperationState.synchronized);
      expect(detail.statusLabel, 'Confirmado');
      expect(detail.lines.single.quantity.toString(), '3');
    }
    expect(findOrderDetail('otro', downloaded: [serverOrder], outbox: const [], presentationNames: names), isNull);
  });

  testWidgets('the order screen only shows the order, with nothing to change', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final rejected = findOrderDetail('M001:abc12345-6789',
        downloaded: const [], outbox: [orderRow(status: OutboxStatus.rejected, message: 'El cliente está bloqueado.')], presentationNames: names);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(null),
        orderDetailProvider('M001:abc12345-6789').overrideWithValue(rejected),
        customerProfileProvider('c1').overrideWithValue(null),
        productImagesProvider.overrideWith(() => FixedImages()),
      ],
      child: const MaterialApp(home: OrderDetailScreen(orderKey: 'M001:abc12345-6789')),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Temporal ABC12345'), findsOneWidget);
    expect(find.text('Rechazado'), findsOneWidget);
    expect(find.text('El cliente está bloqueado.'), findsOneWidget);
    expect(find.text('3 × Unidad · L 20.00 c/u'), findsOneWidget);
    expect(find.text('L 65.00'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  downloadedBeforePhotosTest();

  test('thumbnails: downloads what is missing, drops old photos, skips gone ones and stops without signal', () async {
    final dir = await Directory.systemTemp.createTemp('thumbs');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/a_old.jpg').writeAsBytes([0]);
    await File('${dir.path}/b_v1.jpg').writeAsBytes([0]);
    final store = ProductImageStore(dir);
    Map<String, dynamic> product(String id, String? version) =>
        {'id': id, 'thumbnail_url': version == null ? null : 'http://test/$id', 'image_version': version};

    final api = FakeApi({'http://test/c': 404, 'http://test/e': 429});
    final saved = <String>[];
    final count = await store.update(
      products: [product('a', 'new'), product('b', 'v1'), product('c', 'v1'), product('d', 'v1'), product('e', 'v1'), product('f', 'v1'), product('g', null)],
      api: api,
      onSaved: (id, _) => saved.add(id),
    );

    expect(api.requested, ['http://test/a', 'http://test/c', 'http://test/d', 'http://test/e'], reason: 'b is already there; stops at e (too many requests)');
    expect(count, 2);
    expect(saved, ['a', 'd']);
    expect((await store.index()).keys.toSet(), {'a', 'b', 'd'});
    expect(await File('${dir.path}/a_old.jpg').exists(), isFalse, reason: 'the old photo of a is replaced');
  });
}

void downloadedBeforePhotosTest() {
  test('a catalog downloaded before photos existed is downloaded again once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final dir = await Directory.systemTemp.createTemp('thumbs');
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    await db.into(db.syncRecords).insert(SyncRecordsCompanion.insert(resource: 'products', id: 'a', data: jsonEncode({'id': 'a', 'name': 'Arroz'})));
    await db.writeState('cursor:products', 'old-cursor');
    final api = FakeApi(const {});
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      apiProvider.overrideWithValue(api),
      syncEngineProvider.overrideWithValue(null),
      productImageDirectoryProvider.overrideWith((ref) async => dir),
    ]);
    addTearDown(container.dispose);

    await container.read(productImagesProvider.notifier).update();

    expect(await db.readState('cursor:products'), isNull);
    expect(api.requested, isEmpty);
  });
}

class FixedImages extends ProductImagesController {
  @override
  Map<String, String> build() => const {};
}
