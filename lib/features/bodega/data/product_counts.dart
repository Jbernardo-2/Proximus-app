import 'dart:convert';

import '../../../core/decimal_value.dart';
import '../../../data/database.dart';
import '../../preventa/data/preventa_models.dart';

/// A product counted on this phone, from the queue: pending, applied by the server, or refused.
final class LocalCount {
  const LocalCount({
    required this.outboxId,
    required this.productId,
    required this.warehouseId,
    required this.counted,
    required this.countedAt,
    required this.status,
    this.notes,
    this.message,
    this.countNumber,
    this.expected,
    this.difference,
  });

  final int outboxId;
  final String productId;
  final String warehouseId;

  /// In base units.
  final DecimalValue counted;
  final DateTime countedAt;
  final String status;
  final String? notes;

  /// Why the server refused it.
  final String? message;

  /// What the server answered once it applied the count.
  final String? countNumber;
  final DecimalValue? expected;
  final DecimalValue? difference;

  bool get isPending => status == OutboxStatus.pending;
  bool get isRejected => status == OutboxStatus.rejected;
}

/// Counts recorded on this phone, newest first.
List<LocalCount> localCounts(List<OutboxData> outbox) {
  final counts = <LocalCount>[];
  for (final row in outbox) {
    if (row.type != 'inventory.product_count') continue;
    final payload = (jsonDecode(row.payload) as Map).cast<String, dynamic>();
    final data = row.result == null ? null : jsonDecode(row.result!);
    final item = data is Map ? ((data['items'] as List?)?.firstOrNull as Map?) : null;
    counts.add(LocalCount(
      outboxId: row.id,
      productId: payload['product_id'].toString(),
      warehouseId: payload['warehouse_id'].toString(),
      counted: DecimalValue.parse(payload['counted_quantity']),
      countedAt: DateTime.tryParse(payload['counted_at']?.toString() ?? '')?.toLocal() ?? row.createdAt,
      notes: payload['notes']?.toString(),
      status: row.status,
      message: row.message,
      countNumber: data is Map ? data['count_number']?.toString() : null,
      expected: item?['expected_quantity'] == null ? null : DecimalValue.parse(item!['expected_quantity']),
      difference: item?['difference'] == null ? null : DecimalValue.parse(item!['difference']),
    ));
  }
  counts.sort((a, b) => b.countedAt.compareTo(a.countedAt));
  return counts;
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
