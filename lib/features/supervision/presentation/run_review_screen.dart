import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/formatting.dart';
import '../../bodega/application/warehouse_run_actions.dart';
import '../../bodega/presentation/online.dart';
import '../application/supervision_providers.dart';
import '../data/supervision_models.dart';

/// Each stop of a run with what the driver recorded, to fix before settling: a wrong
/// payment is voided, and a stop recorded wrong goes back to the driver.
class RunReviewScreen extends ConsumerWidget {
  const RunReviewScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(runRecordProvider(runId));
    final run = value.value;

    return Scaffold(
      appBar: AppBar(title: Text(run?['run_number']?.toString() ?? 'Paradas')),
      body: run == null
          ? value.isLoading
                ? const Center(child: CircularProgressIndicator())
                : value.hasError
                ? LiveError(error: value.error!, onRetry: () => ref.invalidate(liveResourceProvider('delivery_runs')))
                : const Center(child: Text('Esta jornada ya se liquidó o se canceló.', style: TextStyle(color: AppColors.muted)))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(liveResourceProvider('delivery_runs')),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('${run['driver_name'] ?? ''} · ${run['status_label'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Text('Anula un cobro equivocado. Para corregir lo entregado, reabre la parada: vuelve al repartidor y él la registra de nuevo.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                for (final stop in stopReviews(run)) _StopCard(runId: runId, stop: stop),
              ]),
            ),
    );
  }
}

class _StopCard extends ConsumerStatefulWidget {
  const _StopCard({required this.runId, required this.stop});

  final String runId;
  final StopReview stop;

  @override
  ConsumerState<_StopCard> createState() => _StopCardState();
}

class _StopCardState extends ConsumerState<_StopCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final ok = await runOnline(context, action);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _void(StopPayment payment) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _ReasonDialog(payment: payment));
    if (reason == null) return;
    await _run(() => ref.read(runCorrectionsProvider).voidPayment(widget.runId, widget.stop.runOrderId, payment.id, reason), 'Cobro anulado.');
  }

  Future<void> _reopen() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reabrir parada ${widget.stop.visitOrder}'),
        content: Text('${widget.stop.customerName} vuelve a quedar pendiente en el teléfono del repartidor, que debe registrarla de nuevo. La jornada vuelve a "en ruta" hasta que la termine.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reabrir')),
        ],
      ),
    );
    if (confirmed == true) await _run(() => ref.read(runCorrectionsProvider).reopenStop(widget.runId, widget.stop.runOrderId), 'Parada reabierta: el repartidor la verá al sincronizar.');
  }

  @override
  Widget build(BuildContext context) {
    final stop = widget.stop;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 14, child: Text('${stop.visitOrder}', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stop.customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${stop.orderNumber} · ${stop.statusLabel}${stop.hasOutcome ? ' · entregado ${money(stop.delivered)}' : ''}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
            if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          for (final payment in stop.payments)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 38),
              title: Text(
                '${payment.methodLabel} ${money(payment.amount)}',
                style: TextStyle(fontWeight: FontWeight.w600, decoration: payment.isActive ? null : TextDecoration.lineThrough, color: payment.isActive ? AppColors.ink : AppColors.muted),
              ),
              subtitle: Text([?payment.receiptNumber, if (!payment.isActive) 'Anulado${payment.voidReason == null ? '' : ': ${payment.voidReason}'}'].join(' · ')),
              trailing: payment.isActive ? TextButton(onPressed: _busy ? null : () => _void(payment), child: const Text('Anular')) : null,
            ),
          if (stop.hasOutcome)
            Align(
              alignment: Alignment.centerRight,
              child: stop.canReopen
                  ? TextButton.icon(onPressed: _busy ? null : _reopen, icon: const Icon(Icons.undo), label: const Text('Reabrir parada'))
                  : const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Para reabrirla, anula primero su cobro.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
            ),
        ]),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.payment});

  final StopPayment payment;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Anular ${widget.payment.methodLabel.toLowerCase()} de ${money(widget.payment.amount)}'),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLength: 1000,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(labelText: 'Motivo *', hintText: 'Ejemplo: se registró dos veces'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _reason.text.trim().isEmpty ? null : () => Navigator.pop(context, _reason.text.trim()), child: const Text('Anular cobro')),
    ],
  );
}
