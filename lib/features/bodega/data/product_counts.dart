import '../../../core/decimal_value.dart';
import '../../preventa/data/preventa_models.dart';

/// A single-product count as the server applied it.
final class ProductCount {
  const ProductCount({
    required this.countNumber,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.warehouseName,
    required this.counted,
    required this.expected,
    required this.difference,
    required this.postedAt,
    this.notes,
    this.countedBy,
  });

  factory ProductCount.fromJson(Map<String, dynamic> json) {
    final item = ((json['items'] as List?) ?? const []).cast<Map>().first;
    final product = (item['product'] as Map?) ?? const {};
    return ProductCount(
      countNumber: json['count_number']?.toString() ?? '',
      productId: product['id']?.toString() ?? '',
      productName: product['name']?.toString() ?? '',
      unit: product['base_unit_symbol']?.toString() ?? 'u',
      warehouseName: (json['warehouse'] as Map?)?['name']?.toString() ?? '',
      counted: DecimalValue.parse(item['counted_quantity']),
      expected: DecimalValue.parse(item['expected_quantity'] ?? '0'),
      difference: DecimalValue.parse(item['difference'] ?? '0'),
      postedAt: DateTime.tryParse(json['posted_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      notes: json['notes']?.toString(),
      countedBy: (json['created_by'] as Map?)?['name']?.toString(),
    );
  }

  final String countNumber;
  final String productId;
  final String productName;
  final String unit;
  final String warehouseName;

  /// In base units.
  final DecimalValue counted;
  final DecimalValue expected;
  final DecimalValue difference;
  final DateTime postedAt;
  final String? notes;
  final String? countedBy;
}

/// What a count by presentations adds up to in base units; null while nothing was typed.
DecimalValue? countedTotal(List<LocalPresentation> presentations, Map<String, DecimalValue?> typed) {
  DecimalValue? total;
  for (final presentation in presentations) {
    final value = typed[presentation.id];
    if (value == null) continue;
    total = (total ?? DecimalValue.zero) + value * presentation.conversionFactor;
  }
  return total;
}
