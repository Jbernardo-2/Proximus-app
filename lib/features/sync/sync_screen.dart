import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/database.dart';
import '../../sync/operation_view.dart';
import '../preventa/documents/payment_receipt.dart';
import '../preventa/presentation/receipt_screen.dart';
import 'sync_format.dart';
import 'sync_summary_card.dart';

const _resourceLabels = {
  'products': 'Productos',
  'stocks': 'Existencias',
  'routes': 'Rutas',
  'customers': 'Clientes',
  'route_activity': 'Ruta del día',
  'recent_orders': 'Pedidos recientes',
  'customer_credit': 'Crédito de clientes',
  'receivables': 'Deudas abiertas',
  'delivery_runs': 'Jornadas de reparto',
};

final _time = DateFormat('dd/MM HH:mm');

/// What the phone recorded and where each thing stands: rejected first, then
/// waiting to be sent, then what the server accepted in the last days.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operations = ref.watch(operationViewsProvider);
    final rejected = operations.where((op) => op.state == OperationState.rejected).toList();
    final pending = operations.where((op) => op.state != OperationState.rejected && op.state != OperationState.accepted).toList();
    final accepted = operations.where((op) => op.state == OperationState.accepted).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ClockWarning(),
          const SyncSummaryCard(),
          const SizedBox(height: 24),
          if (rejected.isNotEmpty)
            _Section(
              title: 'Rechazadas · ${rejected.length}',
              color: AppColors.danger,
              child: Column(children: [for (final op in rejected) _OperationTile(view: op)]),
            ),
          _Section(
            title: 'Por enviar',
            child: pending.isEmpty ? const _Empty('Nada pendiente.') : Column(children: [for (final op in pending) _OperationTile(view: op)]),
          ),
          _Section(
            title: 'Aceptadas (últimos 7 días)',
            child: accepted.isEmpty ? const _Empty('Todavía nada.') : Column(children: [for (final op in accepted.take(30)) _OperationTile(view: op)]),
          ),
          const _Section(title: 'Datos en el teléfono', child: _StoredData()),
          const _Section(title: 'Este teléfono', child: _PhoneInfo()),
        ],
      ),
    );
  }
}

/// Visits and receipts carry the phone time, so a wrong clock must be fixed.
class ClockWarning extends ConsumerWidget {
  const ClockWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(clockOffsetProvider);
    if (offset == null || offset.abs() < 300) return const SizedBox.shrink();
    final minutes = (offset.abs() / 60).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF5D08A))),
      child: Text(
        'La hora del teléfono está ${offset > 0 ? 'atrasada' : 'adelantada'} $minutes min. Corrígela en Ajustes → Fecha y hora (automática), porque las visitas y comprobantes llevan esa hora.',
        style: const TextStyle(color: Color(0xFF8A5A00)),
      ),
    );
  }
}

class _OperationTile extends StatelessWidget {
  const _OperationTile({required this.view});

  final OperationView view;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (view.state) {
      OperationState.rejected => (Icons.error_outline, AppColors.danger),
      OperationState.accepted => (Icons.check_circle_outline, AppColors.brand),
      OperationState.sending => (Icons.sync, AppColors.brand),
      OperationState.retrying => (Icons.replay, AppColors.amber),
      OperationState.waitingSignal => (Icons.signal_wifi_off, AppColors.amber),
      OperationState.saved => (Icons.schedule, AppColors.amber),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text('${view.title}${view.customer.isEmpty ? '' : ' · ${view.customer}'}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [view.state.label, if (view.serverNumber != null) view.serverNumber!, _time.format(view.row.createdAt)].join(' · '),
        style: TextStyle(color: view.state == OperationState.rejected ? AppColors.danger : AppColors.muted),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => OperationSheet(view: view)),
    );
  }
}

/// Everything about one operation, with what can be done about it.
class OperationSheet extends ConsumerWidget {
  const OperationSheet({super.key, required this.view});

