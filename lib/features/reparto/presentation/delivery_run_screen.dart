import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/external_apps.dart';
import '../../../core/formatting.dart';
import '../../preventa/data/preventa_models.dart' show LocalOperationState;
import '../../preventa/presentation/daily_route_screen.dart' show StatusChip;
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';
import '../data/delivery_repository.dart';
import 'run_closing_screen.dart' show openRunClosing;
import 'run_debts_screen.dart' show runDebtsProvider;

final _day = DateFormat("EEEE d 'de' MMMM", 'es');

String _dayLabel(DateTime? date) => date == null ? '' : toBeginningOfSentenceCase(_day.format(date));

/// The driver's work. Only runs that still need them show: with one, it opens
/// straight away; with several, a short list to pick from, today's first.
class DeliveryRunScreen extends ConsumerWidget {
  const DeliveryRunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(deliveryRunsProvider);

    return runs.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Mi jornada')),
        body: _Message(icon: Icons.sync_problem, title: 'No se pudo leer la jornada guardada', detail: error.toString()),
      ),
      data: (runs) {
        final toWork = runsToWork(runs);
        final finished = [
          for (final run in runs)
            if (!run.needsDriver) run,
        ];
        if (toWork.length == 1) return _RunScaffold(run: toWork.single, finished: finished);

        return Scaffold(
          appBar: AppBar(title: const Text('Mi jornada'), actions: const [_SyncButton()]),
          body: RefreshIndicator(
            onRefresh: () => ref.read(syncProvider.notifier).sync(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (toWork.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: _Message(icon: Icons.local_shipping_outlined, title: 'No tienes jornadas por entregar', detail: 'Cuando la bodega cargue tu camión, desliza hacia abajo para sincronizar.'),
                  )
                else ...[
                  Text('Tienes ${toWork.length} jornadas sin terminar', style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 8),
                  for (final run in toWork) _RunTile(run: run),
                ],
                if (finished.isNotEmpty) _SettlementNote(runs: finished),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One run opened from the list.
class DeliveryRunDetailScreen extends ConsumerWidget {
  const DeliveryRunDetailScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(deliveryRunProvider(runId));
    if (run == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Jornada')),
        body: const _Message(icon: Icons.local_shipping_outlined, title: 'Esta jornada ya no está en el teléfono', detail: 'Puede que el supervisor ya la haya liquidado.'),
      );
    }
    return _RunScaffold(run: run, title: 'Jornada ${run.runNumber}');
  }
}

class _RunScaffold extends ConsumerWidget {
  const _RunScaffold({required this.run, this.title = 'Mi jornada', this.finished = const []});

  final LocalDeliveryRun run;
  final String title;

  /// Runs already finished, waiting for the supervisor: only their closing is left to see.
  final List<LocalDeliveryRun> finished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = run.pendingStops;
    final runDebts = ref.watch(runDebtsProvider(run.id));
    final debts = {for (final debt in runDebts) debt.customerId: debt.outstanding};
    final debtTotal = runDebts.fold(DecimalValue.zero, (sum, debt) => sum + debt.outstanding);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [_SyncButton()]),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncProvider.notifier).sync(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _RunSummary(run: run),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => context.push('/deliveries/${run.id}/load'),
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Carga del camión')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: runDebts.isEmpty ? null : AppColors.danger,
                      side: runDebts.isEmpty ? null : const BorderSide(color: AppColors.danger),
                    ),
                    onPressed: runDebts.isEmpty ? null : () => context.push('/deliveries/${run.id}/debts'),
                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(runDebts.isEmpty ? 'Sin saldos' : 'Saldos (${runDebts.length}) · ${money(debtTotal)}')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!run.hasLeft) ...[_DepartButton(run: run), const SizedBox(height: 16)],
            if (pending.isEmpty) ...[
              const _Message(icon: Icons.emoji_events_outlined, title: 'Terminaste todas las paradas', detail: 'Entrega el efectivo y la mercadería devuelta al supervisor.'),
              FilledButton.icon(onPressed: () => openRunClosing(context, run), icon: const Icon(Icons.summarize_outlined), label: const Text('Ver cierre de jornada')),
            ] else ...[
              if (run.hasLeft) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(onPressed: () => openRunClosing(context, run), icon: const Icon(Icons.summarize_outlined, size: 18), label: const Text('Cierre preliminar')),
                ),
              ],
              Text(run.hasLeft ? 'Por entregar (${pending.length})' : 'Paradas (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final stop in pending) DeliveryStopCard(stop: stop, debt: debts[stop.customerId], onTap: () => context.push('/deliveries/${run.id}/stops/${stop.id}')),
            ],
            if (finished.isNotEmpty) _SettlementNote(runs: finished),
          ],
        ),
      ),
    );
  }
}

