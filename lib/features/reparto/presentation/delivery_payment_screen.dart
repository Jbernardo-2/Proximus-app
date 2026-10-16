import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../../core/location_capture.dart';
import '../../preventa/data/payment_draft.dart' show parseAmount;
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';
import '../data/settlement_draft.dart';
import 'delivery_invoice_screen.dart';

/// Collects what was delivered: one method for everything by default (cash, or credit
/// when the order was on credit), or several combined.
class DeliveryPaymentScreen extends ConsumerStatefulWidget {
  const DeliveryPaymentScreen({super.key, required this.runId, required this.stopId});

  final String runId;
  final String stopId;

  @override
  ConsumerState<DeliveryPaymentScreen> createState() => _DeliveryPaymentScreenState();
}

class _DeliveryPaymentScreenState extends ConsumerState<DeliveryPaymentScreen> {
  late final LocationSession _location = ref.read(locationServiceProvider).start();
  final List<TextEditingController> _amounts = [];
  final List<TextEditingController> _references = [];
  final _creditReason = TextEditingController();
  SettlementDraft? _draft;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [..._amounts, ..._references, _creditReason]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllers(SettlementDraft draft) {
    while (_amounts.length < draft.lines.length) {
      _amounts.add(TextEditingController(text: draft.lines[_amounts.length].amount.toFixed(2)));
      _references.add(TextEditingController());
    }
  }

  void _set(SettlementDraft draft) => setState(() => _draft = draft);

  void _addMethod(List<({String value, String label})> methods) {
    final draft = _draft!;
    final used = draft.lines.map((line) => line.method).toSet();
    final next = methods.where((method) => !used.contains(method.value) && method.value != 'credit').firstOrNull?.value ?? 'other';
    final updated = draft.addMethod(next);
    _syncControllers(updated);
    _amounts.last.text = updated.lines.last.amount.toFixed(2);
    _set(updated);
  }

  void _remove(int index) {
    _amounts.removeAt(index).dispose();
    _references.removeAt(index).dispose();
    final updated = _draft!.removeAt(index);
    if (updated.lines.length == 1) _amounts.single.text = updated.total.toFixed(2);
    _set(updated);
  }

  Future<void> _save(LocalDeliveryRun run, LocalDeliveryStop stop) async {
    setState(() => _saving = true);
    try {
      final invoice = await ref.read(deliveryActionsProvider).recordPayment(run, stop, _draft!, location: _location);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => DeliveryInvoiceScreen(invoice: invoice, justIssued: true)));
    } catch (error, stack) {
      debugPrint('No se pudo registrar el cobro: $error\n$stack');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo registrar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(deliveryRunProvider(widget.runId));
    final stop = run?.stops.where((item) => item.id == widget.stopId).firstOrNull;
    if (run == null || stop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cobrar')),
        body: const Center(child: Text('Esta parada ya no está en el teléfono.')),
      );
    }
    final draft = _draft ??= SettlementDraft.start(stop.balanceDue, credit: stop.isCredit);
    _syncControllers(draft);
    final manifest = ref.watch(manifestProvider).value;
    final methods = manifest?.options('settlement_methods') ?? const [(value: 'cash', label: 'Efectivo'), (value: 'credit', label: 'Crédito')];
    final requiringReference = manifest?.requiringReference('settlement_methods') ?? const <String>{};
    final balance = ref.watch(customerBalancesProvider)[stop.customerId];
    final allowsCredit = balance?.allowsCredit ?? false;
    final available = balance?.available;
    final problems = draft.problems(requiringReference: requiringReference, allowsCredit: allowsCredit, available: available);
    final multiple = draft.lines.length > 1;
    final hasCredit = draft.lines.any((line) => line.isCredit);

    return Scaffold(
      appBar: AppBar(title: Text('Cobrar · ${stop.customerName}', overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total entregado', style: TextStyle(color: AppColors.muted)),
                  Text(money(draft.total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  if (stop.isCredit)
                    const Text(
                      'Pedido a crédito',
                      style: TextStyle(color: Color(0xFF2F6FD0), fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Forma de pago', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (var index = 0; index < draft.lines.length; index++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('method-$index-${draft.lines.length}'),
                            initialValue: draft.lines[index].method,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Método', isDense: true),
                            items: [for (final method in methods) DropdownMenuItem(value: method.value, child: Text(method.label))],
                            onChanged: (value) => _set(draft.updateAt(index, draft.lines[index].copyWith(method: value))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (multiple) ...[
                          SizedBox(
                            width: 112,
                            child: TextField(
                              controller: _amounts[index],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Monto', prefixText: 'L ', isDense: true),
                              onChanged: (value) => _set(draft.updateAt(index, draft.lines[index].copyWith(amount: parseAmount(value) ?? DecimalValue.zero))),
                            ),
                          ),
                          IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close, size: 20), onPressed: () => _remove(index)),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(money(draft.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    if (!draft.lines[index].isCredit) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextField(
                          controller: _references[index],
                          decoration: InputDecoration(labelText: requiringReference.contains(draft.lines[index].method) ? 'Referencia (obligatoria)' : 'Referencia (opcional)', isDense: true),
                          onChanged: (value) => _set(draft.updateAt(index, draft.lines[index].copyWith(reference: value))),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (draft.lines.length < 4) TextButton.icon(onPressed: () => _addMethod(methods), icon: const Icon(Icons.add), label: const Text('Combinar con otra forma de pago')),
          if (hasCredit) ...[
            const SizedBox(height: 8),
            Text(
              !allowsCredit
                  ? 'El cliente no tiene crédito activo. Quedará como excepción para el supervisor.'
                  : 'Crédito disponible: ${money(available == null || available.isNegative ? DecimalValue.zero : available)}',
              style: TextStyle(
                color: allowsCredit && !draft.needsCreditReason(allowsCredit: allowsCredit, available: available) ? AppColors.muted : AppColors.amber,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (draft.needsCreditReason(allowsCredit: allowsCredit, available: available)) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _creditReason,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Motivo del crédito'),
                onChanged: (value) => _set(draft.withCreditReason(value)),
              ),
            ],
          ],
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
              FilledButton(
                onPressed: problems.isNotEmpty || _saving ? null : () => _save(run, stop),
                child: _saving
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(draft.collected.isZero ? 'Registrar a crédito' : 'Cobrar ${money(draft.collected)} y facturar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
