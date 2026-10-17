import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../preventa/data/preventa_models.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/bodega_providers.dart';
import '../application/receipt_actions.dart';
import '../data/receipts.dart';
import '../data/warehouse_catalog.dart';
import 'barcode_scanner_screen.dart';
import 'product_search_screen.dart';
import 'warehouse_run_screen.dart' show BottomAction;

final _day = DateFormat("EEEE d 'de' MMMM", 'es');

/// A whole entry of merchandise: its kind, where it comes from and its lines, posted at once.
class NewReceiptScreen extends ConsumerStatefulWidget {
  const NewReceiptScreen({super.key});

  @override
  ConsumerState<NewReceiptScreen> createState() => _NewReceiptScreenState();
}

class _NewReceiptScreenState extends ConsumerState<NewReceiptScreen> {
  ReceiptType _type = ReceiptType.receipt;
  String? _supplierId;
  String? _warehouseId;
  DateTime _date = DateTime.now();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final _lines = <ReceiptLine>[];
  bool _saving = false;
  String? _refusal;

  @override
  void dispose() {
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addLine({WarehouseProduct? item, LocalPresentation? presentation}) async {
    item ??= await Navigator.of(context).push<WarehouseProduct>(
      MaterialPageRoute(builder: (context) => ProductSearchScreen(title: 'Agregar producto', onPick: (item) => Navigator.pop(context, item))),
    );
    if (item == null || !mounted) return;
    final line = await showModalBottomSheet<ReceiptLine>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LineSheet(item: item!, type: _type, presentation: presentation),
    );
    if (line == null) return;
    setState(() {
      final same = _lines.indexWhere((existing) => existing.key == line.key);
      // One line per presentation and lot, as the server keeps them: a repeat adds up.
      if (same >= 0) {
        final existing = _lines[same];
        _lines[same] = ReceiptLine(
          product: line.product,
          presentation: line.presentation,
          quantity: existing.quantity + line.quantity,
          unitCost: line.unitCost ?? existing.unitCost,
          lotNumber: line.lotNumber,
          expirationDate: line.expirationDate ?? existing.expirationDate,
        );
      } else {
        _lines.add(line);
      }
    });
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final item = productForBarcode(ref.read(warehouseProductsProvider), code);
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('El código $code no está registrado. Búscalo por nombre.')));
      return;
    }
    await _addLine(item: item, presentation: item.presentationWithBarcode(code.trim()));
  }

  Future<void> _post(String warehouseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aplicar ${_type.label.toLowerCase()}'),
        content: Text('${_lines.length} ${_lines.length == 1 ? 'línea' : 'líneas'}. La existencia sube en este momento y el documento ya no se puede editar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _refusal = null;
    });
    try {
      final posted = await ref.read(receiptActionsProvider).post(receiptPayload(
        type: _type,
        warehouseId: warehouseId,
        occurredOn: _date,
        lines: _lines,
        supplierId: _supplierId,
        reference: _reference.text,
        notes: _notes.text,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${posted.number} aplicada: la existencia ya subió.')));
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _refusal = error.isNetwork ? 'Sin conexión: no se guardó nada. Revisa la señal e intenta de nuevo.' : error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdjust = ref.watch(sessionProvider).value?.can('inventory:adjust') ?? false;
    final suppliers = ref.watch(suppliersProvider);
    final warehouses = ref.watch(warehouseNamesProvider);
    final warehouseId = _warehouseId ?? ref.watch(manifestProvider).value?.defaultWarehouse?['id']?.toString() ?? warehouses.keys.firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva entrada'),
        actions: [IconButton(tooltip: 'Escanear producto', icon: const Icon(Icons.qr_code_scanner), onPressed: _saving ? null : _scan)],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              DropdownButtonFormField<ReceiptType>(
                isExpanded: true,
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final type in ReceiptType.values)
                    if (!type.needsAdjustPermission || canAdjust) DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: _saving ? null : (type) => setState(() => _type = type ?? _type),
              ),
              if (_type.hasSupplier) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _supplierId,
                  decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sin proveedor')),
                    for (final supplier in suppliers.entries) DropdownMenuItem(value: supplier.key, child: Text(supplier.value)),
                  ],
                  onChanged: _saving ? null : (value) => setState(() => _supplierId = value),
                ),
              ],
              if (warehouses.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: warehouseId,
                  decoration: const InputDecoration(labelText: 'Bodega'),
                  items: [for (final warehouse in warehouses.entries) DropdownMenuItem(value: warehouse.key, child: Text(warehouse.value))],
                  onChanged: _saving ? null : (value) => setState(() => _warehouseId = value),
                ),
              ],
              const SizedBox(height: 12),
              TextField(controller: _reference, maxLength: 120, decoration: InputDecoration(labelText: _type.hasSupplier ? 'Factura o referencia (opcional)' : 'Referencia (opcional)')),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text('Fecha: ${_day.format(_date)}'),
                onPressed: _saving
                    ? null
                    : () async {
                        final today = DateTime.now();
                        final picked = await showDatePicker(context: context, initialDate: _date, firstDate: today.subtract(const Duration(days: 60)), lastDate: today);
                        if (picked != null) setState(() => _date = picked);
                      },
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text('${_lines.length} ${_lines.length == 1 ? 'línea' : 'líneas'}', style: const TextStyle(fontWeight: FontWeight.w700))),
                TextButton.icon(onPressed: _saving ? null : () => _addLine(), icon: const Icon(Icons.add), label: const Text('Agregar producto')),
              ]),
              if (_lines.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Escanea o busca los productos que entran.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))),
              for (final line in _lines)
                Card(
                  child: ListTile(
                    leading: ProductImage(productId: line.product.id, size: 44),
                    title: Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      '${line.quantity} ${line.presentation.name}',
                      if (!line.presentation.isBase) '= ${line.baseQuantity} ${line.product.baseUnit ?? 'u'}',
                      if (line.unitCost != null) 'costo ${money(line.unitCost!)}',
                      if (line.lotNumber != null) 'lote ${line.lotNumber}',
                      if (line.expirationDate != null) 'vence ${DateFormat('d/M/yyyy').format(line.expirationDate!)}',
                    ].join(' · ')),
                    trailing: IconButton(tooltip: 'Quitar', icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger), onPressed: _saving ? null : () => setState(() => _lines.remove(line))),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(controller: _notes, maxLength: 2000, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
              if (_refusal != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Text(_refusal!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        BottomAction(
          child: FilledButton.icon(
            onPressed: _lines.isEmpty || warehouseId == null || _saving ? null : () => _post(warehouseId),
            icon: const Icon(Icons.move_to_inbox_outlined),
            label: Text(_saving ? 'Aplicando…' : 'Aplicar entrada'),
          ),
        ),
      ]),
    );
  }
}

