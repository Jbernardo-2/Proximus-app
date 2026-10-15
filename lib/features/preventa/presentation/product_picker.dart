import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../data/order_draft.dart';
import '../data/preventa_models.dart';

typedef PickedProduct = ({LocalProduct product, LocalPresentation presentation, DecimalValue quantity});

/// Full-screen catalog search. Returns the product, presentation and quantity chosen.
Future<PickedProduct?> pickProduct(BuildContext context, {DateTime? day}) =>
    Navigator.of(context).push<PickedProduct>(MaterialPageRoute(builder: (_) => ProductPickerScreen(day: day ?? DateTime.now())));

class ProductPickerScreen extends ConsumerStatefulWidget {
  const ProductPickerScreen({super.key, required this.day});

  final DateTime day;

  @override
  ConsumerState<ProductPickerScreen> createState() => _ProductPickerScreenState();
}

class _ProductPickerScreenState extends ConsumerState<ProductPickerScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final terms = _query.toLowerCase().split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
    final products = ref.watch(productsProvider).where((product) {
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
      appBar: AppBar(title: const Text('Agregar producto')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nombre, código o código de barras'),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? Center(child: Text(_query.isEmpty ? 'No hay productos en el teléfono. Sincroniza con señal.' : 'Ningún producto coincide.', style: const TextStyle(color: AppColors.muted)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final available = stock[product.id] ?? DecimalValue.zero;
                    return Card(
                      child: ListTile(
                        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${product.sku} · ${available.isNegative || available.isZero ? 'Sin existencias' : 'Disp. ${available.toFixed(product.allowsDecimal ? 2 : 0)} ${product.baseUnit ?? ''}'}',
                          style: TextStyle(color: available.isNegative || available.isZero ? AppColors.danger : AppColors.muted),
                        ),
                        trailing: const Icon(Icons.add_circle_outline, color: AppColors.brand),
                        onTap: () async {
                          final picked = await showModalBottomSheet<PickedProduct>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (_) => QuantitySheet(product: product, available: available, day: widget.day),
                          );
                          if (picked != null && context.mounted) Navigator.pop(context, picked);
                        },
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
    _presentation = presentations.where((p) => p.id == widget.presentationId).firstOrNull ??
        presentations.where((p) => p.isBase).firstOrNull ??
        presentations.first;
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
        Text(widget.product.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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
