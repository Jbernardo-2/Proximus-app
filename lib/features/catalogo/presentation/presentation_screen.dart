import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../bodega/presentation/barcode_scanner_screen.dart';
import '../../bodega/presentation/warehouse_run_screen.dart' show BottomAction;
import '../application/catalog_admin.dart';
import '../data/catalog_models.dart';
import 'option_field.dart';
import 'product_form_screen.dart' show moneyInput;

DecimalValue? _parse(String text) {
  try {
    return text.trim().isEmpty ? null : DecimalValue.parse(text.trim());
  } on FormatException {
    return null;
  }
}

/// One presentation (box, bale, dozen…) and its price tiers. The base presentation
/// keeps its factor of 1 and stays active.
class PresentationScreen extends ConsumerStatefulWidget {
  const PresentationScreen({super.key, required this.product, this.presentation});

  final ProductData product;

  /// Null to add one.
  final PresentationData? presentation;

  @override
  ConsumerState<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends ConsumerState<PresentationScreen> {
  late final _name = TextEditingController(text: widget.presentation?.name);
  late final _factor = TextEditingController(text: widget.presentation?.conversionFactor.toString());
  late final _barcode = TextEditingController(text: widget.presentation?.barcode);
  late final _price = TextEditingController(text: widget.presentation?.salePrice.toString());
  late bool _sellable = widget.presentation?.isSellable ?? true;
  late bool _purchasable = widget.presentation?.isPurchasable ?? true;
  late bool _active = widget.presentation?.isActive ?? true;
  bool _saving = false;
  String? _refusal;

  bool get _isBase => widget.presentation?.isBase ?? false;

  @override
  void dispose() {
    for (final field in [_name, _factor, _barcode, _price]) {
      field.dispose();
    }
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && (_parse(_factor.text)?.isZero == false || _isBase) && _parse(_price.text) != null;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _refusal = null;
    });
    final refusal = await trySave(() => ref.read(catalogAdminProvider).savePresentation(widget.product.id, widget.presentation?.id, {
      'name': _name.text.trim(),
      'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      'conversion_factor': _isBase ? '1' : _factor.text.trim(),
      'sale_price': _price.text.trim(),
      'is_sellable': _sellable,
      'is_purchasable': _purchasable,
      'is_active': _isBase || _active,
    }));
    if (!mounted) return;
    if (refusal == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _refusal = refusal;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.product.baseUnit.detail ?? widget.product.baseUnit.name;
    // The tiers shown come fresh from the server after each change.
    final tiers = ref.watch(productDataProvider(widget.product.id)).value?.presentations.where((p) => p.id == widget.presentation?.id).firstOrNull?.tiers ?? widget.presentation?.tiers ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(widget.presentation == null ? 'Nueva presentación' : widget.presentation!.name)),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(controller: _name, maxLength: 120, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ejemplo: Caja x24')),
            TextField(
              controller: _factor,
              enabled: !_isBase,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: moneyInput,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Cuántos $unit trae *', helperText: _isBase ? 'La presentación base siempre es 1.' : null),
            ),
            TextField(
              controller: _barcode,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Código de barras (opcional)',
                suffixIcon: IconButton(
                  tooltip: 'Escanear',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () async {
                    final code = await scanBarcode(context);
                    if (code != null) setState(() => _barcode.text = code);
                  },
                ),
              ),
            ),
            TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: moneyInput, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Precio de venta *', prefixText: 'L ')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Se vende'), value: _sellable, onChanged: (value) => setState(() => _sellable = value)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Se compra'), value: _purchasable, onChanged: (value) => setState(() => _purchasable = value)),
            if (!_isBase) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activa'), value: _active, onChanged: (value) => setState(() => _active = value)),
            if (_refusal != null) Refusal(_refusal!),
            if (widget.presentation != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(child: Text('Escalas de precio', style: TextStyle(fontWeight: FontWeight.w700))),
                TextButton.icon(onPressed: () => _openTier(null), icon: const Icon(Icons.add), label: const Text('Agregar')),
              ]),
              const Text('Precio especial desde cierta cantidad, con fechas opcionales.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              for (final tier in tiers)
                Card(
                  child: ListTile(
                    title: Text('Desde ${tier.minQuantity}${tier.maxQuantity == null ? '' : ' hasta ${tier.maxQuantity}'}', style: TextStyle(fontWeight: FontWeight.w600, color: tier.isActive ? AppColors.ink : AppColors.muted)),
                    subtitle: Text([
                      if (tier.startsAt != null || tier.endsAt != null) '${tier.startsAt == null ? '…' : DateFormat('d/M/yy').format(tier.startsAt!)} – ${tier.endsAt == null ? '…' : DateFormat('d/M/yy').format(tier.endsAt!)}',
                      if (!tier.isActive) 'Inactiva',
                    ].join(' · ')),
                    trailing: Text(money(tier.unitPrice), style: const TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => _openTier(tier),
                  ),
                ),
            ],
          ]),
        ),
        BottomAction(child: FilledButton(onPressed: !_valid || _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar presentación'))),
      ]),
    );
  }

  Future<void> _openTier(PriceTierData? tier) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TierSheet(productId: widget.product.id, presentationId: widget.presentation!.id, tier: tier),
  );
}

