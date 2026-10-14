import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/database.dart';
import 'sync_format.dart';
import 'sync_summary_card.dart';

const _resourceLabels = {
  'products': 'Productos',
  'stocks': 'Existencias',
  'routes': 'Rutas',
  'customers': 'Clientes',
  'customer_credit': 'Crédito de clientes',
  'receivables': 'Deudas abiertas',
  'delivery_runs': 'Jornadas de reparto',
};

const _operationLabels = {
  'order.create': 'Pedido',
  'visit.no_sale': 'Visita sin pedido',
  'delivery.outcome': 'Resultado de entrega',
  'delivery.payment': 'Cobro de entrega',
  'customer.payment': 'Abono',
};

/// What the phone has stored, what is waiting to be sent and what the server rejected.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final session = ref.watch(sessionProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SyncSummaryCard(),
          const SizedBox(height: 24),
          _Section(
            title: 'Rechazadas',
            child: StreamBuilder<List<OutboxData>>(
              stream: ref.watch(outboxProvider).watch(status: OutboxStatus.rejected),
              builder: (context, snapshot) {
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) return const _Empty('Ninguna. Todo lo enviado fue aceptado.');
                return Column(children: [
                  for (final row in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.error_outline, color: AppColors.danger),
                      title: Text('${_operationLabels[row.type] ?? row.type}${row.summary.isEmpty ? '' : ' · ${row.summary}'}'),
                      subtitle: Text(row.message ?? ''),
                      trailing: IconButton(
                        tooltip: 'Descartar',
                        icon: const Icon(Icons.close),
                        onPressed: () => ref.read(outboxProvider).dismiss(row.id),
                      ),
                    ),
                ]);
              },
            ),
          ),
          _Section(
            title: 'Por enviar',
            child: StreamBuilder<List<OutboxData>>(
              stream: ref.watch(outboxProvider).watch(status: OutboxStatus.pending),
              builder: (context, snapshot) {
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) return const _Empty('Nada pendiente.');
                return Column(children: [
                  for (final row in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule, color: AppColors.amber),
                      title: Text('${_operationLabels[row.type] ?? row.type}${row.summary.isEmpty ? '' : ' · ${row.summary}'}'),
                      subtitle: Text(row.attempts > 0 ? '${row.message ?? ''} · intento ${row.attempts}' : 'Registrado ${relativeTime(row.createdAt)}'),
                    ),
                ]);
              },
            ),
          ),
          _Section(
            title: 'Datos en el teléfono',
            child: StreamBuilder<List<SyncRecord>>(
              stream: db.select(db.syncRecords).watch(),
              builder: (context, snapshot) {
                final counts = <String, int>{};
                for (final record in snapshot.data ?? const <SyncRecord>[]) {
                  counts[record.resource] = (counts[record.resource] ?? 0) + 1;
                }
                if (counts.isEmpty) return const _Empty('Aún no se ha descargado nada.');
                return Column(children: [
                  for (final entry in counts.entries)
                    _ResourceRow(resource: entry.key, count: entry.value),
                ]);
              },
            ),
          ),
          if (session != null)
            _Section(
              title: 'Este teléfono',
              child: StreamBuilder<List<DocumentSeriesRow>>(
                stream: db.select(db.documentSeries).watch(),
                builder: (context, snapshot) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Código ${session.deviceCode} · servidor ${session.serverUrl}', style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 8),
                    for (final series in snapshot.data ?? const <DocumentSeriesRow>[])
                      Text('Último ${series.prefix}${series.lastNumber.toString().padLeft(6, '0')}', style: const TextStyle(fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
        ],
      ),
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
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: child)),
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
