import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/external_apps.dart';
import '../../../core/formatting.dart';
import '../data/preventa_models.dart';
import '../data/preventista_repository.dart';
import 'no_sale_sheet.dart';

class DailyRouteScreen extends ConsumerWidget {
  const DailyRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(dailyRouteProvider);
    final running = ref.watch(syncProvider.select((status) => status.running));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruta del día'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: running ? null : () => ref.read(syncProvider.notifier).sync(),
            icon: running ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
          ),
        ],
      ),
      body: route.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(icon: Icons.sync_problem, title: 'No se pudo leer la ruta guardada', detail: error.toString()),
        data: (route) {
          if (route.stops.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.read(syncProvider.notifier).sync(),
              child: ListView(children: const [
                SizedBox(height: 120),
                _Message(
                  icon: Icons.event_available_outlined,
                  title: 'No tienes clientes programados hoy',
                  detail: 'Desliza hacia abajo para sincronizar si el supervisor acaba de cambiar la ruta.',
                ),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(syncProvider.notifier).sync(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (route.isStale) ...[const _StaleBanner(), const SizedBox(height: 12)],
                _Summary(route: route),
                const SizedBox(height: 16),
                for (final stop in route.stops) _StopCard(stop: stop),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.route});

  final DailyRoute route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(outboxCountsProvider).value;
    final day = DateTime.tryParse(route.date ?? route.today) ?? DateTime.now();
    final percent = (route.progress * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(route.stops.first.routeName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              '${toBeginningOfSentenceCase(DateFormat("EEEE d 'de' MMMM", 'es').format(day))} · ${route.stops.length} clientes',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: route.progress, minHeight: 8))),
              const SizedBox(width: 12),
              Text('$percent %', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              _Figure(label: 'Pendientes', value: '${route.pending}'),
              _Figure(label: 'Atendidos', value: '${route.attended}'),
              _Figure(label: 'Pedidos', value: '${route.withOrder}', color: AppColors.brand),
              _Figure(label: 'Sin venta', value: '${route.withNoSale}', color: AppColors.amber),
            ]),
            const Divider(height: 28),
            Row(children: [
              _Figure(label: 'Vendido', value: money(route.sold)),
              _Figure(label: 'Abonos', value: money(route.collected)),
            ]),
            if ((pending?.pending ?? 0) > 0 || (pending?.rejected ?? 0) > 0) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => context.go('/sync'),
                child: Text(
                  [
                    if ((pending?.pending ?? 0) > 0) '${pending!.pending} por enviar',
                    if ((pending?.rejected ?? 0) > 0) '${pending!.rejected} rechazadas',
                  ].join(' · '),
                  style: TextStyle(fontWeight: FontWeight.w600, color: (pending?.rejected ?? 0) > 0 ? AppColors.danger : AppColors.amber),
                ),
              ),
            ],
          ],
        ),
      ),
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
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color ?? AppColors.ink)),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );
}

class _StopCard extends ConsumerWidget {
  const _StopCard({required this.stop});

  final LocalRouteActivity stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(customerBalancesProvider)[stop.customer.id];
    final customer = stop.customer;
    final phone = customer.phone ?? customer.whatsapp;
    final whatsapp = customer.whatsapp ?? customer.phone;
    final (label, color) = switch (stop.status) {
      'order_taken' => ('Pedido tomado', AppColors.brand),
      'no_sale' => ('Sin venta', AppColors.amber),
      'visited' => ('Visitado', const Color(0xFF2F6FD0)),
      _ => ('Pendiente', AppColors.muted),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: stop.isCompleted ? color.withValues(alpha: 0.15) : const Color(0xFFF1F1EF),
                child: Text('${stop.visitOrder}', style: TextStyle(fontWeight: FontWeight.w700, color: stop.isCompleted ? color : AppColors.ink)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(customer.businessName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(customer.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _Chip(text: label, color: color),
              if (stop.activity.hasPayment) const _Chip(text: 'Abonó', color: Color(0xFF2F6FD0)),
              if (stop.operationState == LocalOperationState.pending) const _Chip(text: 'Por enviar', color: AppColors.amber, outlined: true),
              if (stop.operationState == LocalOperationState.rejected) const _Chip(text: 'Rechazado', color: AppColors.danger, outlined: true),
            ]),
            if (balance != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Saldo ', style: TextStyle(color: AppColors.muted)),
                    TextSpan(
                      text: money(balance.outstanding),
                      style: TextStyle(fontWeight: FontWeight.w700, color: balance.overdue.isZero ? AppColors.ink : AppColors.danger),
                    ),
                  ])),
                ),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    const TextSpan(text: 'Disponible ', style: TextStyle(color: AppColors.muted)),
                    TextSpan(
                      text: balance.allowsCredit ? money(balance.available.isNegative ? DecimalValue.zero : balance.available) : 'Sin crédito',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ])),
                ),
              ]),
            ],
            if (stop.rejectionMessage != null) ...[
              const SizedBox(height: 8),
              Text(stop.rejectionMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 6),
            Row(children: [
              if (phone != null)
                IconButton(tooltip: 'Llamar', icon: const Icon(Icons.call_outlined), onPressed: () => _open(context, ExternalApps.call(phone))),
              if (whatsapp != null)
                IconButton(tooltip: 'WhatsApp', icon: const Icon(Icons.chat_outlined), onPressed: () => _open(context, ExternalApps.whatsapp(whatsapp))),
              IconButton(
                tooltip: 'Abrir ubicación',
                icon: const Icon(Icons.place_outlined),
                onPressed: () => _open(
                  context,
                  ExternalApps.map(
                    latitude: customer.latitude,
                    longitude: customer.longitude,
                    label: customer.hasLocation ? customer.businessName : '${customer.address} ${customer.businessName}',
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _act(context, ref, 'no_sale'),
                  child: const Text('Sin venta'),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: OutlinedButton(
                  style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 44))),
                  onPressed: null,
                  child: Text('Abono'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: null,
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: const Text('Pedido'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    if (action == 'no_sale') {
      final saved = await showNoSaleSheet(context, stop);
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Visita sin venta guardada en el teléfono: ${stop.customer.businessName}.')));
      }
    }
  }

  Future<void> _open(BuildContext context, Future<bool> opening) async {
    if (!await opening && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay una app instalada para abrir esto.')));
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color, this.outlined = false});

  final String text;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: outlined ? Border.all(color: color.withValues(alpha: 0.6)) : null,
        ),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF5D08A))),
        child: const Text(
          'Esta ruta es de otro día. Sincroniza con señal para recibir la de hoy; lo que registres se guarda igual.',
          style: TextStyle(color: Color(0xFF8A5A00)),
        ),
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