  final OperationView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outbox = ref.read(outboxProvider);
    final rejected = view.state == OperationState.rejected;
    final receipt = view.receipt;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(view.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (view.customer.isNotEmpty) Text(view.customer, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 8),
          Text(
            '${view.state.label}${view.serverNumber == null ? '' : ' · ${view.serverNumber}'}',
            style: TextStyle(fontWeight: FontWeight.w700, color: rejected ? AppColors.danger : AppColors.ink),
          ),
          Text('Registrado ${_time.format(view.row.createdAt)}${view.row.attempts > 0 ? ' · ${view.row.attempts} intentos' : ''}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const Divider(height: 24),
          for (final (label, value) in view.details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))), Flexible(child: Text(value, textAlign: TextAlign.right))]),
            ),
          if (rejected) ...[
            const Divider(height: 24),
            const Text('Motivo del servidor', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(view.row.message ?? 'Sin detalle.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF4ED), borderRadius: BorderRadius.circular(12)),
              child: Text(view.recommendation ?? '', style: const TextStyle(color: AppColors.danger)),
            ),
          ] else if (view.state != OperationState.accepted && view.row.message != null) ...[
            const Divider(height: 24),
            Text(view.row.message!, style: const TextStyle(color: AppColors.amber)),
          ],
          const SizedBox(height: 16),
          if (receipt != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(receipt: PaymentReceipt.fromJson(receipt)))),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Ver o reimprimir comprobante'),
            ),
          if (view.customerId != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/customer/${view.customerId}');
              },
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Abrir cliente'),
            ),
          ],
          if (rejected) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await outbox.retry(view.row.id);
                ref.read(syncProvider.notifier).sync(pushOnly: true);
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.replay),
              label: const Text('Reintentar'),
            ),
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('¿Descartar esta operación?'),
                    content: Text(
                      view.customerHoldsReceipt
                          ? 'El cliente tiene un comprobante impreso de este abono. Descártalo solo después de avisar al supervisor.'
                          : 'Se borrará del teléfono y no se enviará.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar')),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await outbox.dismiss(view.row.id);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Descartar', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _StoredData extends ConsumerWidget {
  const _StoredData();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<SyncRecord>>(
      stream: db.select(db.syncRecords).watch(),
      builder: (context, snapshot) {
        final counts = <String, int>{};
        for (final record in snapshot.data ?? const <SyncRecord>[]) {
          counts[record.resource] = (counts[record.resource] ?? 0) + 1;
        }
        if (counts.isEmpty) return const _Empty('Aún no se ha descargado nada.');
        return Column(children: [for (final entry in counts.entries) _ResourceRow(resource: entry.key, count: entry.value)]);
      },
    );
  }
}

class _PhoneInfo extends ConsumerWidget {
  const _PhoneInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final session = ref.watch(sessionProvider).value;
    if (session == null) return const SizedBox.shrink();
    return StreamBuilder<List<DocumentSeriesRow>>(
      stream: db.select(db.documentSeries).watch(),
      builder: (context, snapshot) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Código ${session.deviceCode} · servidor ${session.serverUrl}', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        for (final series in snapshot.data ?? const <DocumentSeriesRow>[])
          Text('Último ${series.prefix}${series.lastNumber.toString().padLeft(6, '0')}', style: const TextStyle(fontFamily: 'monospace')),
      ]),
    );
  }
}

class _ResourceRow extends ConsumerWidget {
  const _ResourceRow({required this.resource, required this.count});

  final String resource;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pulledAt = ref.watch(syncStateProvider('pulled_at:$resource')).value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(_resourceLabels[resource] ?? resource)),
        Text('$count', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: Text(relativeTime(pulledAt == null ? null : DateTime.tryParse(pulledAt)), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.color});

  final String title;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color ?? AppColors.ink)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: child)),
          ),
        ]),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(color: AppColors.muted)),
      );
}
