import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/formatting.dart';
import '../../bodega/presentation/catalog_edit.dart' show EditablePhoto;
import '../../bodega/presentation/online.dart';
import '../../preventa/presentation/daily_route_screen.dart' show StatusChip;
import '../application/catalog_admin.dart';
import 'presentation_screen.dart';
import 'product_form_screen.dart';
import 'supplier_link_sheet.dart';

/// A product as the server holds it, to manage: its data, presentations with their
/// prices, and who supplies it. Read live; every change is saved on the server.
class ProductAdminScreen extends ConsumerWidget {
  const ProductAdminScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(productDataProvider(productId));
    final product = value.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(product?.sku ?? 'Producto'),
        actions: [
          if (product != null)
            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)))),
        ],
      ),
      body: product == null
          ? value.hasError
                ? LiveError(error: value.error!, onRetry: () => ref.invalidate(productDataProvider(productId)))
                : const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(productDataProvider(productId)),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  EditablePhoto(productId: product.id),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text([product.category.name, if (product.brand != null) product.brand!.name].join(' · '), style: const TextStyle(color: AppColors.muted)),
                      Text('Unidad base: ${product.baseUnit.label}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        if (!product.isActive) const StatusChip(text: 'Inactivo', color: AppColors.danger),
                        if (product.allowsDecimal) const StatusChip(text: 'Decimales', color: AppColors.muted, outlined: true),
                        if (product.tracksLots) const StatusChip(text: 'Lote', color: AppColors.muted, outlined: true),
                        if (product.tracksExpiration) const StatusChip(text: 'Vencimiento', color: AppColors.muted, outlined: true),
                      ]),
                    ]),
                  ),
                ]),
                if (product.description != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(product.description!)),
                const SizedBox(height: 20),
                _Header(
                  title: 'Presentaciones',
                  action: 'Agregar',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PresentationScreen(product: product))),
                ),
                for (final presentation in product.presentations)
                  Card(
                    child: ListTile(
                      title: Text(presentation.name, style: TextStyle(fontWeight: FontWeight.w700, color: presentation.isActive ? AppColors.ink : AppColors.muted)),
                      subtitle: Text([
                        presentation.isBase ? 'Unidad base' : '${presentation.conversionFactor} ${product.baseUnit.detail ?? product.baseUnit.name}',
                        presentation.barcode ?? 'Sin código',
                        if (presentation.tiers.isNotEmpty) '${presentation.tiers.length} ${presentation.tiers.length == 1 ? 'escala' : 'escalas'}',
                        if (!presentation.isSellable) 'No se vende',
                        if (!presentation.isActive) 'Inactiva',
                      ].join(' · ')),
                      trailing: Text(money(presentation.salePrice), style: const TextStyle(fontWeight: FontWeight.w800)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PresentationScreen(product: product, presentation: presentation))),
                    ),
                  ),
                const SizedBox(height: 20),
                _Header(title: 'Proveedores', action: 'Agregar', onPressed: () => openSupplierLinkSheet(context, product)),
                if (product.suppliers.isEmpty) const Text('Sin proveedores registrados.', style: TextStyle(color: AppColors.muted)),
                for (final link in product.suppliers)
                  Card(
                    child: ListTile(
                      leading: Icon(link.isPreferred ? Icons.star : Icons.local_shipping_outlined, color: link.isPreferred ? AppColors.amber : AppColors.muted),
                      title: Text(link.supplier.name, style: TextStyle(fontWeight: FontWeight.w700, color: link.isActive ? AppColors.ink : AppColors.muted)),
                      subtitle: Text([product.presentationName(link.presentationId), if (link.supplierSku != null) 'código ${link.supplierSku}', if (!link.isActive) 'Inactivo'].join(' · ')),
                      trailing: Text(money(link.costPrice), style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => openSupplierLinkSheet(context, product, link: link),
                    ),
                  ),
              ]),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.action, required this.onPressed});

  final String title;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
    TextButton.icon(onPressed: onPressed, icon: const Icon(Icons.add), label: Text(action)),
  ]);
}
