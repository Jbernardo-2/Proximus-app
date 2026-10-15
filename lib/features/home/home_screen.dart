import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/modules.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../sync/sync_screen.dart';
import '../sync/sync_summary_card.dart';

const roleLabels = {
  'admin': 'Administrador',
  'supervisor': 'Supervisor',
  'preventista': 'Preventista',
  'repartidor': 'Repartidor',
  'bodeguero': 'Bodeguero',
};

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
          const ClockWarning(),
          SyncSummaryCard(onTap: () => context.go('/sync')),
          const SizedBox(height: 24),
          const Text('Módulos', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
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
      if (confirmed != true || !context.mounted) return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    final notifier = ref.read(sessionProvider.notifier);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Expanded(child: Text('Cerrando sesión…')),
        ]),
      ),
    );
    await notifier.prepareLogout();
    navigator.pop();
    await notifier.endSession();
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
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(module.label, style: TextStyle(fontWeight: FontWeight.w600, color: module.isReady ? AppColors.ink : AppColors.muted)),
                if (!module.isReady) const Text('En construcción', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
