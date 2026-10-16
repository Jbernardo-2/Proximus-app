import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../../core/location_capture.dart';
import '../../preventa/presentation/payment_split_editor.dart';
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';
import '../data/settlement_draft.dart';
import 'delivery_invoice_screen.dart';

/// Collects what was delivered: one method for everything by default (cash, or credit
/// when the order was on credit), or several combined, always showing what is left.
class DeliveryPaymentScreen extends ConsumerStatefulWidget {
  const DeliveryPaymentScreen({super.key, required this.runId, required this.stopId});

  final String runId;
  final String stopId;

  @override
  ConsumerState<DeliveryPaymentScreen> createState() => _DeliveryPaymentScreenState();
}

class _DeliveryPaymentScreenState extends ConsumerState<DeliveryPaymentScreen> {
  late final LocationSession _location = ref.read(locationServiceProvider).start();
  final _creditReason = TextEditingController();
  SettlementDraft? _draft;
  bool _saving = false;

  @override
  void dispose() {
    _creditReason.dispose();
    super.dispose();
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
      return Scaffold(appBar: AppBar(title: const Text('Cobrar')), body: const Center(child: Text('Esta parada ya no está en el teléfono.')));
    }
    final draft = _draft ??= SettlementDraft.start(stop.balanceDue, credit: stop.isCredit);
    final manifest = ref.watch(manifestProvider).value;
    final methods = manifest?.options('settlement_methods') ?? const [(value: 'cash', label: 'Efectivo'), (value: 'credit', label: 'Crédito')];
    final requiringReference = manifest?.requiringReference('settlement_methods') ?? const <String>{};
    final balance = ref.watch(customerBalancesProvider)[stop.customerId];
    final allowsCredit = balance?.allowsCredit ?? false;
    final available = balance?.available;
    // The bar at the bottom already says whether the lines add up.
    final problems = [
      for (final problem in draft.problems(requiringReference: requiringReference, allowsCredit: allowsCredit, available: available))
        if (!problem.startsWith('Las formas de pago deben sumar')) problem,
    ];
    final lines = [for (final line in draft.lines) (method: line.method, amount: line.amount, reference: line.reference)];
    final complete = draft.assigned == draft.total;
    final needsReason = draft.needsCreditReason(allowsCredit: allowsCredit, available: available);

    return Scaffold(
      appBar: AppBar(title: Text('Cobrar · ${stop.customerName}', overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total entregado', style: TextStyle(color: AppColors.muted)),
                Text(money(draft.total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                if (stop.isCredit) const Text('Pedido a crédito', style: TextStyle(color: Color(0xFF2F6FD0), fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Forma de pago', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          PaymentSplitEditor(
            total: draft.total,
            lines: lines,
            methods: methods,
            requiringReference: requiringReference,
            onChanged: (next) => setState(() => _draft = draft.withLines([for (final line in next) SettlementLine(method: line.method, amount: line.amount, reference: line.reference)])),
          ),
          if (draft.lines.any((line) => line.isCredit)) ...[
            const SizedBox(height: 8),
            Text(
              !allowsCredit
                  ? 'El cliente no tiene crédito activo. Quedará como excepción para el supervisor.'
                  : 'Crédito disponible: ${money(available == null || available.isNegative ? DecimalValue.zero : available)}',
              style: TextStyle(color: allowsCredit && !needsReason ? AppColors.muted : AppColors.amber, fontWeight: FontWeight.w600),
            ),
            if (needsReason) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _creditReason,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Motivo del crédito'),
                onChanged: (value) => setState(() => _draft = draft.withCreditReason(value)),
              ),
            ],
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SplitRemainingBar(total: draft.total, lines: lines),
            if (problems.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(problems.first, style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: !complete || problems.isNotEmpty || _saving ? null : () => _save(run, stop),
              child: _saving
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(draft.collected.isZero ? 'Registrar a crédito' : 'Cobrar ${money(draft.collected)} y facturar'),
            ),
          ]),
        ),
      ),
    );
  }
}
