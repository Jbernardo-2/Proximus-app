/// Exact base-10 value for money and quantities received as JSON strings.
///
/// It deliberately never converts through [double], so totals calculated
/// offline preserve the same decimal value the Laravel API will validate.
final class DecimalValue implements Comparable<DecimalValue> {
  const DecimalValue._(this._coefficient, this.scale);

  factory DecimalValue.parse(Object? value) {
    final source = value?.toString().trim() ?? '';
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(source);
    if (match == null) {
      throw FormatException('Valor decimal inválido: $source');
    }

    final fraction = match.group(3) ?? '';
    final sign = match.group(1) == '-' ? -1 : 1;
    return DecimalValue._(
      BigInt.parse('${match.group(2)}$fraction') * BigInt.from(sign),
      fraction.length,
    ).normalized();
  }

  static final zero = DecimalValue._(BigInt.zero, 0);

  final BigInt _coefficient;
  final int scale;

  bool get isNegative => _coefficient.isNegative;
  bool get isZero => _coefficient == BigInt.zero;

  DecimalValue operator +(DecimalValue other) {
    final targetScale = scale > other.scale ? scale : other.scale;
    return DecimalValue._(
      _scaledCoefficient(targetScale) + other._scaledCoefficient(targetScale),
      targetScale,
    ).normalized();
  }

  DecimalValue operator -(DecimalValue other) => this + -other;

  DecimalValue operator -() => DecimalValue._(-_coefficient, scale);

  DecimalValue operator *(DecimalValue other) =>
      DecimalValue._(_coefficient * other._coefficient, scale + other.scale).normalized();

  @override
  int compareTo(DecimalValue other) {
    final targetScale = scale > other.scale ? scale : other.scale;
    return _scaledCoefficient(targetScale).compareTo(other._scaledCoefficient(targetScale));
  }

  String toFixed(int digits) {
    if (digits < 0) throw ArgumentError.value(digits, 'digits');
    var coefficient = _coefficient;
    if (digits < scale) {
      final divisor = _powerOfTen(scale - digits);
      final quotient = coefficient ~/ divisor;
      final remainder = coefficient.abs() % divisor;
      coefficient = quotient;
      if (remainder * BigInt.two >= divisor) {
        coefficient += coefficient.isNegative ? -BigInt.one : BigInt.one;
      }
    } else if (digits > scale) {
      coefficient *= _powerOfTen(digits - scale);
    }
    return _format(coefficient, digits);
  }

  @override
  String toString() => _format(_coefficient, scale);

  @override
  bool operator ==(Object other) => other is DecimalValue && compareTo(other) == 0;

  @override
  int get hashCode {
    final value = normalized();
    return Object.hash(value._coefficient, value.scale);
  }

  DecimalValue normalized() {
    var coefficient = _coefficient;
    var currentScale = scale;
    while (currentScale > 0 && coefficient % BigInt.from(10) == BigInt.zero) {
      coefficient ~/= BigInt.from(10);
      currentScale--;
    }
    return DecimalValue._(coefficient, currentScale);
  }

  BigInt _scaledCoefficient(int targetScale) =>
      _coefficient * _powerOfTen(targetScale - scale);

  static BigInt _powerOfTen(int exponent) => BigInt.from(10).pow(exponent);

  static String _format(BigInt coefficient, int scale) {
    final sign = coefficient.isNegative ? '-' : '';
    var digits = coefficient.abs().toString();
    if (scale == 0) return '$sign$digits';
    digits = digits.padLeft(scale + 1, '0');
    final split = digits.length - scale;
    return '$sign${digits.substring(0, split)}.${digits.substring(split)}';
  }
}
