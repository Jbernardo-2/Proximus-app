import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/modules.dart';
import '../../app/providers.dart';
import '../../app/brand.dart';
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
    final ready = [for (final module in modules) if (module.isReady) module];
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
      ),
      // Every option lives in the menu; the home keeps only what the day needs.
      drawer: _Menu(modules: ready, userName: session.userName, subtitle: '${roleLabels[session.role] ?? session.role} · Teléfono ${session.deviceCode}'),
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
            if (manifest == null)
              const Padding(padding: EdgeInsets.only(top: 16), child: Text('Sincroniza con señal para cargar tus módulos.', style: TextStyle(color: AppColors.muted)))
            // Without a panel of their own (the salesperson) the shortcuts stay on the home.
            else if (!session.can('reports:view') && !manifest.hasResource('dispatch_orders')) ...[
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [for (final module in ready) _ModuleTile(module: module)],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The side menu: who is signed in, every module, the sync, and the settings at the bottom.
class _Menu extends StatelessWidget {
  const _Menu({required this.modules, required this.userName, required this.subtitle});

  final List<AppModule> modules;
  final String userName;
  final String subtitle;

  void _open(BuildContext context, String path) {
    Navigator.pop(context);
    context.push(path);
  }

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const ProximusLogo(markSize: 40),
            const SizedBox(height: 14),
            Text(userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
            for (final module in modules) ListTile(leading: Icon(module.icon, color: AppColors.brand), title: Text(module.label), onTap: () => _open(context, module.path!)),
            ListTile(leading: const Icon(Icons.sync, color: AppColors.brand), title: const Text('Sincronización'), onTap: () => _open(context, '/sync')),
          ]),
        ),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Ajustes'), onTap: () => _open(context, '/settings')),
      ]),
    ),
  );
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final AppModule module;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.go(module.path!),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(module.icon, color: AppColors.brand),
            Text(module.label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
          ],
        ),
      ),
    ),
  );
}
