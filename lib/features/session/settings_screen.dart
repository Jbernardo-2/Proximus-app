import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../home/home_screen.dart' show roleLabels;
import '../sync/sync_format.dart';

/// User, phone and server details. Signing out lives here, away from daily use:
/// the app opens straight into the session and nobody needs to sign out each day.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session == null) return const Scaffold();
    final lastSync = ref.watch(lastSyncProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(children: [
              _Info(icon: Icons.person_outline, label: session.userName, detail: '${roleLabels[session.role] ?? session.role}${session.email.isEmpty ? '' : ' · ${session.email}'}'),
              _Info(icon: Icons.smartphone, label: 'Teléfono ${session.deviceCode}', detail: 'Proximus $appVersion'),
              _Info(icon: Icons.dns_outlined, label: 'Servidor', detail: session.serverUrl),
              _Info(icon: Icons.sync, label: 'Última sincronización', detail: relativeTime(lastSync)),
              _Info(
                icon: Icons.key_outlined,
                label: 'Sesión',
                detail: session.needsReauth
                    ? 'Sin conexión con el servidor: falta ingresar la contraseña'
                    : (session.expiresAt == null ? 'Activa' : 'Activa · se renueva sola; vence el ${DateFormat('dd/MM/yyyy').format(session.expiresAt!)} si no hay conexión'),
              ),
            ]),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: AppColors.danger),
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Cambiar de usuario o cerrar sesión'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Solo es necesario si otra persona va a usar este teléfono. Para volver a entrar sin señal solo puede hacerlo el último usuario, con su contraseña.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final pending = ref.read(outboxCountsProvider).value?.pending ?? 0;
    final offline = ref.read(syncProvider).lastReport?.error?.isNetwork ?? false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (pending > 0) Text('Hay $pending operaciones sin enviar. Se intentará enviarlas ahora; si no se puede, se enviarán cuando vuelvas a entrar con tu usuario.'),
          if (pending > 0) const SizedBox(height: 8),
          if (offline) const Text('No hay señal: para volver a entrar necesitarás tu contraseña. Sin señal solo tú podrás entrar en este teléfono.'),
          if (pending == 0 && !offline) const Text('Para volver a entrar necesitarás tu correo y contraseña.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

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

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.detail});

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.muted),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(detail),
      );
}
