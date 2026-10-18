import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/formatting.dart';
import '../application/supervision_providers.dart';
import '../data/supervision_models.dart';

/// The supervisor's home: today's money, what waits for them, and the runs on the road.
class SupervisorDashboard extends ConsumerWidget {
  const SupervisorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(managementPanelProvider);

    return panel.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator())),
      error: (error, _) => Card(
        child: ListTile(
          leading: const Icon(Icons.wifi_off, color: AppColors.muted),
          title: const Text('El panel necesita señal'),
          subtitle: Text('$error'),
          trailing: IconButton(tooltip: 'Reintentar', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(managementPanelProvider)),
        ),
      ),
      data: (panel) {
        final toSettle = panel.pending['runs_awaiting_settlement'] ?? 0;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Hoy', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
            IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(managementPanelProvider)),
          ]),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              _Figure(label: 'Vendido', value: money(panel.sold), color: AppColors.ink),
              _Figure(label: 'Cobrado', value: money(panel.collected), color: AppColors.brand),
              _Figure(label: 'Fiado hoy', value: money(panel.credit), color: AppColors.amber),
              _Figure(label: 'Cartera vencida · ${panel.overdueCustomers} clientes', value: money(panel.overdue), color: AppColors.danger),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => context.push('/settlements'),
                icon: const Icon(Icons.point_of_sale_outlined),
                label: Text(toSettle == 0 ? 'Liquidar' : 'Liquidar ($toSettle)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/field'), icon: const Icon(Icons.map_outlined), label: const Text('Campo'))),
          ]),
          if ((panel.pending['stock_shortages'] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${panel.pending['stock_shortages']} productos con faltante en bodega.', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ),
          if (panel.runs.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Jornadas', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            for (final run in panel.runs.take(5)) RunProgressTile(run: run),
          ],
        ]);
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color))),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      ]),
    ),
  );
}

/// A run with its stops done; one waiting for settlement opens its settlement.
class RunProgressTile extends StatelessWidget {
  const RunProgressTile({super.key, required this.run});

  final RunProgress run;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text('${run.runNumber} · ${run.driverName}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${run.statusLabel} · ${run.completedStops} de ${run.stops} paradas · entregado ${money(run.delivered)}'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: run.progress, minHeight: 5, borderRadius: BorderRadius.circular(3)),
      ]),
      trailing: Icon(run.awaitsSettlement ? Icons.point_of_sale_outlined : Icons.chevron_right, color: AppColors.brand),
      // Back from the road it is settled; on the road its stops can be reviewed and fixed.
      onTap: () => context.push(run.awaitsSettlement ? '/settlements/${run.id}' : '/runs/${run.id}/review'),
    ),
  );
}
