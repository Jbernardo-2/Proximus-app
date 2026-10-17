import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/api.dart';

/// Runs one warehouse step against the server. On a refusal or without signal it shows
/// why and nothing is left half done on the phone. Returns whether it went through.
Future<bool> runOnline(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on ApiException catch (error) {
    if (context.mounted) {
      final message = error.isNetwork ? 'Sin conexión: no se guardó. Revisa la señal e intenta de nuevo.' : error.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.danger, duration: const Duration(seconds: 6)));
    }
    return false;
  }
}

/// What a live screen shows when the server could not be reached.
class LiveError extends StatelessWidget {
  const LiveError({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error as ApiException).isNetwork;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(offline ? Icons.wifi_off : Icons.error_outline, size: 44, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            offline ? 'Sin conexión con el servidor. En bodega se trabaja con señal.' : '$error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ]),
      ),
    );
  }
}
