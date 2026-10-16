import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/sync/operation_status_banner.dart';

OutboxData payment(String status, {String? message}) => OutboxData(
  id: 1,
  clientReference: 'M004:abono',
  type: 'customer.payment',
  payload: jsonEncode({'receipt_number': 'ABO-M004-000001'}),
  status: status,
  summary: 'Farmacia El Sauce',
  attempts: 1,
  createdAt: DateTime(2026, 10, 16, 9),
  message: message,
);

void main() {
  Future<void> show(WidgetTester tester, OutboxData row) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        outboxRowsProvider.overrideWith((ref) => Stream.value([row])),
        syncProvider.overrideWith(_IdleSync.new),
      ],
      child: const MaterialApp(
        home: Scaffold(body: OperationStatusBanner(type: 'customer.payment', field: 'receipt_number', value: 'ABO-M004-000001', noun: 'este abono')),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the receipt says right away whether the server took the payment', (tester) async {
    await show(tester, payment(OutboxStatus.pending));
    expect(find.textContaining('Guardado en el teléfono'), findsOneWidget);

    await show(tester, payment(OutboxStatus.done));
    expect(find.text('Aceptado por el servidor.'), findsOneWidget);

    await show(tester, payment(OutboxStatus.rejected, message: 'El abono no se registró: este cliente no está en tus jornadas activas.'));
    expect(find.textContaining('El servidor rechazó este abono: El abono no se registró: este cliente no está en tus jornadas activas.'), findsOneWidget);
    expect(find.textContaining('No entregues este comprobante'), findsOneWidget);
  });
}

class _IdleSync extends SyncController {
  @override
  SyncStatus build() => const SyncStatus();
}
