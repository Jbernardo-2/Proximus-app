import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/core/api.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/sync/outbox_service.dart';
import 'package:proximus_app/sync/sync_engine.dart';

/// Server double: pages per resource and a scripted answer per operation.
class FakeApi implements SyncApi {
  Map<String, dynamic> manifestBody = {};
  final Map<String, List<Map<String, dynamic>>> pages = {};
  final List<String?> cursorsSeen = [];
  final List<List<Map<String, dynamic>>> pushed = [];
  String Function(Map<String, dynamic> operation) answer = (_) => 'accepted';
  ApiException? failure;

  @override
  Future<Map<String, dynamic>> manifest() async {
    if (failure != null) throw failure!;
    return manifestBody;
  }

  @override
  Future<Map<String, dynamic>> pull(String resource, {String? cursor, int limit = 200}) async {
    cursorsSeen.add(cursor);
    final list = pages[resource] ?? const [];
    final index = cursor == null ? 0 : int.parse(cursor.split('#').last) + 1;
    if (index >= list.length) return {'records': [], 'next_cursor': cursor, 'has_more': false};
    return {...list[index], 'next_cursor': '$resource#$index'};
  }

  @override
  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> operations) async {
    if (failure != null) throw failure!;
    pushed.add(operations);
    return {
      'results': [
        for (final operation in operations)
          {
            'client_reference': operation['client_reference'],
            'status': answer(operation),
            'http_status': 201,
            'data': {'ok': true},
            'message': 'Esta parada no está pendiente de cobro.',
            'errors': answer(operation) == 'rejected' ? {'delivery_run_order': ['Esta parada no está pendiente de cobro.']} : null,
          },
      ],
    };
  }
}

