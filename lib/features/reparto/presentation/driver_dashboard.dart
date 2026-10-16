import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/external_apps.dart';
import '../../../core/formatting.dart';
import '../../preventa/presentation/daily_route_screen.dart' show StatusChip;
import '../../../app/providers.dart';
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';
import '../data/delivery_repository.dart';
import '../data/run_closing.dart';
import 'run_closing_screen.dart' show openRunClosing;

final _today = DateFormat("EEEE d 'de' MMMM", 'es');

/// The driver's home: how much is left today, what was collected and where to go next.
/// One number leads (stops left); everything else supports it.
class DriverDashboard extends ConsumerWidget {
  const DriverDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(deliveryRunsProvider).value ?? const <LocalDeliveryRun>[];
    final toWork = runsToWork(runs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(toBeginningOfSentenceCase(_today.format(DateTime.now())), style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 10),
        if (toWork.isEmpty && runs.isNotEmpty)
          _Finished(run: (runs.toList()..sort((a, b) => (b.scheduledDate ?? DateTime(0)).compareTo(a.scheduledDate ?? DateTime(0)))).first)
        else if (toWork.isEmpty)
          const _Idle()
        else ...[
          _TodayCard(run: toWork.first),
          const SizedBox(height: 12),
          _Figures(run: toWork.first),
          if (toWork.first.nextStop != null) ...[
            const SizedBox(height: 20),
            const Text('Siguiente parada', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _NextStop(run: toWork.first, stop: toWork.first.nextStop!),
          ],
          if (toWork.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton(onPressed: () => context.go('/deliveries'), child: Text('Tienes ${toWork.length - 1} ${toWork.length == 2 ? 'jornada anterior' : 'jornadas anteriores'} sin terminar')),
            ),
        ],
      ],
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          Icon(Icons.local_shipping_outlined, size: 44, color: AppColors.muted),
          SizedBox(height: 12),
          Text('Sin jornadas por entregar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text(
            'Cuando la bodega cargue tu camión aparecerá aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

/// Every stop done: the cash to hand over leads, and the closing is one tap away.
class _Finished extends ConsumerWidget {
  const _Finished({required this.run});

  final LocalDeliveryRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closing = RunClosing.of(run, ref.watch(outboxRowsProvider).value ?? const []);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terminaste la jornada ${run.runNumber}',
              style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text('Efectivo a entregar', style: TextStyle(color: AppColors.muted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(closing.cash),
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.1, color: AppColors.ink),
              ),
            ),
            if (!closing.isFinal)
              const Text(
                'Hay operaciones sin enviar: sincroniza antes de entregar.',
                style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () => openRunClosing(context, run), icon: const Icon(Icons.summarize_outlined), label: const Text('Ver cierre de jornada')),
          ],
        ),
      ),
    );
  }
}

/// The headline: stops left, the progress meter and the one action that matters now.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.run});

  final LocalDeliveryRun run;

  @override
  Widget build(BuildContext context) {
    final left = run.pendingStops.length;
    final done = run.doneStops.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Jornada ${run.runNumber}',
                    style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                  ),
                ),
                StatusChip(text: run.statusLabel, color: run.hasLeft ? AppColors.brand : AppColors.amber),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$left',
                  style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w800, height: 1, color: AppColors.ink),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    !run.hasLeft ? (left == 1 ? 'parada para hoy' : 'paradas para hoy') : (left == 1 ? 'parada por entregar' : 'paradas por entregar'),
                    style: const TextStyle(fontSize: 16, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Meter: the track is a lighter step of the same green, so progress reads across the bar.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: run.progress, minHeight: 8, color: AppColors.brand, backgroundColor: AppColors.brand.withValues(alpha: 0.14)),
            ),
            const SizedBox(height: 6),
            Text('$done de ${run.stops.length} terminadas', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/deliveries/${run.id}'),
              icon: Icon(run.hasLeft ? Icons.route : Icons.local_shipping),
              label: Text(run.hasLeft ? 'Continuar ruta' : 'Revisar carga y salir'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Supporting numbers: what is in hand, what is still to collect, and credit given.
class _Figures extends StatelessWidget {
  const _Figures({required this.run});

  final LocalDeliveryRun run;

  @override
  Widget build(BuildContext context) {
    final toCollect = run.pendingStops
        .where((stop) => !stop.isCredit)
        .fold(DecimalValue.zero, (total, stop) => total + (stop.progress == StopProgress.awaitingPayment ? stop.balanceDue : stop.loadedTotal));
    return Row(
      children: [
        _Figure(label: 'Cobrado', value: run.collectedTotal),
        const SizedBox(width: 10),
        _Figure(label: 'Por cobrar', value: toCollect),
        const SizedBox(width: 10),
        _Figure(label: 'Crédito', value: run.creditGranted ?? DecimalValue.zero),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final DecimalValue value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(value),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NextStop extends StatelessWidget {
  const _NextStop({required this.run, required this.stop});

  final LocalDeliveryRun run;
  final LocalDeliveryStop stop;

  @override
  Widget build(BuildContext context) {
    final customer = stop.customer;
    final phone = customer?.phone ?? customer?.whatsapp;
    void openStop() => context.push('/deliveries/${run.id}/stops/${stop.id}');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openStop,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: AppColors.brand.withValues(alpha: 0.12),
                    child: Text(
                      '${stop.visitOrder}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand),
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
                        Text(
                          '${money(stop.progress == StopProgress.awaitingPayment ? stop.balanceDue : stop.loadedTotal)} · ${stop.isCredit ? 'Crédito' : 'Contado'}'
                          '${stop.progress == StopProgress.awaitingPayment ? ' · falta cobrar' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Row(
                  children: [
                    if (phone != null) TextButton.icon(onPressed: () => ExternalApps.call(phone), icon: const Icon(Icons.call_outlined, size: 18), label: const Text('Llamar')),
                    TextButton.icon(
                      onPressed: () => ExternalApps.map(
                        latitude: customer?.latitude,
                        longitude: customer?.longitude,
                        label: customer?.hasLocation ?? false ? stop.customerName : '${stop.customerAddress} ${stop.customerName}',
                      ),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Cómo llegar'),
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
}
