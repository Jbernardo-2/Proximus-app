import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/api.dart';

/// Tells the user when the server is not accepting the session (opened without signal,
/// expired) and lets them enter the password to send what is pending. Also warns
/// before the session expires if the phone has not been online to renew it.
class SessionBanner extends ConsumerWidget {
  const SessionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session == null) return const SizedBox.shrink();

    if (session.needsReauth) {
      return _Banner(
        color: const Color(0xFFFFF7E6),
        textColor: const Color(0xFF8A5A00),
        text: 'Trabajando sin conexión con el servidor. Lo que registres se guarda en el teléfono; cuando tengas señal, ingresa tu contraseña para enviarlo.',
        action: TextButton(onPressed: () => showReauthDialog(context), child: const Text('Ingresar contraseña')),
      );
    }

    final expiresAt = session.expiresAt;
    if (expiresAt != null && expiresAt.difference(DateTime.now()) < const Duration(days: 5)) {
      return _Banner(
        color: const Color(0xFFFFF7E6),
        textColor: const Color(0xFF8A5A00),
        text: 'Tu sesión vence el ${DateFormat('dd/MM').format(expiresAt)}. Conéctate a internet para renovarla sola.',
      );
    }
    return const SizedBox.shrink();
  }
}

/// Online login of the same user, to get a session the server accepts again.
Future<void> showReauthDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _ReauthDialog());

class _ReauthDialog extends ConsumerStatefulWidget {
  const _ReauthDialog();

  @override
  ConsumerState<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends ConsumerState<_ReauthDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = session.email.isNotEmpty ? session.email : ((await ref.read(secureStoreProvider).offlineCredential())?.email ?? '');
      await ref.read(sessionProvider.notifier).login(email: email, password: _password.text, serverUrl: session.serverUrl);
      if (ref.read(sessionProvider).value?.needsReauth ?? true) {
        setState(() => _error = 'Todavía no hay conexión con el servidor. Inténtalo cuando tengas señal.');
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ingresar contraseña'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Con señal, para que el servidor vuelva a aceptar tu sesión y reciba lo pendiente.', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.danger))],
        ]),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Después')),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'),
          ),
        ],
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.textColor, required this.text, this.action});

  final Color color;
  final Color textColor;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TextStyle(color: textColor)),
          if (action != null) Align(alignment: Alignment.centerRight, child: action) else const SizedBox(height: 8),
        ]),
      );
}
