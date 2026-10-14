import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import 'sync_format.dart';

/// State of the phone at a glance: last sync, queue and rejected operations.
class SyncSummaryCard extends ConsumerWidget {
  const SyncSummaryCard({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncProvider);
    final counts = ref.watch(outboxCountsProvider).value ?? (pending: 0, rejected: 0);
    final lastSync = ref.watch(lastSyncProvider).value;
    final error = status.lastReport?.error;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.running ? 'Sincronizando…' : (error != null ? 'Sin conexión con el servidor' : 'Sincronizado ${relativeTime(lastSync)}'),
                      style: TextStyle(fontWeight: FontWeight.w700, color: error != null && !status.running ? AppColors.amber : AppColors.ink),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 12, children: [
                      _Count(label: 'por enviar', value: counts.pending, color: counts.pending > 0 ? AppColors.amber : AppColors.muted),
                      _Count(label: 'rechazadas', value: counts.rejected, color: counts.rejected > 0 ? AppColors.danger : AppColors.muted),
                    ]),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Sincronizar ahora',
                onPressed: status.running ? null : () => ref.read(syncProvider.notifier).sync(),
                icon: status.running ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Text('$value $label', style: TextStyle(color: color, fontSize: 13));
}
