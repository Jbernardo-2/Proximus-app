import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../../core/payment_split.dart';
import '../data/payment_draft.dart' show parseAmount;

/// The ways a total is paid, so nobody has to do the subtraction in their head: every
/// amount can be typed, two lines balance each other, and with more each line can
/// absorb what is missing. Cash can take what the customer handed over to show the change.
class PaymentSplitEditor extends StatefulWidget {
  const PaymentSplitEditor({
    super.key,
    required this.total,
    required this.lines,
    required this.methods,
    required this.onChanged,
    this.requiringReference = const {},
    this.withoutReference = const {'credit'},
    this.maxLines = 4,
  });

  final DecimalValue total;
  final List<SplitLine> lines;
  final List<({String value, String label})> methods;
  final ValueChanged<List<SplitLine>> onChanged;
  final Set<String> requiringReference;

  /// Methods that never carry a reference (credit).
  final Set<String> withoutReference;
  final int maxLines;

  @override
  State<PaymentSplitEditor> createState() => _PaymentSplitEditorState();
}

class _PaymentSplitEditorState extends State<PaymentSplitEditor> {
  final List<TextEditingController> _amounts = [];
  final List<FocusNode> _focus = [];
  final List<TextEditingController> _references = [];
  final List<TextEditingController> _received = [];

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PaymentSplitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    for (final controller in [..._amounts, ..._references, ..._received]) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  /// Keeps one field per line and shows amounts changed elsewhere (the other line
  /// balancing, "Completar"), without touching the field being typed in.
  void _sync() {
    while (_amounts.length > widget.lines.length) {
      _release(_amounts.removeLast(), _focus.removeLast(), _references.removeLast(), _received.removeLast());
    }
    while (_amounts.length < widget.lines.length) {
      final line = widget.lines[_amounts.length];
      _amounts.add(TextEditingController(text: line.amount.toFixed(2)));
      _focus.add(FocusNode());
      _references.add(TextEditingController(text: line.reference ?? ''));
      _received.add(TextEditingController());
    }
    for (var index = 0; index < widget.lines.length; index++) {
      if (_focus[index].hasFocus) continue;
      if (parseAmount(_amounts[index].text) != widget.lines[index].amount) _amounts[index].text = widget.lines[index].amount.toFixed(2);
    }
  }

  /// Fields of a removed line are still on screen until the next frame: release them after it.
  void _release(TextEditingController amount, FocusNode focus, TextEditingController reference, TextEditingController received) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      amount.dispose();
      focus.dispose();
      reference.dispose();
      received.dispose();
    });
  }

  void _change(List<SplitLine> lines) => widget.onChanged(lines);

  void _remove(int index) {
    // Shift the local fields with the line so each keeps its own text.
    _release(_amounts.removeAt(index), _focus.removeAt(index), _references.removeAt(index), _received.removeAt(index));
    _change(splitRemove(widget.lines, index, widget.total));
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final missing = widget.total - splitAssigned(lines);
    final used = lines.map((line) => line.method).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < lines.length; index++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('method-$index-${lines.length}'),
                          initialValue: lines[index].method,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Método', isDense: true),
                          items: [
                            for (final method in widget.methods)
                              DropdownMenuItem(
                                value: method.value,
                                child: Text(method.label, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _change([...lines]..[index] = (method: value, amount: lines[index].amount, reference: lines[index].reference));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: TextField(
                          controller: _amounts[index],
                          focusNode: _focus[index],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(labelText: 'Monto', prefixText: 'L ', isDense: true),
                          onChanged: (value) => _change(splitEdit(lines, index, parseAmount(value) ?? DecimalValue.zero, widget.total)),
                        ),
                      ),
                      if (lines.length > 1) IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close, size: 20), onPressed: () => _remove(index)) else const SizedBox(width: 8),
                    ],
                  ),
                  if (lines.length > 2 && !missing.isZero)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () {
                          _focus[index].unfocus();
                          _change(splitComplete(lines, index, widget.total));
                        },
                        child: Text(missing.isNegative ? 'Ajustar (−${money(-missing)})' : 'Completar (+${money(missing)})'),
                      ),
                    ),
                  if (!widget.withoutReference.contains(lines[index].method)) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextField(
                        controller: _references[index],
                        decoration: InputDecoration(labelText: widget.requiringReference.contains(lines[index].method) ? 'Referencia (obligatoria)' : 'Referencia (opcional)', isDense: true),
                        onChanged: (value) => _change([...lines]..[index] = (method: lines[index].method, amount: lines[index].amount, reference: value)),
                      ),
                    ),
                  ],
                  if (lines[index].method == 'cash') _CashChange(controller: _received[index], amount: lines[index].amount, onChanged: () => setState(() {})),
                ],
              ),
            ),
          ),
        if (lines.length < widget.maxLines)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                final next =
                    widget.methods.where((method) => !used.contains(method.value) && !widget.withoutReference.contains(method.value)).firstOrNull?.value ??
                    widget.methods.where((method) => !used.contains(method.value)).firstOrNull?.value ??
                    'other';
                _change(splitAdd(lines, next, widget.total));
              },
              icon: const Icon(Icons.add),
              label: Text(missing.isZero || missing.isNegative ? 'Combinar con otra forma de pago' : 'Agregar forma de pago (${money(missing)})'),
            ),
          ),
      ],
    );
  }
}

/// Optional, only on screen: what the customer handed over and the change to give back.
class _CashChange extends StatelessWidget {
  const _CashChange({required this.controller, required this.amount, required this.onChanged});

  final TextEditingController controller;
  final DecimalValue amount;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final received = parseAmount(controller.text);
    final change = received == null ? null : cashChange(received, amount);
    final short = received != null && received.compareTo(amount) < 0;
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Recibido (opcional)', prefixText: 'L ', isDense: true),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 12),
          if (change != null)
            Text(
              'Vuelto ${money(change)}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand),
            )
          else if (short)
            Text(
              'Faltan ${money(amount - received)}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.amber),
            ),
        ],
      ),
    );
  }
}

/// Always in sight at the bottom: how much is still to be assigned, over, or done.
class SplitRemainingBar extends StatelessWidget {
  const SplitRemainingBar({super.key, required this.total, required this.lines});

  final DecimalValue total;
  final List<SplitLine> lines;

  @override
  Widget build(BuildContext context) {
    final assigned = splitAssigned(lines);
    final missing = total - assigned;
    final (label, color, icon) = missing.isZero
        ? ('Completo', AppColors.brand, Icons.check_circle)
        : missing.isNegative
        ? ('Sobran ${money(-missing)}', AppColors.danger, Icons.error_outline)
        : ('Falta distribuir ${money(missing)}', AppColors.amber, Icons.pending_outlined);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ),
          Text('${money(assigned)} de ${money(total)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}
