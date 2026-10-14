import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../sync/sync_summary_card.dart';

const roleLabels = {
  'admin': 'Administrador',
  'supervisor': 'Supervisor',
  'preventista': 'Preventista',
  'repartidor': 'Repartidor',
  'bodeguero': 'Bodeguero',
};

/// Modules each role will find here as they are built, phase by phase.
const _modules = {
  'preventista': [('Ruta del día', Icons.route_outlined), ('Clientes', Icons.storefront_outlined), ('Nuevo pedido', Icons.add_shopping_cart), ('Abonos', Icons.payments_outlined)],
  'repartidor': [('Mi jornada', Icons.local_shipping_outlined), ('Entregas y cobros', Icons.receipt_long_outlined)],
  'bodeguero': [('Preparación', Icons.inventory_2_outlined), ('Inventario', Icons.warehouse_outlined)],
  'supervisor': [('Panel', Icons.space_dashboard_outlined), ('Reportes', Icons.bar_chart), ('Crédito', Icons.account_balance_wallet_outlined), ('Jornadas', Icons.local_shipping_outlined)],
  'admin': [('Panel', Icons.space_dashboard_outlined), ('Reportes', Icons.bar_chart), ('Crédito', Icons.account_balance_wallet_outlined), ('Jornadas', Icons.local_shipping_outlined)],
};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value!;
    ref.watch(syncProvider);
    final modules = _modules[session.role] ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.userName, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${roleLabels[session.role] ?? session.role} · Teléfono ${session.deviceCode}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout), onPressed: () => _logout(context, ref)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SyncSummaryCard(onTap: () => context.go('/sync')),
          const SizedBox(height: 24),
          const Text('Módulos', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              for (final (label, icon) in modules)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(icon, color: AppColors.muted),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted)),
                          const Text('En construcción', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ]),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final counts = ref.read(outboxCountsProvider).value;
    if ((counts?.pending ?? 0) > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hay operaciones sin enviar'),
          content: Text('${counts!.pending} operaciones siguen en el teléfono. Se intentará enviarlas ahora; si no hay señal se enviarán cuando vuelvas a iniciar sesión con tu usuario.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref.read(sessionProvider.notifier).logout();
  }
}
