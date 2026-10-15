import 'decimal_value.dart';

/// "L 1,234.50", the same format as the web panel, straight from the exact value.
String money(DecimalValue value, {String symbol = 'L'}) {
  final fixed = value.toFixed(2);
  final negative = fixed.startsWith('-');
  final parts = (negative ? fixed.substring(1) : fixed).split('.');
  final whole = parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${negative ? '-' : ''}$symbol $whole.${parts.last}';
}
