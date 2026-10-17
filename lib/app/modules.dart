import 'package:flutter/material.dart';

import '../core/session.dart';
import '../sync/sync_manifest.dart';

/// An entry of the home menu. It shows when the server says the user can use
/// it (manifest resources and operations, token abilities), never by role name.
final class AppModule {
  const AppModule({required this.label, required this.icon, required this.isAvailable, this.path});

  final String label;
  final IconData icon;

  /// Screen to open; null while the module is still being built.
  final String? path;
  final bool Function(SyncManifest manifest, Session session) isAvailable;

  bool get isReady => path != null;
}

const appModules = [
  AppModule(
    label: 'Ruta del día',
    icon: Icons.route_outlined,
    path: '/route',
    isAvailable: _routeActivity,
  ),
  AppModule(label: 'Clientes', icon: Icons.storefront_outlined, path: '/customers', isAvailable: _customers),
  AppModule(label: 'Mi jornada', icon: Icons.local_shipping_outlined, path: '/deliveries', isAvailable: _deliveries),
  AppModule(label: 'Jornadas de bodega', icon: Icons.inventory_outlined, path: '/warehouse-runs', isAvailable: _prepares),
  AppModule(label: 'Conteos', icon: Icons.fact_check_outlined, path: '/counts', isAvailable: _counts),
  AppModule(label: 'Entradas', icon: Icons.move_to_inbox_outlined, isAvailable: _receipts),
  AppModule(label: 'Crédito', icon: Icons.account_balance_wallet_outlined, isAvailable: _credit),
  AppModule(label: 'Reportes', icon: Icons.bar_chart, isAvailable: _reports),
];

bool _routeActivity(SyncManifest manifest, Session session) => manifest.hasResource('route_activity');

/// For whoever takes orders; the driver sees their customers inside the run.
bool _customers(SyncManifest manifest, Session session) => manifest.hasResource('customers') && manifest.supports('order.create');

bool _deliveries(SyncManifest manifest, Session session) =>
    manifest.hasResource('delivery_runs') && manifest.supports('delivery.outcome');

// The warehouse works online, so its modules follow the session's permissions, not the offline queue.
bool _prepares(SyncManifest manifest, Session session) => session.can('deliveries:prepare');

bool _counts(SyncManifest manifest, Session session) => session.can('inventory:operate');

bool _receipts(SyncManifest manifest, Session session) => session.can('inventory:operate');

bool _credit(SyncManifest manifest, Session session) => session.can('credits:configure');

bool _reports(SyncManifest manifest, Session session) => session.can('reports:view');

List<AppModule> modulesFor(SyncManifest manifest, Session session) => [
      for (final module in appModules)
        if (module.isAvailable(manifest, session)) module,
    ];
