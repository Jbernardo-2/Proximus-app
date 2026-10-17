import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../preventa/presentation/product_image.dart';
import '../../../app/providers.dart';
import '../application/bodega_providers.dart';
import 'count_sheet.dart';

/// Everything the warehouse checks on a product: stock per warehouse and each presentation.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(warehouseProductProvider(productId));
    if (item == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Este producto ya no está en el catálogo.', style: TextStyle(color: AppColors.muted))));
    }
    final product = item.product;
    final unit = product.baseUnit ?? 'u';
    final warehouses = ref.watch(warehouseNamesProvider);
    final manifestCounts = ref.watch(sessionProvider).value?.can('inventory:operate') ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(product.sku)),
      floatingActionButton: manifestCounts
          ? FloatingActionButton.extended(onPressed: () => openCountSheet(context, item), icon: const Icon(Icons.fact_check_outlined), label: const Text('Contar'))
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProductImage(productId: product.id, size: 96),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 4),
                Text([product.sku, if (product.brand != null) product.brand!, if (product.category != null) product.category!].join(' · '), style: const TextStyle(color: AppColors.muted)),
                Text('Unidad base: $unit${product.allowsDecimal ? ' (acepta decimales)' : ''}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          const Text('Existencia', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (warehouses.isEmpty) const Text('Sin bodegas descargadas.', style: TextStyle(color: AppColors.muted)),
          for (final entry in warehouses.entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _Figure(label: 'Físico', value: item.stocks[entry.key]?.onHand ?? DecimalValue.zero, unit: unit, lead: true),
                    _Figure(label: 'Reservado', value: item.stocks[entry.key]?.reserved ?? DecimalValue.zero, unit: unit),
                    _Figure(label: 'Disponible', value: item.stocks[entry.key]?.available ?? DecimalValue.zero, unit: unit),
                  ]),
                ]),
              ),
            ),
          const SizedBox(height: 20),
          const Text('Presentaciones', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final presentation in product.presentations)
            Card(
              child: ListTile(
                title: Text(presentation.name, style: TextStyle(fontWeight: FontWeight.w700, color: presentation.isActive ? AppColors.ink : AppColors.muted)),
                subtitle: Text([
                  presentation.isBase ? 'Unidad base' : '${presentation.conversionFactor} $unit',
                  presentation.barcode ?? 'Sin código de barras',
                  if (!presentation.isActive) 'Inactiva',
                ].join(' · ')),
                trailing: presentation.isSellable ? Text(money(presentation.salePrice), style: const TextStyle(fontWeight: FontWeight.w700)) : const Text('No se vende', style: TextStyle(color: AppColors.muted)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.unit, this.lead = false});

  final String label;
  final DecimalValue value;
  final String unit;
  final bool lead;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      Text('$value $unit', style: TextStyle(fontSize: lead ? 20 : 16, fontWeight: lead ? FontWeight.w800 : FontWeight.w600, color: value.isNegative ? AppColors.danger : AppColors.ink)),
    ]),
  );
}
