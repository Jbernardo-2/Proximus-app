import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/main.dart';

/// Keystore double: everything in memory.
class MemorySecureStore extends SecureStore {
  MemorySecureStore(this.current);

  Session? current;

  @override
  Future<Session?> session() async => current;

  @override
  Future<void> saveSession(Session session) async => current = session;

  @override
  Future<void> clearSession() async => current = null;

  @override
  Future<String> serverUrl() async => 'http://test';

  @override
  Future<void> saveServerUrl(String url) async {}
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('closing the session returns to the login screen', (tester) async {
    final store = MemorySecureStore(Session(
      serverUrl: 'http://test',
      token: 't',
      user: const {'id': 7, 'name': 'Ana Preventista', 'role': 'preventista'},
      device: const {'code': 'M001'},
      abilities: const ['orders:manage'],
    ));
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secureStoreProvider.overrideWithValue(store),
      ],
      child: const ProximusApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ana Preventista'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Entrar'), findsOneWidget);
    expect(store.current, isNull);

    // Unmount first so the local database streams close, then close the database for real.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}
