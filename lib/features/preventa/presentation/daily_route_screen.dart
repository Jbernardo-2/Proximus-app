import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../data/preventa_models.dart';
import '../data/preventista_repository.dart';

class DailyRouteScreen extends ConsumerWidget {
  const DailyRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(dailyRouteProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruta del día'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: ref.watch(syncProvider).running
                ? null
                : () => ref.read(syncProvider.notifier).sync(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: activities.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(
          icon: Icons.sync_problem,
          title: 'No se pudo leer la ruta local',
          detail: error.toString(),
        ),
        data: (route) {
          final items = route.stops;
          if (items.isEmpty) {
            return const _Message(
              icon: Icons.event_available_outlined,
              title: 'No hay clientes programados hoy',
              detail: 'Sincroniza si el supervisor acaba de modificar la ruta.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(syncProvider.notifier).sync(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (route.isStale) ...[
                  const _StaleBanner(),
                  const SizedBox(height: 12),
                ],
                _ProgressCard(route: route, routeName: items.first.routeName),
                const SizedBox(height: 12),
                for (final activity in items) _ActivityCard(activity: activity),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF5D08A))),
        child: const Text(
          'Esta es la ruta de otro día. Sincroniza con señal para recibir la de hoy; lo que registres se guardará igual.',
          style: TextStyle(color: AppColors.amber),
        ),
      );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.route, required this.routeName});

  final DailyRoute route;
  final String routeName;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(routeName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: route.progress),
              const SizedBox(height: 8),
              Text('${route.attended} de ${route.stops.length} atendidos · ${route.withOrder} con pedido · ${route.withNoSale} sin venta', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 4),
              Text('Vendido L ${route.sold.toFixed(2)} · Abonos L ${route.collected.toFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});

  final LocalRouteActivity activity;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (activity.status) {
      'order_taken' => ('Pedido tomado', Colors.green, Icons.check_circle_outline),
      'no_sale' => ('Sin venta', Colors.orange, Icons.do_not_disturb_alt_outlined),
      'visited' => ('Visitado', Colors.blue, Icons.how_to_reg_outlined),
      _ => ('Pendiente', AppColors.muted, Icons.schedule),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _showCustomer(context),
        leading: CircleAvatar(child: Text('${activity.visitOrder}')),
        title: Text(activity.customer.businessName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(activity.customer.address, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Row(children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              if (activity.activity.hasPayment) ...[
                const SizedBox(width: 8),
                const Icon(Icons.payments_outlined, size: 16, color: Colors.blue),
              ],
              if (activity.operationState == LocalOperationState.pending) ...[
                const SizedBox(width: 8),
                const Text('Pendiente de envío', style: TextStyle(fontSize: 11, color: Colors.orange)),
              ],
              if (activity.operationState == LocalOperationState.rejected) ...[
                const SizedBox(width: 8),
                const Text('Requiere revisión', style: TextStyle(fontSize: 11, color: Colors.red)),
              ],
            ]),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  void _showCustomer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(activity.customer.businessName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _Detail(icon: Icons.place_outlined, text: activity.customer.address),
            if ((activity.customer.reference ?? '').isNotEmpty)
              _Detail(icon: Icons.signpost_outlined, text: activity.customer.reference!),
            if ((activity.customer.contactName ?? '').isNotEmpty)
              _Detail(icon: Icons.person_outline, text: activity.customer.contactName!),
            if ((activity.customer.phone ?? '').isNotEmpty)
              _Detail(icon: Icons.phone_outlined, text: activity.customer.phone!),
            if (activity.rejectionMessage != null)
              _Detail(icon: Icons.error_outline, text: activity.rejectionMessage!, color: Colors.red),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color ?? AppColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ]),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ]),
        ),
      );
}