class _TierSheet extends ConsumerStatefulWidget {
  const _TierSheet({required this.productId, required this.presentationId, this.tier});

  final String productId;
  final String presentationId;
  final PriceTierData? tier;

  @override
  ConsumerState<_TierSheet> createState() => _TierSheetState();
}

class _TierSheetState extends ConsumerState<_TierSheet> {
  late final _min = TextEditingController(text: widget.tier?.minQuantity.toString());
  late final _max = TextEditingController(text: widget.tier?.maxQuantity?.toString());
  late final _price = TextEditingController(text: widget.tier?.unitPrice.toString());
  late DateTime? _starts = widget.tier?.startsAt;
  late DateTime? _ends = widget.tier?.endsAt;
  late bool _active = widget.tier?.isActive ?? true;
  bool _saving = false;
  String? _refusal;

  @override
  void dispose() {
    for (final field in [_min, _max, _price]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? current) {
    final today = DateTime.now();
    return showDatePicker(context: context, initialDate: current ?? today, firstDate: today.subtract(const Duration(days: 365)), lastDate: today.add(const Duration(days: 730)));
  }

  @override
  Widget build(BuildContext context) {
    final valid = _parse(_min.text)?.isZero == false && _parse(_price.text) != null && (_max.text.trim().isEmpty || _parse(_max.text) != null);
    final date = DateFormat('d MMM yyyy', 'es');
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.tier == null ? 'Nueva escala' : 'Editar escala', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Row(children: [
            Expanded(child: TextField(controller: _min, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: moneyInput, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Desde *'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _max, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: moneyInput, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Hasta (opcional)'))),
          ]),
          TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: moneyInput, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Precio por unidad *', prefixText: 'L ')),
          const SizedBox(height: 8),
          Row(children: [
            // Tap to choose a date; a long press goes back to no limit.
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final picked = await _pick(_starts);
                  if (picked != null) setState(() => _starts = picked);
                },
                onLongPress: () => setState(() => _starts = null),
                child: Text(_starts == null ? 'Desde siempre' : 'Desde ${date.format(_starts!)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final picked = await _pick(_ends);
                  if (picked != null) setState(() => _ends = picked);
                },
                onLongPress: () => setState(() => _ends = null),
                child: Text(_ends == null ? 'Sin fin' : 'Hasta ${date.format(_ends!)}'),
              ),
            ),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activa'), value: _active, onChanged: (value) => setState(() => _active = value)),
          if (_refusal != null) Refusal(_refusal!),
          FilledButton(
            onPressed: !valid || _saving
                ? null
                : () async {
                    setState(() {
                      _saving = true;
                      _refusal = null;
                    });
                    final refusal = await trySave(() => ref.read(catalogAdminProvider).saveTier(widget.productId, widget.presentationId, widget.tier?.id, {
                      'min_quantity': _min.text.trim(),
                      'max_quantity': _max.text.trim().isEmpty ? null : _max.text.trim(),
                      'unit_price': _price.text.trim(),
                      'starts_at': dateText(_starts),
                      'ends_at': dateText(_ends),
                      'is_active': _active,
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
            child: Text(_saving ? 'Guardando…' : 'Guardar escala'),
          ),
        ]),
      ),
    );
  }
}
