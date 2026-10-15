import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/formatting.dart';
import '../data/preventa_models.dart';
import 'daily_route_screen.dart' show StatusChip;
import 'order_detail_screen.dart';

/// Customers of today's route already attended, with whether the server has what
/// was recorded for them yet.
class VisitedStopsScreen extends ConsumerWidget {
  const VisitedStopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(dailyRouteProvider).value;
    final visited = route?.visitedStops ?? const <LocalRouteActivity>[];
    final waiting = visited.where((stop) => stop.operationState == LocalOperationState.pending).length;
    final rejected = visited.where((stop) => stop.operationState == LocalOperationState.rejected).length;

    return Scaffold(
      appBar: AppBar(title: Text('Visitados (${visited.length})')),
      body: visited.isEmpty
          ? const Center(child: Text('Todavía no has visitado clientes hoy.', style: TextStyle(color: AppColors.muted)))
          : RefreshIndicator(
              onRefresh: () => ref.read(syncProvider.notifier).sync(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    [
                      if (waiting == 0 && rejected == 0) 'Todo confirmado por el servidor.',
                      if (waiting > 0) '$waiting por enviar',
                      if (rejected > 0) '$rejected con rechazo',
                    ].join(' · '),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: rejected > 0 ? AppColors.danger : (waiting > 0 ? AppColors.amber : AppColors.brand),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final stop in visited) _VisitedCard(stop: stop),
                ],
              ),
            ),
    );
  }
}

class _VisitedCard extends StatelessWidget {
  const _VisitedCard({required this.stop});

  final LocalRouteActivity stop;

  @override
  Widget build(BuildContext context) {
    final activity = stop.activity;
    final (sendLabel, sendColor) = switch (stop.operationState) {
      LocalOperationState.pending => ('Por enviar', AppColors.amber),
      LocalOperationState.rejected => ('Rechazado', AppColors.danger),
      _ => ('Confirmado', AppColors.brand),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/customer/${stop.customer.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(stop.customer.businessName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              const SizedBox(width: 8),
              StatusChip(text: sendLabel, color: sendColor, outlined: stop.operationState != LocalOperationState.synchronized && stop.operationState != LocalOperationState.accepted),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (activity.hasOrder) StatusChip(text: 'Pedido ${money(activity.ordersTotal)}', color: AppColors.brand),
              if (activity.hasNoSale && !activity.hasOrder) const StatusChip(text: 'Sin venta', color: AppColors.amber),
              if (activity.hasPayment) StatusChip(text: 'Abonó ${money(activity.paymentsTotal)}', color: const Color(0xFF2F6FD0)),
              if (!activity.hasOrder && !activity.hasNoSale && !activity.hasPayment) const StatusChip(text: 'Visitado', color: Color(0xFF2F6FD0)),
            ]),
            if (stop.orderKey != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => openOrder(context, stop.orderKey!),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(stop.orderNumber == null ? 'Ver pedido' : 'Ver pedido ${stop.orderNumber}'),
                ),
              ),
            if (stop.rejectionMessage != null) ...[
              const SizedBox(height: 6),
              Text(stop.rejectionMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ]),
        ),
      ),
    );
  }
}