/// How many of which presentation, and the cost, lot and expiry when they apply.
class _LineSheet extends StatefulWidget {
  const _LineSheet({required this.item, required this.type, this.presentation});

  final WarehouseProduct item;
  final ReceiptType type;
  final LocalPresentation? presentation;

  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  late LocalPresentation _presentation;
  final _quantity = TextEditingController();
  final _cost = TextEditingController();
  final _lot = TextEditingController();
  DateTime? _expiry;

  List<LocalPresentation> get _presentations => [
    for (final presentation in widget.item.product.presentations)
      if (presentation.isActive) presentation,
  ]..sort((a, b) => b.conversionFactor.compareTo(a.conversionFactor));

  @override
  void initState() {
    super.initState();
    _presentation = widget.presentation ?? _presentations.first;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    _lot.dispose();
    super.dispose();
  }

  DecimalValue? _parse(TextEditingController field) {
    try {
      return DecimalValue.parse(field.text.trim());
    } on FormatException {
      return null;
    }
  }

  String? get _quantityError {
    if (_quantity.text.trim().isEmpty) return null;
    final value = _parse(_quantity);
    if (value == null || value.isZero) return 'Cantidad no válida';
    if (value.scale > 0 && !(widget.item.product.allowsDecimal && _presentation.isBase)) return 'Solo enteros';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.item.product;
    final quantity = _parse(_quantity);
    final cost = _cost.text.trim().isEmpty ? null : _parse(_cost);
    final costValid = _cost.text.trim().isEmpty || cost != null;
    final lotOk = !product.tracksLots || _lot.text.trim().isNotEmpty;
    final expiryOk = !product.tracksExpiration || _expiry != null;
    final valid = quantity != null && !quantity.isZero && _quantityError == null && costValid && lotOk && expiryOk;
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ProductImage(productId: product.id, size: 48),
            const SizedBox(width: 12),
            Expanded(child: Text(product.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<LocalPresentation>(
            isExpanded: true,
            initialValue: _presentation,
            decoration: const InputDecoration(labelText: 'Presentación'),
            items: [
              for (final presentation in _presentations)
                DropdownMenuItem(value: presentation, child: Text(presentation.isBase ? presentation.name : '${presentation.name} (${presentation.conversionFactor} ${product.baseUnit ?? 'u'})')),
            ],
            onChanged: (value) => setState(() => _presentation = value ?? _presentation),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantity,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: numbers,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Cantidad', errorText: _quantityError),
          ),
          if (widget.type.hasCost) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: numbers,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Costo por ${_presentation.name.toLowerCase()} (opcional)', prefixText: 'L ', errorText: costValid ? null : 'Costo no válido'),
            ),
          ],
          if (product.tracksLots) ...[
            const SizedBox(height: 12),
            TextField(controller: _lot, maxLength: 100, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Lote *')),
          ],
          if (product.tracksExpiration) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_busy_outlined),
              label: Text(_expiry == null ? 'Fecha de vencimiento *' : 'Vence el ${_day.format(_expiry!)}'),
              onPressed: () async {
                final today = DateTime.now();
                final picked = await showDatePicker(context: context, initialDate: _expiry ?? today.add(const Duration(days: 180)), firstDate: today.subtract(const Duration(days: 365)), lastDate: today.add(const Duration(days: 3650)));
                if (picked != null) setState(() => _expiry = picked);
              },
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: !valid
                ? null
                : () => Navigator.pop(
                    context,
                    ReceiptLine(
                      product: product,
                      presentation: _presentation,
                      quantity: quantity,
                      unitCost: cost,
                      lotNumber: _lot.text.trim().isEmpty ? null : _lot.text.trim(),
                      expirationDate: _expiry,
                    ),
                  ),
            child: const Text('Agregar a la entrada'),
          ),
        ]),
      ),
    );
  }
}
