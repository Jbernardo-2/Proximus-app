import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/bodega_providers.dart';
import '../data/warehouse_catalog.dart';
import 'barcode_scanner_screen.dart';
import 'catalog_edit.dart';

/// Find a product by name, code or barcode, with the camera when it is at hand.
class ProductSearchScreen extends ConsumerStatefulWidget {
  const ProductSearchScreen({super.key, this.scanOnOpen = false, this.title = 'Productos', this.onPick, this.manage = false});

  /// Managing the catalog: inactive products show, a product opens to be edited, and new ones are created.
  final bool manage;

  final bool scanOnOpen;
  final String title;

  /// Choosing a product for something else (a count) instead of opening it.
  final void Function(WarehouseProduct item)? onPick;

  @override
  ConsumerState<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends ConsumerState<ProductSearchScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.scanOnOpen) WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final product = productForBarcode(ref.read(warehouseProductsProvider), code);
    if (product != null) {
      _open(product);
      return;
    }
    setState(() => _search.text = code);
    final editsCatalog = ref.read(sessionProvider).value?.can('catalog:manage') ?? false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('El código $code no está registrado en ningún producto.'),
      duration: const Duration(seconds: 8),
      action: !editsCatalog || widget.onPick != null
          ? null
          : widget.manage
          // A new product on the shelf: create it with the code just read.
          ? SnackBarAction(label: 'Crear', onPressed: () => context.push('/catalog/new?barcode=${Uri.encodeQueryComponent(code)}'))
          : SnackBarAction(label: 'Asignar', onPressed: () {
              setState(_search.clear);
              assignScannedCode(context, code);
            }),
    ));
  }

  void _open(WarehouseProduct item) => widget.onPick != null
      ? widget.onPick!(item)
      : context.push(widget.manage ? '/catalog/${item.product.id}' : '/products/${item.product.id}');

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(widget.manage ? managedProductsProvider : warehouseProductsProvider);
    final results = searchWarehouseProducts(all, _search.text);
    final warehouseId = ref.watch(manifestProvider).value?.defaultWarehouse?['id']?.toString();

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: widget.manage
          ? FloatingActionButton.extended(onPressed: () => context.push('/catalog/new'), icon: const Icon(Icons.add), label: const Text('Nuevo producto'))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Nombre, código o marca',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Borrar', icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(tooltip: 'Escanear código', iconSize: 28, icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${results.length} de ${all.length} productos', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
        ),
        Expanded(
          child: all.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Sincroniza con señal para descargar el catálogo.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ProductTile(item: results[index], warehouseId: warehouseId, onTap: () => _open(results[index])),
                ),
        ),
      ]),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.item, required this.warehouseId, required this.onTap});

  final WarehouseProduct item;
  final String? warehouseId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final onHand = item.onHandIn(warehouseId);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ProductImage(productId: product.id, size: 52),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([product.sku, if (product.brand != null) product.brand!].join(' · ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$onHand', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: onHand.isZero || onHand.isNegative ? AppColors.danger : AppColors.ink)),
            Text(product.baseUnit ?? 'u', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
