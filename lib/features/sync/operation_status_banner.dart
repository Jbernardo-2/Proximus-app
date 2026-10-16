import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/database.dart';

/// Live answer of the server for a document just issued (a receipt, an invoice), so
/// the user knows right away whether to hand it over, instead of finding out later.
class OperationStatusBanner extends ConsumerWidget {
  const OperationStatusBanner({super.key, required this.type, required this.field, required this.value, required this.noun});

  /// Operation type and the payload field that identifies it, e.g. `customer.payment` / `receipt_number`.
  final String type;
  final String field;
  final String value;

  /// What it is, in the user's words: "este abono", "este cobro".
  final String noun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = (ref.watch(outboxRowsProvider).value ?? const <OutboxData>[])
        .where((row) => row.type == type && (jsonDecode(row.payload) as Map)[field]?.toString() == value)
        .lastOrNull;
    if (row == null) return const SizedBox.shrink();
    final sending = ref.watch(syncProvider.select((status) => status.running));

    final (icon, color, text) = switch (row.status) {
      OutboxStatus.done => (Icons.check_circle, AppColors.brand, 'Aceptado por el servidor.'),
      OutboxStatus.rejected => (
        Icons.cancel,
        AppColors.danger,
        'El servidor rechazó $noun: ${row.message ?? 'sin motivo'}. No entregues este comprobante; revísalo en Actividad.',
      ),
      _ => (Icons.schedule, AppColors.amber, sending ? 'Enviando al servidor…' : 'Guardado en el teléfono. Se enviará en cuanto haya señal.'),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
