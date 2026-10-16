import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';

/// One product of the whole run, all orders together.
typedef TruckLine = ({String? productId, String product, String presentation, DecimalValue loaded, DecimalValue delivered, DecimalValue missing});

/// The whole load added up by product, so the driver can count the truck: what was
/// loaded, what was already delivered and what should still be on board.
List<TruckLine> truckLoad(LocalDeliveryRun run) {
  final lines = <String, TruckLine>{};
  for (final item in run.stops.expand((stop) => stop.items)) {
    final key = '${item.productId}|${item.presentationName}';
    final before = lines[key];
    lines[key] = (
      productId: item.productId,
      product: item.productName,
      presentation: item.presentationName,
      loaded: (before?.loaded ?? DecimalValue.zero) + item.loaded,
      delivered: (before?.delivered ?? DecimalValue.zero) + (item.delivered ?? DecimalValue.zero),
      missing: (before?.missing ?? DecimalValue.zero) + (item.missing ?? DecimalValue.zero),
    );
  }
  return lines.values.toList()..sort((a, b) => a.product.toLowerCase().compareTo(b.product.toLowerCase()));
}

class TruckLoadScreen extends ConsumerWidget {
  const TruckLoadScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(deliveryRunProvider(runId));
    if (run == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Carga del camión')),
        body: const Center(child: Text('Esta jornada ya no está en el teléfono.')),
      );
    }
    final lines = truckLoad(run);
    final started = run.stops.any((stop) => stop.hasOutcome);

    return Scaffold(
      appBar: AppBar(title: Text('Carga · ${run.runNumber}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(
            '${lines.length} productos en ${run.stops.length} pedidos${started ? '. "En camión" es lo cargado menos lo entregado y lo que faltó: lo que deberías tener a bordo.' : '.'}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final (index, line) in lines.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ProductImage(productId: line.productId, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.product, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                started ? '${line.presentation} · cargado ${line.loaded} · entregado ${line.delivered}' : line.presentation,
                                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${started ? line.loaded - line.delivered - line.missing : line.loaded}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                            Text(started ? 'en camión' : 'cargado', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
