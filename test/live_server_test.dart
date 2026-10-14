// Runs the real sync cycle against a Proximus server. Skipped unless a token is given:
//   PROXIMUS_TOKEN=... PROXIMUS_URL=http://192.168.x.x/Proximus/public flutter test test/live_server_test.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/core/api.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/sync/outbox_service.dart';
import 'package:proximus_app/sync/sync_engine.dart';

final token = Platform.environment['PROXIMUS_TOKEN'] ?? '';
final url = Platform.environment['PROXIMUS_URL'] ?? 'http://192.168.101.76/Proximus/public';

void main() {
  test('a full sync against the server stores every available resource', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final api = ProximusApi(baseUrl: url, token: token);
    final engine = SyncEngine(db: db, api: api, outbox: OutboxService(db));

    final report = await engine.sync();

    expect(report.error, isNull, reason: report.error?.message);
    // ignore: avoid_print
    print('Recibido: ${report.pulled}');
    final manifest = await api.manifest();
    for (final entry in (manifest['resources'] as Map<String, dynamic>).entries) {
      if (entry.value['available'] == true) expect(report.pulled, contains(entry.key));
    }
    await db.close();
  }, skip: token.isEmpty ? 'Sin PROXIMUS_TOKEN' : null);
}