void main() {
  late AppDatabase db;
  late FakeApi api;
  late OutboxService outbox;
  late SyncEngine engine;
  var now = DateTime(2026, 10, 14, 9);

  Map<String, dynamic> manifest({Map<String, int> last = const {'invoice': 4}}) => {
        'device': {
          'code': 'M001',
          'series': {
            for (final entry in last.entries) entry.key: {'prefix': 'FAC-M001-', 'last_number': entry.value},
          },
        },
        'resources': {
          'products': {'mode': 'delta', 'available': true},
          'customers': {'mode': 'full', 'available': true},
          'delivery_runs': {'mode': 'full', 'available': false},
        },
      };

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeApi()..manifestBody = manifest();
    outbox = OutboxService(db);
    now = DateTime(2026, 10, 14, 9);
    engine = SyncEngine(db: db, api: api, outbox: outbox, clock: () => now);
  });

  tearDown(() => db.close());

  Future<List<String>> ids(String resource) async =>
      [for (final row in await (db.select(db.syncRecords)..where((r) => r.resource.equals(resource))).get()) row.id]..sort();

  test('delta resources keep a cursor and apply deletions; full resources are replaced', () async {
    api.pages['products'] = [
      {'records': [{'id': 'p1', 'name': 'Agua'}, {'id': 'p2', 'name': 'Jugo'}], 'has_more': true},
      {'records': [{'id': 'p3', 'name': 'Soda'}], 'has_more': false},
    ];
    api.pages['customers'] = [
      {'records': [{'id': 'c1'}, {'id': 'c2'}], 'has_more': false},
    ];
    await db.into(db.syncRecords).insert(SyncRecordsCompanion.insert(resource: 'delivery_runs', id: 'old', data: '{}'));

    final report = await engine.sync();

    expect(report.ok, isTrue);
    expect(report.pulled, {'products': 3, 'customers': 2});
    expect(await ids('products'), ['p1', 'p2', 'p3']);
    expect(await ids('delivery_runs'), isEmpty, reason: 'a resource no longer available is forgotten');
    expect(await db.readState('cursor:products'), 'products#1');

    api.pages['products'] = [
      {'records': [], 'has_more': false},
      {'records': [], 'has_more': false},
      {'records': [{'id': 'p2', 'deleted': true}, {'id': 'p1', 'name': 'Agua 1L'}], 'has_more': false},
    ];
    api.pages['customers'] = [
      {'records': [{'id': 'c2'}], 'has_more': false},
    ];
    api.cursorsSeen.clear();
    await engine.sync();

    expect(api.cursorsSeen.first, 'products#1', reason: 'the next sync continues from the saved cursor');
    expect(await ids('products'), ['p1', 'p3']);
    expect(jsonDecode((await (db.select(db.syncRecords)..where((r) => r.id.equals('p1'))).getSingle()).data)['name'], 'Agua 1L');
    expect(await ids('customers'), ['c2']);
  });

  test('numbers are reserved with the operation and follow the server when it is ahead', () async {
    await outbox.adoptServerSeries({'invoice': {'prefix': 'FAC-M001-', 'last_number': 4}});

    final first = await outbox.enqueue(
      deviceCode: 'M001',
      type: 'delivery.payment',
      summary: 'Pulpería Marta',
      build: (number) async => {'invoice_number': await number('invoice')},
    );
    final second = await outbox.enqueue(
      deviceCode: 'M001',
      type: 'delivery.payment',
      summary: 'Bodega Luis',
      build: (number) async => {'invoice_number': await number('invoice')},
    );

    expect(jsonDecode(first.payload)['invoice_number'], 'FAC-M001-000005');
    expect(jsonDecode(second.payload)['invoice_number'], 'FAC-M001-000006');
    expect(first.clientReference, startsWith('M001:'));

    await outbox.adoptServerSeries({'invoice': {'prefix': 'FAC-M001-', 'last_number': 3}});
    expect(await outbox.nextNumber('invoice'), 'FAC-M001-000007', reason: 'a lower server number never moves the counter back');
    await outbox.adoptServerSeries({'invoice': {'prefix': 'FAC-M001-', 'last_number': 20}});
    expect(await outbox.nextNumber('invoice'), 'FAC-M001-000021');
  });

  test('a failed build does not consume a number', () async {
    await outbox.adoptServerSeries({'invoice': {'prefix': 'FAC-M001-', 'last_number': 0}});

    await expectLater(
      outbox.enqueue(deviceCode: 'M001', type: 'delivery.payment', summary: '', build: (number) async {
        await number('invoice');
        throw StateError('validación local');
      }),
      throwsStateError,
    );

    expect(await outbox.nextNumber('invoice'), 'FAC-M001-000001');
  });

  test('the queue is sent in order; accepted, rejected and failed are handled apart', () async {
    for (final name in ['uno', 'dos', 'tres']) {
      await outbox.enqueue(deviceCode: 'M001', type: 'visit.no_sale', summary: name, build: (_) async => {'name': name});
    }
    api.answer = (operation) => switch (operation['payload']['name']) { 'dos' => 'rejected', 'tres' => 'failed', _ => 'accepted' };

    final report = await engine.sync();

    expect(api.pushed.single.map((o) => o['payload']['name']), ['uno', 'dos', 'tres']);
    expect(report.pushed, 1);
    expect(report.rejected, 1);
    final rows = await (db.select(db.outbox)).get();
    expect(rows.map((r) => r.status), [OutboxStatus.done, OutboxStatus.rejected, OutboxStatus.pending]);
    expect(rows[1].message, 'Esta parada no está pendiente de cobro.');
    expect(rows[2].attempts, 1);
    expect(rows[2].nextAttemptAt, now.add(const Duration(seconds: 30)));

    api.answer = (_) => 'accepted';
    await engine.sync();
    expect(api.pushed, hasLength(1), reason: 'a failed operation waits for its backoff');

    now = now.add(const Duration(minutes: 1));
    await engine.sync();
    expect(api.pushed, hasLength(2));
    expect((await db.select(db.outbox).get()).map((r) => r.status), [OutboxStatus.done, OutboxStatus.rejected, OutboxStatus.done]);

    now = now.add(const Duration(days: 8));
    await engine.sync();
    expect((await db.select(db.outbox).get()).map((r) => r.status), [OutboxStatus.rejected], reason: 'done operations are purged after a week');
  });

  test('without signal nothing is lost and the report carries the error', () async {
    await outbox.enqueue(deviceCode: 'M001', type: 'visit.no_sale', summary: '', build: (_) async => {});
    api.failure = ApiException('Sin conexión con el servidor.');

    final report = await engine.sync();

    expect(report.ok, isFalse);
    expect(report.error!.isNetwork, isTrue);
    expect((await db.select(db.outbox).getSingle()).status, OutboxStatus.pending);
  });

  test('a blocked phone wipes everything, including its series', () async {
    await outbox.adoptServerSeries({'invoice': {'prefix': 'FAC-M001-', 'last_number': 2}});
    await outbox.enqueue(deviceCode: 'M001', type: 'visit.no_sale', summary: '', build: (_) async => {});
    await db.into(db.syncRecords).insert(SyncRecordsCompanion.insert(resource: 'customers', id: 'c1', data: '{}'));
    api.failure = ApiException('Este teléfono fue bloqueado.', status: 423, code: 'device_revoked');

    await expectLater(engine.sync(), throwsA(isA<DeviceRevokedException>()));

    expect(await db.select(db.outbox).get(), isEmpty);
    expect(await db.select(db.syncRecords).get(), isEmpty);
    expect(await db.select(db.documentSeries).get(), isEmpty);
  });

  test('an expired session keeps the queue for the next login', () async {
    await outbox.enqueue(deviceCode: 'M001', type: 'visit.no_sale', summary: '', build: (_) async => {});
    api.failure = ApiException('Unauthenticated.', status: 401);

    await expectLater(engine.sync(), throwsA(isA<SessionExpiredException>()));

    expect(await db.select(db.outbox).get(), hasLength(1));
  });

  test('changing user keeps the phone series', () async {
    await outbox.adoptServerSeries({'invoice': {'prefix': 'FAC-M001-', 'last_number': 9}});
    await db.into(db.outbox).insert(OutboxCompanion.insert(clientReference: 'x', type: 't', payload: '{}', createdAt: now, status: const Value(OutboxStatus.done)));

    await db.wipe();

    expect(await db.select(db.outbox).get(), isEmpty);
    expect(await outbox.nextNumber('invoice'), 'FAC-M001-000010');
  });
}
