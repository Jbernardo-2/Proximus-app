import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../preventa/presentation/daily_route_screen.dart' show StatusChip;
import '../../preventa/presentation/product_image.dart';
import '../application/bodega_providers.dart';
import '../application/count_actions.dart';
import '../data/product_counts.dart';
import '../data/warehouse_catalog.dart';
import 'barcode_scanner_screen.dart';
import 'count_sheet.dart';
import 'product_search_screen.dart';

final _time = DateFormat("d MMM · HH:mm", 'es');

/// Products counted on this phone, with the difference once the server applied them.
class CountsScreen extends ConsumerWidget {
  const CountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(localCountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conteos'),
        actions: [IconButton(tooltip: 'Escanear y contar', icon: const Icon(Icons.qr_code_scanner), onPressed: () => scanAndCount(context, ref))],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => pickAndCount(context, ref), icon: const Icon(Icons.add), label: const Text('Contar producto')),
      body: counts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Escanea o busca un producto y anota cuánto hay. Funciona sin señal: se envía al tenerla.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: counts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _CountTile(count: counts[index]),
            ),
    );
  }
}

Future<void> _count(BuildContext context, WarehouseProduct item) async {
  final saved = await openCountSheet(context, item);
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conteo de ${item.product.name} registrado.')));
  }
}

Future<void> scanAndCount(BuildContext context, WidgetRef ref) async {
  final code = await scanBarcode(context);
  if (code == null || !context.mounted) return;
  final item = productForBarcode(ref.read(warehouseProductsProvider), code);
  if (item == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('El código $code no está registrado. Búscalo por nombre.')));
    return;
  }
  await _count(context, item);
}

Future<void> pickAndCount(BuildContext context, WidgetRef ref) async {
  final item = await Navigator.of(context).push<WarehouseProduct>(
    MaterialPageRoute(builder: (context) => ProductSearchScreen(title: 'Elegir producto', onPick: (item) => Navigator.pop(context, item))),
  );
  if (item != null && context.mounted) await _count(context, item);
}

class _CountTile extends ConsumerWidget {
  const _CountTile({required this.count});

  final LocalCount count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(warehouseProductProvider(count.productId));
    final unit = item?.product.baseUnit ?? 'u';
    final warehouses = ref.watch(warehouseNamesProvider);
    // Until the server answers, an estimate against the last downloaded stock.
    final difference = count.difference ?? (count.isPending && item != null ? count.counted - item.onHandIn(count.warehouseId) : null);
    final color = difference == null || difference.isZero ? AppColors.brand : AppColors.danger;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        leading: ProductImage(productId: count.productId, size: 48),
        title: Text(item?.product.name ?? 'Producto', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text([_time.format(count.countedAt), if (warehouses.length > 1) warehouses[count.warehouseId] ?? '', ?count.countNumber].join(' · ')),
          if (count.notes != null) Text(count.notes!, style: const TextStyle(fontStyle: FontStyle.italic)),
          if (count.isRejected) Text(count.message ?? 'El servidor no aceptó el conteo.', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          count.isRejected
              ? const StatusChip(text: 'Rechazado', color: AppColors.danger)
              : count.isPending
              ? const StatusChip(text: 'Sin enviar', color: AppColors.amber)
              : const StatusChip(text: 'Aplicado', color: AppColors.brand),
        ]),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${count.counted} $unit', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (difference != null)
            Text(
              '${count.difference == null ? '≈ ' : ''}${_signed(difference)}',
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
        ]),
      ),
    );
  }
}

String _signed(DecimalValue value) => value.isZero ? 'cuadra' : value.isNegative ? '$value' : '+$value';
