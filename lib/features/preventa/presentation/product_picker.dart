import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../application/order_draft_controller.dart';
import '../data/order_draft.dart';
import '../data/preventa_models.dart';
import 'product_image.dart';

typedef PickedProduct = ({LocalProduct product, LocalPresentation presentation, DecimalValue quantity});

/// Catalog search that stays open: each product chosen goes straight into the order.
/// Products already in the order are left out of the list; searching for them shows
/// them marked, and choosing one edits its line instead of duplicating it.
class ProductPickerScreen extends ConsumerStatefulWidget {
  const ProductPickerScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<ProductPickerScreen> createState() => _ProductPickerScreenState();
}

class _ProductPickerScreenState extends ConsumerState<ProductPickerScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _choose(LocalProduct product, DecimalValue available, OrderDraft draft) async {
    final lines = draft.lines.where((line) => line.product.id == product.id).toList();
    final editing = lines.length == 1 ? lines.single : null;
    final picked = await showModalBottomSheet<PickedProduct>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuantitySheet(
        product: product,
        available: available,
        day: draft.day,
        initial: editing?.quantity,
        presentationId: editing?.presentation.id,
      ),
    );
    if (picked == null || !mounted) return;

    final controller = ref.read(orderDraftProvider(widget.customerId).notifier);
    if (editing != null && editing.presentation.id == picked.presentation.id) {
      // Editing the line itself: the quantity typed is the new quantity.
      controller.put(picked.product, picked.presentation, picked.quantity);
    } else {
      // Another presentation, or a product with several lines: add to what is there.
      final existing = lines.where((line) => line.presentation.id == picked.presentation.id).firstOrNull;
      controller.put(picked.product, picked.presentation, (existing?.quantity ?? DecimalValue.zero) + picked.quantity);
    }
    _search.clear();
    setState(() {});
    _focus.requestFocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text('Agregado: ${picked.quantity} × ${picked.presentation.name} de ${product.name}')));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(orderDraftProvider(widget.customerId));
    if (draft == null) return const Scaffold();

    final query = _search.text;
    final terms = query.toLowerCase().split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
    final inOrder = <String, List<OrderLine>>{};
    for (final line in draft.lines) {
      inOrder.putIfAbsent(line.product.id, () => []).add(line);
    }
    final products = ref.watch(productsProvider).where((product) {
      if (terms.isEmpty) return !inOrder.containsKey(product.id);
      final haystack = [
        product.name,
        product.sku,
        product.brand ?? '',
        product.category ?? '',
        for (final presentation in product.presentations) presentation.barcode ?? '',
      ].join(' ').toLowerCase();
      return terms.every(haystack.contains);
    }).toList();
    final stock = ref.watch(availableStockProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agregar productos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${draft.lines.length} ${draft.lines.length == 1 ? 'producto' : 'productos'} · ${money(draft.total)}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.brand),
              ),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            focusNode: _focus,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Nombre, código o código de barras',
              suffixIcon: query.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? Center(
                  child: Text(
                    query.isNotEmpty ? 'Ningún producto coincide.' : (inOrder.isEmpty ? 'No hay productos en el teléfono. Sincroniza con señal.' : 'Todos los productos ya están en el pedido.'),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final available = stock[product.id] ?? DecimalValue.zero;
                    final lines = inOrder[product.id];
                    final outOfStock = available.isNegative || available.isZero;
                    return Card(
                      child: ListTile(
                        leading: ProductImage(productId: product.id),
                        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          lines != null
                              ? 'En el pedido: ${lines.map((line) => '${line.quantity} × ${line.presentation.name}').join(', ')}'
                              : '${product.sku} · ${outOfStock ? 'Sin existencias' : 'Disp. ${available.toFixed(product.allowsDecimal ? 2 : 0)} ${product.baseUnit ?? ''}'}',
                          style: TextStyle(color: lines != null ? AppColors.brand : (outOfStock ? AppColors.danger : AppColors.muted)),
                        ),
                        trailing: Icon(lines != null ? Icons.edit_outlined : Icons.add_circle_outline, color: AppColors.brand),
                        onTap: () => _choose(product, available, draft),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// Presentation and quantity of a product, with its tier price and stock.
class QuantitySheet extends StatefulWidget {
  const QuantitySheet({super.key, required this.product, required this.available, required this.day, this.initial, this.presentationId});

  final LocalProduct product;

  /// Stock available in base units.
  final DecimalValue available;
  final DateTime day;
  final DecimalValue? initial;
  final String? presentationId;

  @override
  State<QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<QuantitySheet> {
  late LocalPresentation _presentation;
  late final TextEditingController _quantity;

  @override
  void initState() {
    super.initState();
    final presentations = widget.product.sellablePresentations;
    _presentation = presentations.where((p) => p.id == widget.presentationId).firstOrNull ?? presentations.where((p) => p.isBase).firstOrNull ?? presentations.first;
    _quantity = TextEditingController(text: widget.initial?.toString() ?? '1');
  }

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final current = parseQuantity(_quantity.text, allowsDecimal: widget.product.allowsDecimal) ?? DecimalValue.zero;
    final next = current + DecimalValue.parse('$delta');
    if (next.isNegative || next.isZero) return;
    setState(() => _quantity.text = next.toString());
  }

  @override
  Widget build(BuildContext context) {
    final quantity = parseQuantity(_quantity.text, allowsDecimal: widget.product.allowsDecimal);
    final price = quantity == null ? null : _presentation.priceFor(quantity, widget.day);
    final inPresentation = widget.available.isNegative ? DecimalValue.zero : widget.available.divide(_presentation.conversionFactor, scale: 0);
    final short = quantity != null && (quantity * _presentation.conversionFactor).compareTo(widget.available) > 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ProductImage(productId: widget.product.id, size: 72),
          const SizedBox(width: 14),
          Expanded(child: Text(widget.product.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final presentation in widget.product.sellablePresentations)
            ChoiceChip(
              label: Text('${presentation.name} · ${money(presentation.salePrice)}'),
              selected: presentation.id == _presentation.id,
              onSelected: (_) => setState(() => _presentation = presentation),
            ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          IconButton.outlined(onPressed: () => _step(-1), icon: const Icon(Icons.remove)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _quantity,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.numberWithOptions(decimal: widget.product.allowsDecimal),
              decoration: InputDecoration(
                labelText: 'Cantidad',
                errorText: quantity == null ? (widget.product.allowsDecimal ? 'Cantidad inválida' : 'Solo números enteros') : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.outlined(onPressed: () => _step(1), icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 12),
        if (price != null) ...[
          Text(
            '${money(price.unitPrice)} c/u${price.tier != null ? ' · precio por volumen' : ''}  ·  Total ${money(quantity! * price.unitPrice)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          short ? 'Existencias insuficientes: disponibles $inPresentation × ${_presentation.name}. Puedes agregarlo igual.' : 'Disponibles: $inPresentation × ${_presentation.name}',
          style: TextStyle(fontSize: 13, color: short ? AppColors.amber : AppColors.muted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: quantity == null ? null : () => Navigator.pop<PickedProduct>(context, (product: widget.product, presentation: _presentation, quantity: quantity)),
          child: Text(widget.initial == null ? 'Agregar al pedido' : 'Actualizar cantidad'),
        ),
      ]),
    );
  }
}
