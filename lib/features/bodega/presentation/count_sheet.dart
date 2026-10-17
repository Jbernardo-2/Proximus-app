import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../preventa/data/preventa_models.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/bodega_providers.dart';
import '../application/count_actions.dart';
import '../data/product_counts.dart';
import '../data/warehouse_catalog.dart';

/// Count one product. The system stock is not shown while counting, so it does not
/// steer the count; the difference shows once it is recorded.
Future<bool?> openCountSheet(BuildContext context, WarehouseProduct item) =>
    showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => CountSheet(item: item));

class CountSheet extends ConsumerStatefulWidget {
  const CountSheet({super.key, required this.item});

  final WarehouseProduct item;

  @override
  ConsumerState<CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends ConsumerState<CountSheet> {
  late final Map<String, TextEditingController> _fields;
  final _notes = TextEditingController();
  String? _warehouseId;
  bool _saving = false;

  /// Largest first: a keeper counts boxes, then the loose units.
  List<LocalPresentation> get _presentations => [
    for (final presentation in widget.item.product.presentations)
      if (presentation.isActive) presentation,
  ]..sort((a, b) => b.conversionFactor.compareTo(a.conversionFactor));

  @override
  void initState() {
    super.initState();
    _fields = {for (final presentation in widget.item.product.presentations) presentation.id: TextEditingController()};
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  DecimalValue? _value(String presentationId) {
    final text = _fields[presentationId]!.text.trim();
    if (text.isEmpty) return null;
    try {
      return DecimalValue.parse(text);
    } on FormatException {
      return null;
    }
  }

  String? _error(LocalPresentation presentation) {
    final text = _fields[presentation.id]!.text.trim();
    if (text.isEmpty) return null;
    final value = _value(presentation.id);
    if (value == null) return 'No válida';
    // Loose units may be fractional when the product allows it; boxes are whole.
    if (value.scale > 0 && !(widget.item.product.allowsDecimal && presentation.isBase)) return 'Solo enteros';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.item.product;
    final unit = product.baseUnit ?? 'u';
    final warehouses = ref.watch(warehouseNamesProvider);
    final warehouseId = _warehouseId ?? ref.watch(manifestProvider).value?.defaultWarehouse?['id']?.toString() ?? warehouses.keys.firstOrNull;
    final presentations = _presentations;
    final total = countedTotal(presentations, {for (final presentation in presentations) presentation.id: _value(presentation.id)});
    final valid = total != null && presentations.every((presentation) => _error(presentation) == null);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ProductImage(productId: product.id, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(product.sku, style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
          ]),
          if (warehouses.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: warehouseId,
              decoration: const InputDecoration(labelText: 'Bodega'),
              items: [for (final warehouse in warehouses.entries) DropdownMenuItem(value: warehouse.key, child: Text(warehouse.value))],
              onChanged: (value) => setState(() => _warehouseId = value),
            ),
          ],
          const SizedBox(height: 12),
          const Text('¿Cuánto hay?', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final presentation in presentations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: Text(
                    presentation.isBase ? '${presentation.name} ($unit)' : '${presentation.name} (${presentation.conversionFactor} $unit)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _fields[presentation.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    textAlign: TextAlign.end,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(hintText: '0', errorText: _error(presentation), isDense: true),
                  ),
                ),
              ]),
            ),
          Text(
            total == null ? 'Escribe lo contado; deja en blanco lo que no aplique.' : 'Total contado: $total $unit',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: total == null ? AppColors.muted : AppColors.ink),
          ),
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLength: 500, decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Ejemplo: dos bolsas rotas')),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: !valid || warehouseId == null || _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    final navigator = Navigator.of(context);
                    await ref.read(countActionsProvider).record(productId: product.id, productName: product.name, warehouseId: warehouseId, counted: total, notes: _notes.text);
                    navigator.pop(true);
                  },
            label: const Text('Registrar conteo'),
          ),
        ]),
      ),
    );
  }
}
