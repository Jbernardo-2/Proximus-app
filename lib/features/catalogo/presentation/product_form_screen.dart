import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/decimal_value.dart';
import '../../bodega/presentation/barcode_scanner_screen.dart';
import '../../bodega/presentation/warehouse_run_screen.dart' show BottomAction;
import '../application/catalog_admin.dart';
import '../data/catalog_models.dart';
import 'option_field.dart';

final moneyInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

/// The product's own data. A new product also gets its first presentation and price;
/// the rest of the presentations, prices and suppliers are added on its page.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.product, this.barcode});

  /// Null to create one.
  final ProductData? product;

  /// A scanned code for the new product's first presentation, also offered as its SKU.
  final String? barcode;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  late final _name = TextEditingController(text: widget.product?.name);
  late final _sku = TextEditingController(text: widget.product?.sku);
  late final _description = TextEditingController(text: widget.product?.description);
  final _baseName = TextEditingController(text: 'Unidad');
  late final _barcode = TextEditingController(text: widget.barcode);
  final _price = TextEditingController();
  late CatalogOption? _category = widget.product?.category;
  late CatalogOption? _brand = widget.product?.brand;
  late CatalogOption? _unit = widget.product?.baseUnit;
  late bool _decimals = widget.product?.allowsDecimal ?? false;
  late bool _lots = widget.product?.tracksLots ?? false;
  late bool _expiry = widget.product?.tracksExpiration ?? false;
  late bool _active = widget.product?.isActive ?? true;
  bool _sellable = true;
  bool _purchasable = true;
  bool _saving = false;
  String? _refusal;

  bool get _creating => widget.product == null;

  @override
  void dispose() {
    for (final field in [_name, _sku, _description, _baseName, _barcode, _price]) {
      field.dispose();
    }
    super.dispose();
  }

  bool get _priceValid {
    try {
      DecimalValue.parse(_price.text.trim());
      return true;
    } on FormatException {
      return false;
    }
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _sku.text.trim().isNotEmpty &&
      _category != null &&
      _unit != null &&
      (!_creating || (_baseName.text.trim().isNotEmpty && _priceValid));

  Future<void> _scanInto(TextEditingController field) async {
    final code = await scanBarcode(context);
    if (code != null) setState(() => field.text = code);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _refusal = null;
    });
    final admin = ref.read(catalogAdminProvider);
    final payload = {
      'name': _name.text.trim(),
      'sku': _sku.text.trim(),
      'category_id': _category!.id,
      'brand_id': _brand?.id,
      'base_unit_id': _unit!.id,
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'allows_decimal': _decimals,
      'tracks_lots': _lots,
      'tracks_expiration': _expiry,
      'is_active': _active,
      if (_creating) ...{
        'base_presentation_name': _baseName.text.trim(),
        'base_barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        'base_sale_price': _price.text.trim(),
        'base_is_sellable': _sellable,
        'base_is_purchasable': _purchasable,
      },
    };
    String? id;
    final refusal = await trySave(() async {
      if (_creating) {
        id = await admin.createProduct(payload);
      } else {
        await admin.updateProduct(widget.product!.id, payload);
      }
    });
    if (!mounted) return;
    if (refusal != null) {
      setState(() {
        _saving = false;
        _refusal = refusal;
      });
      return;
    }
    if (_creating) {
      // On to its page, where the photo, more presentations and suppliers are added.
      context.pushReplacement('/catalog/$id');
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gap = const SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: Text(_creating ? 'Nuevo producto' : 'Editar producto')),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(controller: _name, maxLength: 180, textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ejemplo: Arroz Precioso 1 lb')),
            TextField(
              controller: _sku,
              maxLength: 80,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Código interno (SKU) *',
                helperText: 'Escríbelo o toma el código de barras del producto.',
                suffixIcon: IconButton(tooltip: 'Escanear', icon: const Icon(Icons.qr_code_scanner), onPressed: () => _scanInto(_sku)),
              ),
            ),
            if (_creating && _barcode.text.trim().isNotEmpty && _sku.text.trim() != _barcode.text.trim())
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: () => setState(() => _sku.text = _barcode.text.trim()), icon: const Icon(Icons.content_copy, size: 18), label: const Text('Usar el código de barras')),
              ),
            gap,
            OptionField(kind: OptionKind.category, value: _category, onChanged: (value) => setState(() => _category = value)),
            gap,
            OptionField(kind: OptionKind.brand, value: _brand, required: false, onChanged: (value) => setState(() => _brand = value)),
            gap,
            OptionField(kind: OptionKind.unit, value: _unit, onChanged: (value) => setState(() => _unit = value)),
            gap,
            TextField(controller: _description, maxLength: 4000, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Acepta cantidades con decimales'), value: _decimals, onChanged: (value) => setState(() => _decimals = value)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Lleva número de lote'), value: _lots, onChanged: (value) => setState(() => _lots = value)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Lleva fecha de vencimiento'), value: _expiry, onChanged: (value) => setState(() => _expiry = value)),
            if (!_creating) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), subtitle: const Text('Inactivo deja de venderse y de aparecer en los teléfonos.'), value: _active, onChanged: (value) => setState(() => _active = value)),
            if (_creating) ...[
              const SizedBox(height: 8),
              Text('Primera presentación', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Text('La unidad en que se cuenta el producto; cajas y fardos se agregan después.'),
              gap,
              TextField(controller: _baseName, maxLength: 120, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nombre *')),
              TextField(
                controller: _barcode,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Código de barras (opcional)',
                  suffixIcon: IconButton(tooltip: 'Escanear', icon: const Icon(Icons.qr_code_scanner), onPressed: () => _scanInto(_barcode)),
                ),
              ),
              TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: moneyInput, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Precio de venta *', prefixText: 'L ')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Se vende'), value: _sellable, onChanged: (value) => setState(() => _sellable = value)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Se compra'), value: _purchasable, onChanged: (value) => setState(() => _purchasable = value)),
            ],
            if (_refusal != null) Refusal(_refusal!),
          ]),
        ),
        BottomAction(
          child: FilledButton(onPressed: !_valid || _saving ? null : _save, child: Text(_saving ? 'Guardando…' : _creating ? 'Crear producto' : 'Guardar cambios')),
        ),
      ]),
    );
  }
}
