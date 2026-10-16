import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/external_apps.dart';
import '../../../core/formatting.dart';
import '../../preventa/data/preventa_models.dart' show LocalOperationState;
import '../../preventa/presentation/daily_route_screen.dart' show StatusChip;
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';

final _day = DateFormat("EEEE d 'de' MMMM", 'es');

/// The driver's day: the loaded run, leaving the warehouse and the stops still to do.
class DeliveryRunScreen extends ConsumerWidget {
  const DeliveryRunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(deliveryRunsProvider);
    final running = ref.watch(syncProvider.select((status) => status.running));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi jornada'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: running ? null : () => ref.read(syncProvider.notifier).sync(),
            icon: running ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
          ),
        ],
      ),
      body: runs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(icon: Icons.sync_problem, title: 'No se pudo leer la jornada guardada', detail: error.toString()),
        data: (runs) => RefreshIndicator(
          onRefresh: () => ref.read(syncProvider.notifier).sync(),
          child: runs.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 120),
                  _Message(
                    icon: Icons.local_shipping_outlined,
                    title: 'No tienes jornadas cargadas',
                    detail: 'Cuando la bodega cargue tu camión, desliza hacia abajo para sincronizar.',
                  ),
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final run in runs) ...[
                      _RunSummary(run: run),
                      const SizedBox(height: 12),
                      if (!run.hasLeft) ...[_DepartButton(run: run), const SizedBox(height: 12)],
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                        onPressed: run.doneStops.isEmpty ? null : () => context.push('/deliveries/${run.id}/done'),
                        icon: const Icon(Icons.task_alt),
                        label: Text('Entregas terminadas (${run.doneStops.length})'),
                      ),
                      const SizedBox(height: 16),
                      if (run.pendingStops.isEmpty)
                        const _Message(
                          icon: Icons.emoji_events_outlined,
                          title: 'Terminaste todas las paradas',
                          detail: 'Revisa en "Entregas terminadas" que todo quede confirmado y entrega el efectivo al supervisor.',
                        ),
                      for (final stop in run.pendingStops) DeliveryStopCard(stop: stop),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({required this.run});

  final LocalDeliveryRun run;

  @override
  Widget build(BuildContext context) {
    final shortStops = run.stops.where((stop) => stop.hasShortItems).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text('Jornada ${run.runNumber}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            StatusChip(
              text: run.statusLabel,
              color: run.hasLeft ? AppColors.brand : AppColors.amber,
              outlined: run.departurePending,
            ),
          ]),
          Text(
            [
              if (run.scheduledDate != null) toBeginningOfSentenceCase(_day.format(run.scheduledDate!)),
              if (run.vehicleCode != null) 'Camión ${run.vehicleCode}${run.licensePlate == null ? '' : ' (${run.licensePlate})'}',
            ].join(' · '),
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: run.progress, minHeight: 8))),
            const SizedBox(width: 12),
            Text('${run.doneStops.length}/${run.stops.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _Figure(label: 'Paradas', value: '${run.stops.length}'),
            _Figure(label: 'Carga', value: money(run.loadedTotal)),
            _Figure(label: 'Cobrado', value: money(run.collectedTotal), color: AppColors.brand),
          ]),
          if (run.departurePending) ...[
            const SizedBox(height: 10),
            const Text('Salida guardada en el teléfono; se enviará cuando haya señal.', style: TextStyle(fontSize: 12, color: AppColors.amber)),
          ],
          if (run.departureRejection != null) ...[
            const SizedBox(height: 10),
            Text(run.departureRejection!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ],
          if (!run.hasLeft && shortStops > 0) ...[
            const SizedBox(height: 10),
            Text(
              shortStops == 1 ? 'A 1 parada le falta mercadería: la bodega cargó menos de lo pedido.' : 'A $shortStops paradas les falta mercadería: la bodega cargó menos de lo pedido.',
              style: const TextStyle(fontSize: 12, color: AppColors.amber),
            ),
          ],
        ]),
      ),
    );
  }
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

/// A stop of the run in a list: who, what goes, how it is paid and how it stands.
class DeliveryStopCard extends StatelessWidget {
  const DeliveryStopCard({super.key, required this.stop});

  final LocalDeliveryStop stop;

  @override
  Widget build(BuildContext context) {
    final customer = stop.customer;
    final phone = customer?.phone ?? customer?.whatsapp;
    final whatsapp = customer?.whatsapp ?? customer?.phone;
    final (label, color) = switch (stop.progress) {
      StopProgress.awaitingPayment => ('Falta cobrar', AppColors.amber),
      StopProgress.done => (stop.statusLabel.isEmpty ? 'Terminada' : stop.statusLabel, AppColors.brand),
      StopProgress.pending => ('Pendiente', AppColors.muted),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFF1F1EF),
              child: Text('${stop.visitOrder}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stop.customerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(stop.customerAddress, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            StatusChip(text: label, color: color),
            StatusChip(text: stop.isCredit ? 'Crédito' : 'Contado', color: stop.isCredit ? const Color(0xFF2F6FD0) : AppColors.ink, outlined: true),
            if (stop.hasShortItems) const StatusChip(text: 'Carga incompleta', color: AppColors.amber, outlined: true),
            if (stop.operationState == LocalOperationState.pending) const StatusChip(text: 'Por enviar', color: AppColors.amber, outlined: true),
            if (stop.operationState == LocalOperationState.rejected) const StatusChip(text: 'Rechazado', color: AppColors.danger, outlined: true),
          ]),
          const SizedBox(height: 8),
          Text(
            '${stop.items.length} ${stop.items.length == 1 ? 'producto' : 'productos'} · ${money(stop.loadedTotal)}${stop.orderNumber == null ? '' : ' · ${stop.orderNumber}'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (stop.rejectionMessage != null) ...[
            const SizedBox(height: 6),
            Text(stop.rejectionMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          Row(children: [
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
          ]),
        ]),
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
          ? const Center(child: Text('Todavía no terminas ninguna parada.', style: TextStyle(color: AppColors.muted)))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [for (final stop in done) DeliveryStopCard(stop: stop)]),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color ?? AppColors.ink)),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        ]),
      );
}
