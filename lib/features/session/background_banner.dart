import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/external_apps.dart';

/// Whether the phone lets Proximus sync with the app closed; checked again each time
/// the app comes back, since the user changes it in the system settings.
final backgroundAllowedProvider = FutureProvider.autoDispose<bool?>((ref) {
  final listener = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(listener.dispose);
  return ExternalApps.isBackgroundAllowed();
});

/// Asks to let the app work without battery restrictions. Without it, with power
/// saving on, Android cuts the network in the background and what is pending only
/// goes out while the app is open.
class BackgroundBanner extends ConsumerWidget {
  const BackgroundBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(backgroundAllowedProvider).value != false) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Con el ahorro de batería, el teléfono no deja que Proximus envíe lo pendiente con la app cerrada. Permítelo para que se envíe solo.',
          style: TextStyle(color: Color(0xFF8A5A00)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: ExternalApps.requestBackground, child: const Text('Permitir')),
        ),
      ]),
    );
  }
}
