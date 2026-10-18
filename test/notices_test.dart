import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/notifications/notices.dart';
import 'package:proximus_app/features/notifications/notices_screen.dart';

import 'delivery_run_test.dart' show MemorySecureStore;

Map<String, dynamic> notice(String id, String type, {bool read = false, String? run}) => {
  'id': id,
  'type': type,
  'title': 'Aviso $id',
  'message': 'Detalle $id',
  'severity': 'important',
  'read': read,
  'created_at': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
  'delivery_run_id': run,
};

void main() {
  test('a notice opens what it is about, and the run screens only for whoever settles', () {
    Notice of(String type, {String? run}) => Notice.fromJson(notice('1', type, run: run));

    expect(of('delivery_run_awaiting_settlement', run: 'r1').route(settles: true), '/settlements/r1');
    expect(of('delivery_outcome', run: 'r1').route(settles: true), '/runs/r1/review');
    expect(of('delivery_outcome', run: 'r1').route(settles: false), isNull, reason: 'the salesperson only reads it');
    expect(of('delivery_run_loaded').route(settles: false), '/deliveries');
    expect(of('product_count_adjusted').route(settles: true), '/counts');
    expect(of('something_new').route(settles: true), isNull);
  });

  test('without signal the bell shows the last notices kept on the phone', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.writeState('notifications', jsonEncode({'data': [notice('a', 'product_count_adjusted')], 'unread_count': 1}));
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      secureStoreProvider.overrideWithValue(MemorySecureStore(null)),
      apiProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);

    final notices = await container.read(noticesProvider.future);

    expect(notices.unread, 1);
    expect(notices.items.single.title, 'Aviso a');
  });

  testWidgets('the bell counts the unread notices and the list shows them first in bold', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final notices = (items: [Notice.fromJson(notice('a', 'product_count_adjusted')), Notice.fromJson(notice('b', 'order_confirmed', read: true))], unread: 1);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(MemorySecureStore(null)),
        apiProvider.overrideWithValue(null),
        noticesProvider.overrideWith((ref) async => notices),
      ],
      child: MaterialApp(home: Scaffold(appBar: AppBar(actions: const [NoticesBell()]), body: const NoticesScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('1 avisos sin leer'), findsOneWidget);
    expect(find.byTooltip('Marcar todos como leídos'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Aviso a')).style?.fontWeight, FontWeight.w800);
    expect(tester.widget<Text>(find.text('Aviso b')).style?.fontWeight, FontWeight.normal);
    expect(find.text('hace 5 min'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
