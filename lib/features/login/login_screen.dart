import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/api.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController();
  bool _busy = false;
  bool _showServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(secureStoreProvider).serverUrl().then((url) {
      if (mounted) _server.text = url;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(sessionProvider.notifier).login(
            email: _email.text.trim(),
            password: _password.text,
            serverUrl: _server.text.trim(),
          );
    } on ApiException catch (error) {
      setState(() => _error = error.isNetwork ? 'No se pudo conectar con el servidor. Revisa la señal o la dirección del servidor.' : error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(syncProvider.select((status) => status.notice));

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Proximus', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.brand)),
                    const SizedBox(height: 4),
                    Text('Inicia sesión para trabajar con o sin señal.', style: TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 32),
                    if (notice != null) ...[
                      _Banner(message: notice),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Correo'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      validator: (value) => (value == null || !value.contains('@')) ? 'Escribe tu correo.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Contraseña'),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) => (value == null || value.isEmpty) ? 'Escribe tu contraseña.' : null,
                    ),
                    if (_showServer) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _server,
                        decoration: const InputDecoration(labelText: 'Servidor', helperText: 'Ej. http://192.168.1.10/Proximus/public'),
                        keyboardType: TextInputType.url,
                        validator: (value) => (value == null || !value.startsWith('http')) ? 'Dirección inválida.' : null,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _Banner(message: _error!),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _showServer = !_showServer),
                      child: Text(_showServer ? 'Ocultar servidor' : 'Cambiar servidor'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF4ED), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFED7AA))),
        child: Text(message, style: const TextStyle(color: AppColors.danger)),
      );
}
