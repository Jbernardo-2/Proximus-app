import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../preventa/documents/payment_receipt.dart' show ReceiptFormat;
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';
import '../data/run_closing.dart';
import '../documents/run_closing_pdf.dart';

/// The driver's own count at the end of the run, to hand to the supervisor: the cash to
/// deliver leads, then how it was collected, the credit given and what comes back.
class RunClosingScreen extends ConsumerWidget {
  const RunClosingScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(deliveryRunProvider(runId));
    if (run == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cierre de jornada')),
        body: const Center(child: Text('Esta jornada ya no está en el teléfono.')),
      );
    }
    final closing = RunClosing.of(run, ref.watch(outboxRowsProvider).value ?? const []);
    final manifest = ref.watch(manifestProvider).value;
    final labels = {
      for (final option in [...?manifest?.options('payment_methods'), ...?manifest?.options('settlement_methods')]) option.value: option.label,
    };
    final driver = ref.watch(sessionProvider).value?.userName ?? '';

    Future<void> output(ReceiptFormat format, {bool share = false}) async {
      Future<Uint8List> pdf() => buildRunClosingPdf(run: run, closing: closing, driver: driver, methodLabels: labels, format: format);
      try {
        if (share) {
          await Printing.sharePdf(bytes: await pdf(), filename: 'cierre-${run.runNumber.toLowerCase()}.pdf');
        } else {
          await Printing.layoutPdf(name: 'Cierre ${run.runNumber}', format: format == ReceiptFormat.ticket ? PdfPageFormat.roll80 : PdfPageFormat.letter, onLayout: (_) => pdf());
        }
      } catch (error, stack) {
        debugPrint('No se pudo imprimir el cierre: $error\n$stack');
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo ${share ? 'compartir' : 'imprimir'}: $error')));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text('Cierre · ${run.runNumber}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (!closing.isFinal) _Warning(closing: closing, onOpenActivity: () => context.go('/sync')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Efectivo a entregar', style: TextStyle(color: AppColors.muted)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(money(closing.cash), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.1)),
                  ),
                  const SizedBox(height: 4),
                  Text('Total cobrado ${money(closing.collected)} · Crédito ${money(closing.credit)}', style: const TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Cobrado por forma de pago',
            children: [
              if (closing.byMethod.isEmpty) const _Line(label: 'Sin cobros todavía', value: ''),
              for (final entry in closing.byMethod.entries) _Line(label: labels[entry.key] ?? entry.key, value: money(entry.value)),
              if (closing.accountPaymentCount > 0)
                _Line(
                  label: 'Incluye ${closing.accountPaymentCount} ${closing.accountPaymentCount == 1 ? 'abono' : 'abonos'} a cuenta',
                  value: money(closing.accountPayments.values.fold(DecimalValue.zero, (sum, amount) => sum + amount)),
                  muted: true,
                ),
            ],
          ),
          _Section(
            title: 'Paradas (${run.stops.length})',
            children: [
              _Line(label: 'Entregadas', value: '${closing.delivered}'),
              _Line(label: 'Entrega parcial', value: '${closing.partial}'),
              _Line(label: 'No entregadas', value: '${closing.notDelivered}'),
              if (closing.open > 0) _Line(label: 'Sin terminar', value: '${closing.open}', warn: true),
            ],
          ),
          if (closing.returns.isNotEmpty)
            _Section(
              title: 'Mercadería que regresa a bodega',
              children: [
                for (final item in closing.returns)
                  _Line(
                    label: '${item.product} · ${item.presentation}',
                    value: [if (!item.returned.isZero) 'Dev. ${item.returned}', if (!item.damaged.isZero) 'Dañ. ${item.damaged}', if (!item.missing.isZero) 'Faltó ${item.missing}'].join(' · '),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: () => output(ReceiptFormat.ticket), icon: const Icon(Icons.receipt_long), label: const Text('Imprimir ticket 80 mm')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => output(ReceiptFormat.letter),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Imprimir carta'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => output(ReceiptFormat.letter, share: true),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Compartir'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Es tu conteo de la jornada. El supervisor hace la liquidación en la web.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.closing, required this.onOpenActivity});

  final RunClosing closing;
  final VoidCallback onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final reasons = [
      if (closing.open > 0) closing.open == 1 ? '1 parada sin terminar' : '${closing.open} paradas sin terminar',
      if (closing.unsent > 0) closing.unsent == 1 ? '1 operación sin enviar' : '${closing.unsent} operaciones sin enviar',
      if (closing.rejected > 0) closing.rejected == 1 ? '1 operación rechazada' : '${closing.rejected} operaciones rechazadas',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cierre preliminar: ${reasons.join(', ')}.',
            style: const TextStyle(color: Color(0xFF8A5A00), fontWeight: FontWeight.w600),
          ),
          if (closing.unsent > 0 || closing.rejected > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onOpenActivity, child: const Text('Ver en Actividad')),
            ),
          if (closing.unsent == 0 && closing.rejected == 0) const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(children: children),
          ),
        ),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.muted = false, this.warn = false});

  final String label;
  final String value;
  final bool muted;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final color = warn ? AppColors.amber : (muted ? AppColors.muted : AppColors.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: color)),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Opens the closing of a run.
void openRunClosing(BuildContext context, LocalDeliveryRun run) => context.push('/deliveries/${run.id}/closing');
