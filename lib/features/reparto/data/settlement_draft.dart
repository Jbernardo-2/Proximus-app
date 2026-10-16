import '../../../core/decimal_value.dart';

/// One way the delivered amount is paid: cash, transfer, card, check, other, or credit.
final class SettlementLine {
  const SettlementLine({required this.method, required this.amount, this.reference});

  final String method;
  final DecimalValue amount;
  final String? reference;

  bool get isCredit => method == 'credit';

  SettlementLine copyWith({String? method, DecimalValue? amount, String? reference}) =>
      SettlementLine(method: method ?? this.method, amount: amount ?? this.amount, reference: reference ?? this.reference);
}

/// The payment of a delivered stop being recorded. The server checks the same rules:
/// the lines add up exactly to what was delivered and credit goes in a single line.
final class SettlementDraft {
  const SettlementDraft({required this.total, required this.lines, this.creditReason = ''});

  /// One line for the whole amount: credit if the order was on credit, cash otherwise.
  factory SettlementDraft.start(DecimalValue total, {required bool credit}) => SettlementDraft(
    total: total,
    lines: [SettlementLine(method: credit ? 'credit' : 'cash', amount: total)],
  );

  final DecimalValue total;
  final List<SettlementLine> lines;
  final String creditReason;

  DecimalValue get assigned => lines.fold(DecimalValue.zero, (sum, line) => sum + line.amount);
  DecimalValue get credit => lines.where((line) => line.isCredit).fold(DecimalValue.zero, (sum, line) => sum + line.amount);
  DecimalValue get collected => assigned - credit;
  DecimalValue get missing => total - assigned;

  SettlementDraft withLines(List<SettlementLine> value) => SettlementDraft(total: total, lines: value, creditReason: creditReason);

  SettlementDraft withCreditReason(String value) => SettlementDraft(total: total, lines: lines, creditReason: value);

  /// Adds a method for what is still unassigned (or nothing, to be typed).
  SettlementDraft addMethod(String method) => withLines([...lines, SettlementLine(method: method, amount: missing.isNegative ? DecimalValue.zero : missing)]);

  SettlementDraft removeAt(int index) {
    final next = [...lines]..removeAt(index);
    // With a single method left, it takes the whole amount again.
    return withLines(next.length == 1 ? [next.single.copyWith(amount: total)] : next);
  }

  SettlementDraft updateAt(int index, SettlementLine line) => withLines([...lines]..[index] = line);

  /// Credit beyond what the customer has (or without credit at all) is accepted from the
  /// road, but the supervisor sees it as an exception: it needs a reason.
  bool needsCreditReason({required bool allowsCredit, required DecimalValue? available}) => !credit.isZero && (!allowsCredit || (available != null && credit.compareTo(available) > 0));

  /// What stops saving, in plain words; empty when it can be saved.
  List<String> problems({required Set<String> requiringReference, required bool allowsCredit, required DecimalValue? available}) => [
    if (assigned != total) 'Las formas de pago deben sumar ${total.toFixed(2)}.',
    for (final line in lines)
      if (line.amount.isZero || line.amount.isNegative) 'Cada forma de pago necesita un monto.',
    if (lines.where((line) => line.isCredit).length > 1) 'El crédito va en una sola línea.',
    for (final line in lines)
      if (requiringReference.contains(line.method) && (line.reference ?? '').trim().isEmpty) 'Falta la referencia del pago.',
    if (needsCreditReason(allowsCredit: allowsCredit, available: available) && creditReason.trim().isEmpty) 'Explica por qué se da crédito por encima de lo autorizado.',
  ];
}
