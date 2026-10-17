import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/modules.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../bodega/presentation/warehouse_dashboard.dart';
import '../supervision/presentation/supervisor_dashboard.dart';
import '../reparto/presentation/driver_dashboard.dart';
import '../session/background_banner.dart';
import '../session/session_banner.dart';
import '../sync/sync_screen.dart';
import '../sync/sync_summary_card.dart';

const roleLabels = {'admin': 'Administrador', 'supervisor': 'Supervisor', 'preventista': 'Preventista', 'repartidor': 'Repartidor', 'bodeguero': 'Bodeguero'};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    // Right after signing out this screen rebuilds once before the router shows the login.
    if (session == null) return const Scaffold();
    ref.watch(syncProvider);
    final manifest = ref.watch(manifestProvider).value;
    final modules = manifest == null ? const <AppModule>[] : modulesFor(manifest, session);
    // A driver's home is their day, not a menu: the dashboard takes the place of the modules.
    // A supervisor may also record deliveries, but their home is the panel, not a driver's day.
    final driverHome = modules.any((module) => module.path == '/deliveries') &&
        !modules.any((module) => module.path == '/route' || module.path == '/field' || module.path == '/warehouse-runs');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.userName, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${roleLabels[session.role] ?? session.role} · Teléfono ${session.deviceCode}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
        actions: [IconButton(tooltip: 'Ajustes', icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/settings'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SessionBanner(),
          const BackgroundBanner(),
          const ClockWarning(),
          if (driverHome) ...[
            const DriverDashboard(),
            const SizedBox(height: 20),
            SyncSummaryCard(onTap: () => context.go('/sync')),
          ] else ...[
            // Management starts from the day's money and what waits for them.
            if (session.can('reports:view')) ...[
              const SupervisorDashboard(),
              const SizedBox(height: 20),
            ],
            // Whoever dispatches (warehouse, supervisor) starts from products and what waits to go out.
            if (manifest?.hasResource('dispatch_orders') ?? false) ...[
              const WarehouseDashboard(),
              const SizedBox(height: 20),
            ],
            SyncSummaryCard(onTap: () => context.go('/sync')),
            const SizedBox(height: 24),
            const Text(
              'Módulos',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            if (manifest == null)
              const Text('Sincroniza con señal para cargar tus módulos.', style: TextStyle(color: AppColors.muted))
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [for (final module in modules) _ModuleTile(module: module)],
              ),
          ],
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final color = module.isReady ? AppColors.brand : AppColors.muted;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: module.isReady ? () => context.go(module.path!) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(module.icon, color: color),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.label,
                    style: TextStyle(fontWeight: FontWeight.w600, color: module.isReady ? AppColors.ink : AppColors.muted),
                  ),
                  if (!module.isReady) const Text('En construcción', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
