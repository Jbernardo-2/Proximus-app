import '../../../core/decimal_value.dart';
import '../../preventa/data/preventa_models.dart';

/// The kinds of merchandise coming in that the phone records. Adjustments need the
/// adjustment permission, as on the web.
enum ReceiptType {
  receipt('receipt', 'Entrada de proveedor'),
  customerReturn('customer_return', 'Devolución de cliente'),
  adjustmentIn('adjustment_in', 'Ajuste de entrada');

  const ReceiptType(this.value, this.label);

  final String value;
  final String label;

  bool get needsAdjustPermission => this == adjustmentIn;
  bool get hasSupplier => this == receipt;
  bool get hasCost => this == receipt;

  static ReceiptType? of(String? value) => values.where((type) => type.value == value).firstOrNull;
}

/// One line being entered: a presentation, how many, and what the product needs.
final class ReceiptLine {
  const ReceiptLine({required this.product, required this.presentation, required this.quantity, this.unitCost, this.lotNumber, this.expirationDate});

  final LocalProduct product;
  final LocalPresentation presentation;
  final DecimalValue quantity;
  final DecimalValue? unitCost;
  final String? lotNumber;
  final DateTime? expirationDate;

  DecimalValue get baseQuantity => quantity * presentation.conversionFactor;

  /// The server keeps one line per presentation and lot.
  String get key => '${presentation.id}|${lotNumber ?? ''}';

  Map<String, dynamic> toJson() => {
    'product_presentation_id': presentation.id,
    'quantity': quantity.toString(),
    'unit_cost': unitCost?.toString(),
    'lot_number': lotNumber,
    'expiration_date': expirationDate == null ? null : _date(expirationDate!),
  };
}

String _date(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// What the phone sends to post the whole entry.
Map<String, dynamic> receiptPayload({
  required ReceiptType type,
  required String warehouseId,
  required DateTime occurredOn,
  required List<ReceiptLine> lines,
  String? supplierId,
  String? reference,
  String? notes,
}) => {
  'type': type.value,
  'warehouse_id': warehouseId,
  'supplier_id': type.hasSupplier ? supplierId : null,
  'occurred_on': _date(occurredOn),
  'external_reference': (reference?.trim().isEmpty ?? true) ? null : reference!.trim(),
  'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
  'items': [for (final line in lines) line.toJson()],
};

/// A posted document as the server lists it.
final class PostedReceipt {
  const PostedReceipt({
    required this.id,
    required this.number,
    required this.typeLabel,
    required this.occurredOn,
    required this.itemsCount,
    this.supplier,
    this.reference,
    this.createdBy,
    this.items = const [],
  });

  factory PostedReceipt.fromJson(Map<String, dynamic> json) => PostedReceipt(
    id: json['id'].toString(),
    number: json['document_number']?.toString() ?? '',
    typeLabel: json['type_label']?.toString() ?? '',
    occurredOn: DateTime.tryParse(json['occurred_on']?.toString() ?? '') ?? DateTime.now(),
    itemsCount: (json['items_count'] as num?)?.toInt() ?? (json['items'] as List?)?.length ?? 0,
    supplier: (json['supplier'] as Map?)?['name']?.toString(),
    reference: json['external_reference']?.toString(),
    createdBy: (json['created_by'] as Map?)?['name']?.toString(),
    items: [
      for (final item in (json['items'] as List? ?? const []).cast<Map>())
        (
          product: (item['product'] as Map?)?['name']?.toString() ?? '',
          presentation: (item['presentation'] as Map?)?['name']?.toString() ?? '',
          quantity: DecimalValue.parse(item['quantity']),
          lot: item['lot_number']?.toString(),
        ),
    ],
  );

  final String id;
  final String number;
  final String typeLabel;
  final DateTime occurredOn;
  final int itemsCount;
  final String? supplier;
  final String? reference;
  final String? createdBy;
  final List<({String product, String presentation, DecimalValue quantity, String? lot})> items;
}

/// Only the documents that bring merchandise in, newest first as the server sends them.
List<PostedReceipt> postedReceipts(List<Map<String, dynamic>> documents) => [
  for (final json in documents)
    if (ReceiptType.of(json['type']?.toString()) != null) PostedReceipt.fromJson(json),
];
