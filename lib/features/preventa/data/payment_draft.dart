import '../../../core/decimal_value.dart';
import 'preventa_models.dart';

/// A payment method line of an account payment.
final class PaymentLine {
  const PaymentLine({required this.method, required this.amount, this.reference});

  final String method;
  final DecimalValue amount;
  final String? reference;

  PaymentLine copyWith({String? method, DecimalValue? amount, String? reference}) =>
      PaymentLine(method: method ?? this.method, amount: amount ?? this.amount, reference: reference ?? this.reference);
}

/// An account payment being registered: how much, which debts it pays and how it was paid.
/// The server rejects it unless methods and debts add up exactly to the amount.
final class PaymentDraft {
  const PaymentDraft({required this.debts, required this.amount, required this.allocations, required this.lines});

  /// Starts empty, paid in cash.
  factory PaymentDraft.start(List<LocalReceivable> debts) =>
      PaymentDraft(debts: debts, amount: DecimalValue.zero, allocations: const {}, lines: [PaymentLine(method: 'cash', amount: DecimalValue.zero)]);

  final List<LocalReceivable> debts;
  final DecimalValue amount;

  /// Amount applied to each debt, by receivable id.
  final Map<String, DecimalValue> allocations;
  final List<PaymentLine> lines;

  DecimalValue get totalDebt => debts.fold(DecimalValue.zero, (sum, debt) => sum + debt.outstanding);
  DecimalValue get allocated => allocations.values.fold(DecimalValue.zero, (sum, value) => sum + value);
  DecimalValue get paid => lines.fold(DecimalValue.zero, (sum, line) => sum + line.amount);

  /// Sets the amount and applies it to the oldest debts first. With a single
  /// payment method, that method follows the amount.
  PaymentDraft withAmount(DecimalValue value) {
    var left = value;
    final applied = <String, DecimalValue>{};
    final ordered = [...debts]..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));
    for (final debt in ordered) {
      if (left.isZero || left.isNegative) break;
      final part = left.compareTo(debt.outstanding) > 0 ? debt.outstanding : left;
      applied[debt.id] = part;
      left = left - part;
    }
    return PaymentDraft(
      debts: debts,
      amount: value,
      allocations: applied,
      lines: lines.length == 1 ? [lines.single.copyWith(amount: value)] : lines,
    );
  }

  /// Applies a chosen amount to one debt (manual distribution); the total follows.
  PaymentDraft withAllocation(String receivableId, DecimalValue value) {
    final next = {...allocations};
    if (value.isZero || value.isNegative) {
      next.remove(receivableId);
    } else {
      next[receivableId] = value;
    }
    final total = next.values.fold(DecimalValue.zero, (sum, part) => sum + part);
    return PaymentDraft(
      debts: debts,
      amount: total,
      allocations: next,
      lines: lines.length == 1 ? [lines.single.copyWith(amount: total)] : lines,
    );
  }

  PaymentDraft withLines(List<PaymentLine> value) => PaymentDraft(debts: debts, amount: amount, allocations: allocations, lines: value);

  /// What stops saving, in plain words; empty when it can be saved.
  List<String> problems({required Set<String> methodsRequiringReference}) => [
        if (amount.isZero || amount.isNegative) 'Escribe el monto del abono.',
        if (amount.compareTo(totalDebt) > 0) 'El abono no puede ser mayor que la deuda (${totalDebt.toFixed(2)}).',
        for (final debt in debts)
          if ((allocations[debt.id] ?? DecimalValue.zero).compareTo(debt.outstanding) > 0) '${debt.documentNumber ?? 'Una deuda'} recibe más de lo que debe.',
        if (allocated != amount) 'Lo aplicado a las deudas no suma el abono.',
        if (paid != amount) 'Las formas de pago no suman el abono.',
        for (final line in lines)
          if (methodsRequiringReference.contains(line.method) && (line.reference ?? '').trim().isEmpty) 'Falta la referencia del pago.',
        for (final line in lines)
          if (line.amount.isZero || line.amount.isNegative) 'Cada forma de pago necesita un monto.',
      ];
}

/// Money typed by the user: positive, at most two decimals.
DecimalValue? parseAmount(String text) {
  final normalized = text.trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  try {
    final value = DecimalValue.parse(normalized);
    if (value.isNegative || value.scale > 2) return null;
    return value;
  } on FormatException {
    return null;
  }
}
