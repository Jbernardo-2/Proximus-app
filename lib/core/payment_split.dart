import 'decimal_value.dart';

/// One way a total is paid (cash, transfer, card, credit...). Shared by the driver's
/// delivery payment and the preventista's account payment.
typedef SplitLine = ({String method, DecimalValue amount, String? reference});

DecimalValue splitAssigned(List<SplitLine> lines) => lines.fold(DecimalValue.zero, (sum, line) => sum + line.amount);

/// Sets the amount of one line. With exactly two lines, changing the first makes the
/// second take the rest (cash + transfer, cash + credit); changing the second never
/// moves the first, it just shows what is missing. With more, the user completes by hand.
List<SplitLine> splitEdit(List<SplitLine> lines, int index, DecimalValue amount, DecimalValue total) {
  final next = [...lines]..[index] = (method: lines[index].method, amount: amount, reference: lines[index].reference);
  if (next.length == 2 && index == 0) {
    final rest = total - amount;
    next[1] = (method: next[1].method, amount: rest.isNegative ? DecimalValue.zero : rest, reference: next[1].reference);
  }
  return next;
}

/// Makes one line absorb whatever is missing (or give back what is over), so the
/// lines add up exactly to [total]. Never below zero.
List<SplitLine> splitComplete(List<SplitLine> lines, int index, DecimalValue total) {
  final adjusted = lines[index].amount + (total - splitAssigned(lines));
  return [...lines]..[index] = (method: lines[index].method, amount: adjusted.isNegative ? DecimalValue.zero : adjusted, reference: lines[index].reference);
}

/// A new method for what is still missing.
List<SplitLine> splitAdd(List<SplitLine> lines, String method, DecimalValue total) {
  final missing = total - splitAssigned(lines);
  return [...lines, (method: method, amount: missing.isNegative ? DecimalValue.zero : missing, reference: null)];
}

/// Removes a line; with a single one left, it takes the whole total again.
List<SplitLine> splitRemove(List<SplitLine> lines, int index, DecimalValue total) {
  final next = [...lines]..removeAt(index);
  if (next.length == 1) return [(method: next.single.method, amount: total, reference: next.single.reference)];
  return next;
}
