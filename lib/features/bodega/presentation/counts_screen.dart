import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/bodega_providers.dart';
import '../application/count_actions.dart';
import '../data/product_counts.dart';
import '../data/warehouse_catalog.dart';
import 'barcode_scanner_screen.dart';
import 'count_sheet.dart';
import 'online.dart';
import 'product_search_screen.dart';

final _time = DateFormat("d MMM · HH:mm", 'es');

/// The latest counts the server applied: the keeper's own, everyone's for a supervisor.
class CountsScreen extends ConsumerWidget {
  const CountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(productCountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conteos'),
        actions: [IconButton(tooltip: 'Escanear y contar', icon: const Icon(Icons.qr_code_scanner), onPressed: () => scanAndCount(context, ref))],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => pickAndCount(context, ref), icon: const Icon(Icons.add), label: const Text('Contar producto')),
      body: counts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LiveError(error: error, onRetry: () => ref.invalidate(productCountsProvider)),
        data: (counts) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(productCountsProvider),
          child: counts.isEmpty
              ? ListView(children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Escanea o busca un producto y anota cuánto hay. El ajuste se aplica al momento.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: counts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _CountTile(count: counts[index]),
                ),
        ),
      ),
    );
  }
}

Future<void> _count(BuildContext context, WarehouseProduct item) => openCountSheet(context, item);

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

class _CountTile extends StatelessWidget {
  const _CountTile({required this.count});

  final ProductCount count;

  @override
  Widget build(BuildContext context) {
    final difference = count.difference;
    final balanced = difference.isZero;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        leading: ProductImage(productId: count.productId, size: 48),
        title: Text(count.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text([_time.format(count.postedAt), count.countNumber, ?count.countedBy].join(' · ')),
          if (count.notes != null) Text(count.notes!, style: const TextStyle(fontStyle: FontStyle.italic)),
        ]),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${count.counted} ${count.unit}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(
            balanced ? 'cuadra' : difference.isNegative ? '$difference' : '+$difference',
            style: TextStyle(fontWeight: FontWeight.w700, color: balanced ? AppColors.brand : AppColors.danger),
          ),
        ]),
      ),
    );
  }
}
