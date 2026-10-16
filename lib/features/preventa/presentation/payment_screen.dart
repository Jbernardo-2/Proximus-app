import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../../core/location_capture.dart';
import '../application/preventa_actions.dart';
import '../data/payment_draft.dart';
import '../data/preventa_models.dart';
import 'payment_split_editor.dart';
import 'receipt_screen.dart';

final _date = DateFormat('dd/MM/yyyy');

/// Registers an account payment: amount, the debts it pays and how it was paid.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  late final LocationSession _location = ref.read(locationServiceProvider).start();
  final _amount = TextEditingController();
  PaymentDraft? _draft;
  bool _saving = false;
  bool _debtsChanged = false;

  static bool _sameDebts(List<LocalReceivable> a, List<LocalReceivable> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) a[i].id == b[i].id && a[i].outstanding == b[i].outstanding].every((same) => same);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _setAmount(String text) {
    final value = parseAmount(text) ?? DecimalValue.zero;
    setState(() => _draft = _draft!.withAmount(value));
  }

  void _payAll() {
    final total = _draft!.totalDebt;
    _amount.text = total.toFixed(2);
    _setAmount(_amount.text);
  }

  Future<void> _editAllocation(LocalReceivable debt) async {
    final value = await showDialog<DecimalValue>(
      context: context,
      builder: (_) => _AllocationDialog(debt: debt, initial: _draft!.allocations[debt.id] ?? DecimalValue.zero),
    );
    if (value == null || !mounted) return;
    setState(() {
      _draft = _draft!.withAllocation(debt.id, value);
      _amount.text = _draft!.amount.toFixed(2);
    });
  }

  Future<void> _save(LocalCustomer customer) async {
    setState(() => _saving = true);
    try {
      final receipt = await ref.read(preventaActionsProvider).recordPayment(customer: customer, draft: _draft!, location: _location);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ReceiptScreen(receipt: receipt, justIssued: true)));
    } catch (error, stack) {
      debugPrint('No se pudo registrar el abono: $error\n$stack');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo registrar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(customerProfileProvider(widget.customerId));
    final manifest = ref.watch(manifestProvider).value;
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Abono')),
        body: const Center(child: Text('Este cliente no está en el teléfono.')),
      );
    }
    var draft = _draft ??= PaymentDraft.start(profile.receivables);
    // A sync while the screen is open can change the debts (another payment, a new
    // invoice). Re-apply the amount to the current debts instead of sending stale ones.
    if (!_sameDebts(draft.debts, profile.receivables)) {
      draft = _draft = PaymentDraft(debts: profile.receivables, amount: DecimalValue.zero, allocations: const {}, lines: draft.lines).withAmount(draft.amount);
      _debtsChanged = true;
    }
    if (draft.debts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Abono')),
        body: const Center(child: Text('El cliente no tiene deudas abiertas.')),
      );
    }
    final methods = manifest?.options('payment_methods') ?? const [(value: 'cash', label: 'Efectivo')];
    final requiringReference = manifest?.requiringReference('payment_methods') ?? const <String>{};
    final problems = draft.problems(methodsRequiringReference: requiringReference);
    final lines = [for (final line in draft.lines) (method: line.method, amount: line.amount, reference: line.reference)];

    return Scaffold(
      appBar: AppBar(title: Text('Abono · ${profile.customer.businessName}', overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              const Text('Deuda total', style: TextStyle(color: AppColors.muted)),
              const Spacer(),
              Text(money(draft.totalDebt), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: 'Monto del abono',
              prefixText: 'L ',
              suffixIcon: TextButton(onPressed: _payAll, child: const Text('Todo')),
            ),
            onChanged: _setAmount,
          ),
          if (_debtsChanged)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Las deudas se actualizaron con la última sincronización; el monto se volvió a aplicar. Revisa la distribución.', style: TextStyle(color: AppColors.amber, fontSize: 13)),
            ),
          const SizedBox(height: 20),
          const Text('Aplicado a', style: TextStyle(fontWeight: FontWeight.w700)),
          const Text('Se aplica primero a lo más antiguo; toca una deuda para cambiarlo.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 8),
          for (final debt in draft.debts)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _editAllocation(debt),
                title: Text(debt.documentNumber ?? 'Saldo', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Debe ${money(debt.outstanding)}${debt.dueDate == null ? '' : ' · vence ${_date.format(debt.dueDate!)}'}',
                  style: TextStyle(color: debt.isOverdue ? AppColors.danger : AppColors.muted),
                ),
                trailing: Text(
                  money(draft.allocations[debt.id] ?? DecimalValue.zero),
                  style: TextStyle(fontWeight: FontWeight.w800, color: draft.allocations.containsKey(debt.id) ? AppColors.brand : AppColors.muted),
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text('Forma de pago', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          PaymentSplitEditor(
            total: draft.amount,
            lines: lines,
            methods: methods,
            requiringReference: requiringReference,
            withoutReference: const {},
            onChanged: (next) => setState(() => _draft = draft.withLines([for (final line in next) PaymentLine(method: line.method, amount: line.amount, reference: line.reference)])),
          ),
          if (problems.isNotEmpty && !draft.amount.isZero) ...[const SizedBox(height: 8), for (final problem in problems.toSet()) Text('• $problem', style: const TextStyle(color: AppColors.amber))],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!draft.amount.isZero) ...[SplitRemainingBar(total: draft.amount, lines: lines), const SizedBox(height: 8)],
              FilledButton(
                onPressed: problems.isNotEmpty || _saving ? null : () => _save(profile.customer),
                child: _saving
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(draft.amount.isZero ? 'Registrar abono' : 'Registrar abono de ${money(draft.amount)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Amount to apply to one debt. It owns its text field, so the field is released only
/// after the dialog has finished closing (releasing it earlier breaks the closing animation).
class _AllocationDialog extends StatefulWidget {
  const _AllocationDialog({required this.debt, required this.initial});

  final LocalReceivable debt;
  final DecimalValue initial;

  @override
  State<_AllocationDialog> createState() => _AllocationDialogState();
}

class _AllocationDialogState extends State<_AllocationDialog> {
  late final _controller = TextEditingController(text: widget.initial.toFixed(2));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Aplicar a ${widget.debt.documentNumber ?? 'la deuda'}'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: 'Monto', helperText: 'Debe ${money(widget.debt.outstanding)}'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: () => Navigator.pop(context, parseAmount(_controller.text)), child: const Text('Aplicar')),
    ],
  );
}