class _SyncButton extends ConsumerWidget {
  const _SyncButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(syncProvider.select((status) => status.running));
    return IconButton(
      tooltip: 'Sincronizar',
      onPressed: running ? null : () => ref.read(syncProvider.notifier).sync(),
      icon: running ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
    );
  }
}

/// A run in the list: enough to recognise it and see what is left.
class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});

  final LocalDeliveryRun run;

  @override
  Widget build(BuildContext context) {
    final pending = run.pendingStops.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/deliveries/${run.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Jornada ${run.runNumber}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(_dayLabel(run.scheduledDate), style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(text: run.statusLabel, color: run.hasLeft ? AppColors.brand : AppColors.amber),
                        Text(run.hasLeft ? 'Faltan $pending de ${run.stops.length} paradas' : '${run.stops.length} paradas', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Finished runs leave the screen; only a quiet line stays, to reach their closing.
class _SettlementNote extends StatelessWidget {
  const _SettlementNote({required this.runs});

  final List<LocalDeliveryRun> runs;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      children: [
        Text(
          runs.length == 1 ? '1 jornada terminada espera la liquidación del supervisor.' : '${runs.length} jornadas terminadas esperan la liquidación del supervisor.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        for (final run in runs) TextButton(onPressed: () => openRunClosing(context, run), child: Text('Ver cierre de ${run.runNumber}')),
      ],
    ),
  );
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({required this.run});

  final LocalDeliveryRun run;

  @override
  Widget build(BuildContext context) {
    final shortStops = run.stops.where((stop) => stop.hasShortItems).length;
    final done = run.doneStops.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(run.runNumber, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text([_dayLabel(run.scheduledDate), if (run.vehicleCode != null) 'Camión ${run.vehicleCode}'].where((part) => part.isNotEmpty).join(' · '), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            StatusChip(text: run.statusLabel, color: run.hasLeft ? AppColors.brand : AppColors.amber, outlined: run.departurePending),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: run.progress, minHeight: 8),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('$done de ${run.stops.length} entregas terminadas', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (done > 0)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => context.push('/deliveries/${run.id}/done'),
                    child: const Text('Ver'),
                  ),
              ],
            ),
            if (run.hasLeft) Text('Cobrado ${money(run.collectedTotal)} de ${money(run.loadedTotal)}', style: const TextStyle(color: AppColors.muted)),
            if (run.departurePending) const _Note('Salida guardada en el teléfono; se enviará cuando haya señal.', AppColors.amber),
            if (run.departureRejection != null) _Note(run.departureRejection!, AppColors.danger),
            if (!run.hasLeft && shortStops > 0)
              _Note(
                shortStops == 1 ? 'A 1 parada le falta mercadería: la bodega cargó menos de lo pedido.' : 'A $shortStops paradas les falta mercadería: la bodega cargó menos de lo pedido.',
                AppColors.amber,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: TextStyle(fontSize: 12, color: color)),
  );
}

class _DepartButton extends ConsumerStatefulWidget {
  const _DepartButton({required this.run});

  final LocalDeliveryRun run;

  @override
  ConsumerState<_DepartButton> createState() => _DepartButtonState();
}

class _DepartButtonState extends ConsumerState<_DepartButton> {
  bool _saving = false;

  Future<void> _depart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir a ruta?'),
        content: Text('Confirma que el camión ya está cargado con las ${widget.run.stops.length} paradas y sale de la bodega. Funciona sin señal.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Todavía no')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(deliveryActionsProvider).depart(widget.run, location: ref.read(locationServiceProvider).start());
    } catch (error, stack) {
      debugPrint('No se pudo registrar la salida: $error\n$stack');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo registrar la salida: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
    onPressed: _saving ? null : _depart,
    icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.local_shipping),
    label: const Text('Salir a ruta'),
  );
}

