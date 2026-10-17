import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decimal_value.dart';
import '../application/catalog_admin.dart';
import '../data/catalog_models.dart';
import 'option_field.dart';
import 'product_form_screen.dart' show moneyInput;

/// Who sells this product to us, for which presentation and at what cost.
Future<void> openSupplierLinkSheet(BuildContext context, ProductData product, {SupplierLinkData? link}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _SupplierLinkSheet(product: product, link: link),
);

class _SupplierLinkSheet extends ConsumerStatefulWidget {
  const _SupplierLinkSheet({required this.product, this.link});

  final ProductData product;
  final SupplierLinkData? link;

  @override
  ConsumerState<_SupplierLinkSheet> createState() => _SupplierLinkSheetState();
}

class _SupplierLinkSheetState extends ConsumerState<_SupplierLinkSheet> {
  late CatalogOption? _supplier = widget.link?.supplier;
  late String? _presentationId = widget.link?.presentationId ?? widget.product.presentations.where((presentation) => presentation.isPurchasable).firstOrNull?.id;
  late final _sku = TextEditingController(text: widget.link?.supplierSku);
  late final _cost = TextEditingController(text: widget.link?.costPrice.toString());
  late final _notes = TextEditingController(text: widget.link?.notes);
  late bool _preferred = widget.link?.isPreferred ?? widget.product.suppliers.isEmpty;
  late bool _active = widget.link?.isActive ?? true;
  bool _saving = false;
  String? _refusal;

  @override
  void dispose() {
    for (final field in [_sku, _cost, _notes]) {
      field.dispose();
    }
    super.dispose();
  }

  bool get _costValid {
    try {
      DecimalValue.parse(_cost.text.trim());
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _supplier != null && _presentationId != null && _costValid;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.link == null ? 'Agregar proveedor' : 'Editar proveedor', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          OptionField(kind: OptionKind.supplier, value: _supplier, enabled: widget.link == null, onChanged: (value) => setState(() => _supplier = value)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _presentationId,
            decoration: const InputDecoration(labelText: 'Presentación que compra *'),
            items: [for (final presentation in widget.product.presentations) DropdownMenuItem(value: presentation.id, child: Text(presentation.name))],
            onChanged: (value) => setState(() => _presentationId = value),
          ),
          TextField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: moneyInput, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Costo *', prefixText: 'L ')),
          TextField(controller: _sku, maxLength: 100, decoration: const InputDecoration(labelText: 'Código del proveedor (opcional)')),
          TextField(controller: _notes, maxLength: 2000, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Proveedor preferido'), value: _preferred, onChanged: (value) => setState(() => _preferred = value)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: _active, onChanged: (value) => setState(() => _active = value)),
          if (_refusal != null) Refusal(_refusal!),
          FilledButton(
            onPressed: !valid || _saving
                ? null
                : () async {
                    setState(() {
                      _saving = true;
                      _refusal = null;
                    });
                    final refusal = await trySave(() => ref.read(catalogAdminProvider).saveSupplierLink(widget.product.id, widget.link?.id, {
                      'supplier_id': _supplier!.id,
                      'product_presentation_id': _presentationId,
                      'supplier_sku': _sku.text.trim().isEmpty ? null : _sku.text.trim(),
                      'cost_price': _cost.text.trim(),
                      'is_preferred': _preferred,
                      'is_active': _active,
                      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                    }));
                    if (!context.mounted) return;
                    if (refusal == null) {
                      Navigator.pop(context);
                    } else {
                      setState(() {
                        _saving = false;
                        _refusal = refusal;
                      });
                    }
                  },
            child: Text(_saving ? 'Guardando…' : 'Guardar'),
          ),
        ]),
      ),
    );
  }
}
