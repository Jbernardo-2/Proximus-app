import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../../core/location_capture.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';
import '../data/outcome_draft.dart';

/// Reasons the driver picks; damaged and missing are set by the server from the quantities.
const _automaticReasons = {'stock_shortage', 'damaged_goods'};

/// Records what was left at the customer's. Everything delivered is one tap; anything
/// else is per product, with what was not delivered marked as returned, damaged or missing.
class DeliveryOutcomeScreen extends ConsumerStatefulWidget {
  const DeliveryOutcomeScreen({super.key, required this.runId, required this.stopId});

  final String runId;
  final String stopId;

  @override
  ConsumerState<DeliveryOutcomeScreen> createState() => _DeliveryOutcomeScreenState();
}

class _DeliveryOutcomeScreenState extends ConsumerState<DeliveryOutcomeScreen> {
  late final LocationSession _location = ref.read(locationServiceProvider).start();
  final _receiver = TextEditingController();
  final _notes = TextEditingController();
  OutcomeDraft? _draft;
  bool _saving = false;

  @override
  void dispose() {
    _receiver.dispose();
    _notes.dispose();
    super.dispose();
  }

  OutcomeDraft _start(LocalDeliveryStop stop) {
    final products = {for (final product in ref.read(productsProvider)) product.id: product};
    final decimals = {
      for (final item in stop.items)
        if ((products[item.productId]?.allowsDecimal ?? false) && (products[item.productId]?.presentations.any((p) => p.id == item.presentationId && p.isBase) ?? false)) item.id,
    };
    _receiver.text = stop.customer?.contactName ?? '';
    return OutcomeDraft.start(stop, decimalItems: decimals, receiverName: _receiver.text);
  }

  void _update(OutcomeDraft Function(OutcomeDraft draft) change) => setState(() => _draft = change(_draft!));

  Future<void> _editQuantity(OutcomeLine line) async {
    final value = await showDialog<DecimalValue>(
      context: context,
      builder: (context) => _QuantityDialog(line: line),
    );
    if (value != null && mounted) _update((draft) => draft.withDelivered(line.item.id, value));
  }

  Future<void> _save(LocalDeliveryRun run, LocalDeliveryStop stop, Map<String, String> reasons) async {
    setState(() => _saving = true);
    try {
      final draft = _draft!;
      await ref.read(deliveryActionsProvider).recordOutcome(run, stop, draft, location: _location, reasonLabel: reasons[draft.reason]);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(draft.anyDelivered ? 'Entrega guardada. Ahora registra el cobro.' : 'Guardado: no se entregó a ${stop.customerName}.')));
    } catch (error, stack) {
      debugPrint('No se pudo guardar la entrega: $error\n$stack');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(deliveryRunProvider(widget.runId));
    final stop = run?.stops.where((item) => item.id == widget.stopId).firstOrNull;
    if (run == null || stop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Registrar entrega')),
        body: const Center(child: Text('Esta parada ya no está en el teléfono.')),
      );
    }
    final draft = _draft ??= _start(stop);
    final reasons = {
      for (final option in ref.watch(manifestProvider).value?.options('delivery_outcome_reasons') ?? const <({String value, String label})>[])
        if (!_automaticReasons.contains(option.value)) option.value: option.label,
    };
    final problems = draft.problems();

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar entrega')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(stop.customerName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if (!run.hasLeft) const Text('También se marcará la salida a ruta.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Choice(selected: draft.allDelivered, icon: Icons.check_circle_outline, label: 'Todo entregado', onTap: () => _update((draft) => draft.deliverAll().withReason(null))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Choice(selected: !draft.anyDelivered, icon: Icons.block, label: 'No se entregó', onTap: () => _update((draft) => draft.deliverNothing())),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final line in draft.lines)
            _LineCard(
              line: line,
              onStep: (delta) => _update((draft) => draft.withDelivered(line.item.id, line.delivered + DecimalValue.parse('$delta'))),
              onEdit: () => _editQuantity(line),
              onLeftover: (leftover) => _update((draft) => draft.withLeftover(line.item.id, leftover)),
            ),
          if (draft.needsReason) ...[
            const SizedBox(height: 8),
            const Text('¿Por qué se devolvió?', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in reasons.entries) ChoiceChip(label: Text(entry.value), selected: draft.reason == entry.key, onSelected: (_) => _update((draft) => draft.withReason(entry.key))),
              ],
            ),
          ],
          if (draft.anyDelivered) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _receiver,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: '¿Quién recibió?'),
              onChanged: (value) => _update((draft) => draft.withReceiver(value)),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            onChanged: (value) => _update((draft) => draft.withNotes(value)),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (problems.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    problems.first,
                    style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600),
                  ),
                ),
              Row(
                children: [
                  const Text('Entregado', style: TextStyle(color: AppColors.muted)),
                  const Spacer(),
                  Text(money(draft.deliveredTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: problems.isNotEmpty || _saving ? null : () => _save(run, stop, reasons),
                child: _saving ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar entrega'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.icon, required this.label, required this.onTap});

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      backgroundColor: selected ? AppColors.brand.withValues(alpha: 0.10) : null,
      foregroundColor: selected ? AppColors.brand : AppColors.ink,
      side: BorderSide(color: selected ? AppColors.brand : const Color(0xFFE7E5E4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 20),
    label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
  );
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.onStep, required this.onEdit, required this.onLeftover});

  final OutcomeLine line;
  final void Function(int delta) onStep;
  final VoidCallback onEdit;
  final void Function(Leftover leftover) onLeftover;

  @override
  Widget build(BuildContext context) {
    final item = line.item;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductImage(productId: item.productId, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('Cargado ${item.loaded} × ${item.presentationName} · ${money(item.unitPrice)} c/u', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Entregado', style: TextStyle(color: AppColors.muted)),
                const Spacer(),
                IconButton.outlined(onPressed: line.delivered.isZero ? null : () => onStep(-1), icon: const Icon(Icons.remove)),
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 56),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    alignment: Alignment.center,
                    child: Text('${line.delivered}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ),
                IconButton.outlined(onPressed: line.isComplete ? null : () => onStep(1), icon: const Icon(Icons.add)),
              ],
            ),
            if (!line.isComplete) ...[
              const SizedBox(height: 8),
              Text('${line.rest} sin entregar:', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [for (final leftover in Leftover.values) ChoiceChip(label: Text(leftover.label), selected: line.leftover == leftover, onSelected: (_) => onLeftover(leftover))],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Owns its text field, so it is released only after the dialog finished closing.
class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.line});

  final OutcomeLine line;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final controller = TextEditingController(text: widget.line.delivered.toString());

  OutcomeLine get line => widget.line;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(line.item.productName),
    content: TextField(
      controller: controller,
      autofocus: true,
      keyboardType: TextInputType.numberWithOptions(decimal: line.allowsDecimal),
      decoration: InputDecoration(labelText: 'Entregado', helperText: 'Cargado ${line.item.loaded}'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(
        onPressed: () {
          final text = controller.text.trim().replaceAll(',', '.');
          final value = RegExp(r'^\d+(\.\d+)?$').hasMatch(text) ? DecimalValue.parse(text) : null;
          Navigator.pop(context, value);
        },
        child: const Text('Aplicar'),
      ),
    ],
  );
}
