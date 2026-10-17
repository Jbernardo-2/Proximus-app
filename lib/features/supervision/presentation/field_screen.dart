import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/formatting.dart';
import '../../bodega/presentation/online.dart';
import '../../preventa/presentation/daily_route_screen.dart' show StatusChip;
import '../application/supervision_providers.dart';
import '../data/supervision_models.dart';
import 'supervisor_dashboard.dart' show RunProgressTile;

final _time = DateFormat('HH:mm');

String _since(DateTime? at) {
  if (at == null) return 'sin actividad hoy';
  final minutes = DateTime.now().difference(at).inMinutes;
  return minutes < 60 ? 'última actividad hace $minutes min' : 'última actividad ${_time.format(at)}';
}

/// How the street goes today: each salesperson's route and each run on the road.
class FieldScreen extends ConsumerWidget {
  const FieldScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final field = ref.watch(fieldActivityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Campo')),
      body: field.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LiveError(error: error, onRetry: () => ref.invalidate(fieldActivityProvider)),
        data: (field) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(fieldActivityProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Preventistas', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (field.routes.isEmpty) const Text('Nadie tiene ruta hoy.', style: TextStyle(color: AppColors.muted)),
              for (final route in field.routes)
                Card(
                  child: ListTile(
                    title: Text(route.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${route.visited} de ${route.stops} visitas · ${route.withOrder} con pedido · ${route.noSale} sin venta'),
                      Text('Vendido ${money(route.sold)} · cobrado ${money(route.collected)}'),
                      Text(_since(route.lastActivityAt), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: route.progress, minHeight: 5, borderRadius: BorderRadius.circular(3)),
                    ]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _RouteStopsScreen(route: route))),
                  ),
                ),
              const SizedBox(height: 16),
              const Text('Repartidores', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (field.runs.isEmpty) const Text('No hay jornadas en ruta.', style: TextStyle(color: AppColors.muted)),
              for (final run in field.runs) RunProgressTile(run: run),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteStopsScreen extends ConsumerWidget {
  const _RouteStopsScreen({required this.route});

  final RouteProgress route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(salespersonStopsProvider(route.id));
    return Scaffold(
      appBar: AppBar(title: Text(route.name)),
      body: stops.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LiveError(error: error, onRetry: () => ref.invalidate(salespersonStopsProvider(route.id))),
        data: (stops) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(salespersonStopsProvider(route.id)),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: stops.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final stop = stops[index];
              final (label, color) = switch (stop.status) {
                'order_taken' => ('Pedido ${money(stop.ordersTotal)}', AppColors.brand),
                'no_sale' => (stop.noSaleReason ?? 'Sin venta', AppColors.amber),
                'visited' => ('Visitado', AppColors.ink),
                _ => ('Pendiente', AppColors.muted),
              };
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${stop.visitOrder}')),
                  title: Text(stop.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Wrap(spacing: 6, runSpacing: 4, children: [
                    StatusChip(text: label, color: color),
                    if (!stop.paymentsTotal.isZero) StatusChip(text: 'Abono ${money(stop.paymentsTotal)}', color: AppColors.brand, outlined: true),
                  ]),
                  trailing: stop.activityAt == null ? null : Text(_time.format(stop.activityAt!), style: const TextStyle(color: AppColors.muted)),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
