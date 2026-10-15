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
  AppModule(label: 'Clientes', icon: Icons.storefront_outlined, isAvailable: _customers),
  AppModule(label: 'Mi jornada', icon: Icons.local_shipping_outlined, isAvailable: _deliveries),
  AppModule(label: 'Inventario', icon: Icons.warehouse_outlined, isAvailable: _inventory),
  AppModule(label: 'Crédito', icon: Icons.account_balance_wallet_outlined, isAvailable: _credit),
  AppModule(label: 'Reportes', icon: Icons.bar_chart, isAvailable: _reports),
];

bool _routeActivity(SyncManifest manifest, Session session) => manifest.hasResource('route_activity');

bool _customers(SyncManifest manifest, Session session) => manifest.hasResource('customers');

bool _deliveries(SyncManifest manifest, Session session) =>
    manifest.hasResource('delivery_runs') && manifest.supports('delivery.outcome');

bool _inventory(SyncManifest manifest, Session session) => session.can('inventory:operate');

bool _credit(SyncManifest manifest, Session session) => session.can('credits:configure');

bool _reports(SyncManifest manifest, Session session) => session.can('reports:view');

List<AppModule> modulesFor(SyncManifest manifest, Session session) => [
      for (final module in appModules)
        if (module.isAvailable(manifest, session)) module,
    ];
