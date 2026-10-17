import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/warehouse_run_actions.dart';
import '../data/warehouse_runs.dart';
import 'online.dart';
import 'pick_view.dart';

/// One run, by stage: assemble its orders, pick them, and confirm the load. Read live.
class WarehouseRunScreen extends ConsumerWidget {
  const WarehouseRunScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(warehouseRunProvider(runId));
    final run = value.value;
    final session = ref.watch(sessionProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(run?.runNumber ?? 'Jornada')),
      body: value.isLoading && run == null
          ? const Center(child: CircularProgressIndicator())
          : value.hasError && run == null
          ? LiveError(error: value.error!, onRetry: () => ref.read(warehouseRunActionsProvider).refresh())
          : run == null
          ? const Center(child: Text('Esta jornada ya salió o se canceló.', style: TextStyle(color: AppColors.muted)))
          : Column(children: [
              _Header(run: run),
              if (value.isLoading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: switch (run.status) {
                  'draft' => _Assemble(run: run),
                  'preparing' when session != null && run.preparableBy(session.userId, supervises: session.role != 'bodeguero') => PickView(run: run),
                  'preparing' => const _Message('Otro bodeguero está preparando esta jornada. Solo él o un supervisor pueden continuarla.'),
                  _ => _Loaded(run: run),
                },
              ),
            ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.run});

  final WarehouseRun run;

  @override
  Widget build(BuildContext context) {
    final stage = {'draft': 'Armando', 'preparing': 'Preparando', 'loaded': 'Lista para salir'}[run.status] ?? run.status;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(run.driverName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              [if (run.vehicle != null) run.vehicle!, if (run.scheduledDate != null) DateFormat("EEEE d 'de' MMMM", 'es').format(run.scheduledDate!)].join(' · '),
              style: const TextStyle(color: AppColors.muted),
            ),
          ]),
        ),
        Text(stage, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted))));
}

/// A full-width button at the bottom of a stage.
class BottomAction extends StatelessWidget {
  const BottomAction({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: SizedBox(width: double.infinity, height: 52, child: child)),
  );
}

/// Draft: which orders go on the truck.
class _Assemble extends ConsumerStatefulWidget {
  const _Assemble({required this.run});

  final WarehouseRun run;

  @override
  ConsumerState<_Assemble> createState() => _AssembleState();
}

class _AssembleState extends ConsumerState<_Assemble> {
  bool _busy = false;

  Future<void> _do(Future<void> Function() action) async {
    setState(() => _busy = true);
    await runOnline(context, action);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final actions = ref.read(warehouseRunActionsProvider);
    final total = run.orders.fold(DecimalValue.zero, (sum, order) => sum + order.total);
    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async => actions.refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Row(children: [
                Expanded(child: Text('${run.orders.length} ${run.orders.length == 1 ? 'pedido' : 'pedidos'} · ${money(total)}', style: const TextStyle(fontWeight: FontWeight.w700))),
                TextButton.icon(onPressed: () => context.push('/warehouse-runs/${run.id}/orders'), icon: const Icon(Icons.add), label: const Text('Agregar pedidos')),
              ]),
              if (run.orders.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Text('Agrega los pedidos que van en esta jornada.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))),
              for (final order in run.orders)
                Card(
                  child: ListTile(
                    title: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([order.orderNumber, if (order.routeName != null) order.routeName!, '${order.lines.length} líneas'].join(' · ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(money(order.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                      IconButton(
                        tooltip: 'Quitar',
                        icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                        onPressed: _busy ? null : () => _do(() => actions.unassign(run, order)),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
      BottomAction(
        child: FilledButton.icon(
          onPressed: run.orders.isEmpty || _busy ? null : () => _do(() => actions.startPreparation(run)),
          icon: const Icon(Icons.inventory_outlined),
          label: Text(_busy ? 'Guardando…' : 'Iniciar preparación'),
        ),
      ),
    ]);
  }
}

/// Loaded: what went on the truck, waiting for the driver to leave.
class _Loaded extends StatelessWidget {
  const _Loaded({required this.run});

  final WarehouseRun run;

  @override
  Widget build(BuildContext context) {
    final groups = pickGroups(run);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const Text('Cargada. El repartidor ya puede iniciar ruta.', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        for (final group in groups)
          Card(
            child: ListTile(
              leading: ProductImage(productId: group.productId, size: 40),
              title: Text(group.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(group.presentationName),
              trailing: Text('${group.prepared ?? group.requested}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
  }
}
