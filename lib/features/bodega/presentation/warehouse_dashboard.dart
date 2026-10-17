import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../application/bodega_providers.dart';

/// The warehouse home: find a product first, then what is waiting to be dispatched.
class WarehouseDashboard extends ConsumerWidget {
  const WarehouseDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(warehouseWorkProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/products'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.muted),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Buscar producto',
                      style: TextStyle(fontSize: 16, color: AppColors.muted),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Escanear código',
                    iconSize: 28,
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () => context.push('/products?scan=1'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (work != null) ...[
          const SizedBox(height: 20),
          const Text(
            'Despacho',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              for (final count in [
                ('Pedidos sin jornada', work.ordersWaiting, AppColors.danger),
                ('Jornadas por armar', work.drafts, AppColors.amber),
                ('Preparando tú', work.preparingMine, AppColors.brand),
                ('Listas para salir', work.loaded, AppColors.ink),
              ])
                _Count(
                  label: count.$1,
                  value: count.$2,
                  color: count.$3,
                  onTap: () => context.push('/warehouse-runs'),
                ),
            ],
          ),
          if (work.preparingOthers > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${work.preparingOthers} ${work.preparingOthers == 1 ? 'jornada la prepara' : 'jornadas las preparan'} otro bodeguero.',
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
        ],
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: value == 0 ? AppColors.muted : color,
                height: 1,
              ),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}