/// A stop of the run in a list: who, what goes, how it is paid and anything to watch for.
class DeliveryStopCard extends StatelessWidget {
  const DeliveryStopCard({super.key, required this.stop, this.onTap, this.debt});

  final LocalDeliveryStop stop;
  final VoidCallback? onTap;

  /// Old debt of the customer, to collect while there.
  final DecimalValue? debt;

  @override
  Widget build(BuildContext context) {
    final customer = stop.customer;
    final phone = customer?.phone ?? customer?.whatsapp;
    final whatsapp = customer?.whatsapp ?? customer?.phone;
    final chips = [
      if (stop.progress == StopProgress.awaitingPayment) const StatusChip(text: 'Falta cobrar', color: AppColors.amber),
      if (stop.progress == StopProgress.done) StatusChip(text: stop.statusLabel.isEmpty ? 'Terminada' : stop.statusLabel, color: AppColors.brand),
      if (stop.isCredit) const StatusChip(text: 'Crédito', color: Color(0xFF2F6FD0), outlined: true),
      if (debt != null) StatusChip(text: 'Debe ${money(debt!)}', color: AppColors.danger, outlined: true),
      if (stop.hasShortItems && stop.progress == StopProgress.pending) const StatusChip(text: 'Carga incompleta', color: AppColors.amber, outlined: true),
      if (stop.operationState == LocalOperationState.pending) const StatusChip(text: 'Por enviar', color: AppColors.amber, outlined: true),
      if (stop.operationState == LocalOperationState.rejected) const StatusChip(text: 'Rechazado', color: AppColors.danger, outlined: true),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: const Color(0xFFF1F1EF),
                    child: Text(
                      '${stop.visitOrder}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stop.customerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(
                          stop.customerAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 4),
                        Text('${stop.items.length} ${stop.items.length == 1 ? 'producto' : 'productos'} · ${money(stop.loadedTotal)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 42),
                  child: Wrap(spacing: 6, runSpacing: 6, children: chips),
                ),
              ],
              if (stop.rejectionMessage != null)
                Padding(
                  padding: const EdgeInsets.only(left: 42, top: 6),
                  child: Text(stop.rejectionMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Row(
                  children: [
                    if (phone != null) IconButton(tooltip: 'Llamar', icon: const Icon(Icons.call_outlined), onPressed: () => _open(context, ExternalApps.call(phone))),
                    if (whatsapp != null) IconButton(tooltip: 'WhatsApp', icon: const Icon(Icons.chat_outlined), onPressed: () => _open(context, ExternalApps.whatsapp(whatsapp))),
                    IconButton(
                      tooltip: 'Abrir ubicación',
                      icon: const Icon(Icons.place_outlined),
                      onPressed: () => _open(
                        context,
                        ExternalApps.map(
                          latitude: customer?.latitude,
                          longitude: customer?.longitude,
                          label: customer?.hasLocation ?? false ? stop.customerName : '${stop.customerAddress} ${stop.customerName}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Future<bool> opening) async {
    if (!await opening && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay una app instalada para abrir esto.')));
    }
  }
}

/// Stops already finished, with whether the server has what was recorded.
class DoneStopsScreen extends ConsumerWidget {
  const DoneStopsScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(deliveryRunProvider(runId));
    final done = run?.doneStops ?? const <LocalDeliveryStop>[];
    return Scaffold(
      appBar: AppBar(title: Text('Entregas terminadas (${done.length})')),
      body: done.isEmpty
          ? const Center(
              child: Text('Todavía no terminas ninguna parada.', style: TextStyle(color: AppColors.muted)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [for (final stop in done) DeliveryStopCard(stop: stop, onTap: () => context.push('/deliveries/$runId/stops/${stop.id}'))],
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}
