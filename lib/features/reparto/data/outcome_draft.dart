import '../../../core/decimal_value.dart';
import 'delivery_models.dart';

/// Where the part of a product that was not delivered went.
enum Leftover {
  returned('Devuelto'),
  damaged('Dañado'),
  missing('Faltante');

  const Leftover(this.label);

  final String label;
}

/// What happened to one loaded product.
final class OutcomeLine {
  const OutcomeLine({required this.item, required this.delivered, this.leftover = Leftover.returned, this.allowsDecimal = false});

  final LocalDeliveryItem item;
  final DecimalValue delivered;

  /// The rest (loaded - delivered) is counted as this.
  final Leftover leftover;
  final bool allowsDecimal;

  DecimalValue get rest => item.loaded - delivered;
  DecimalValue get deliveredTotal => delivered * item.unitPrice;
  bool get isComplete => rest.isZero;

  OutcomeLine copyWith({DecimalValue? delivered, Leftover? leftover}) =>
      OutcomeLine(item: item, delivered: delivered ?? this.delivered, leftover: leftover ?? this.leftover, allowsDecimal: allowsDecimal);
}

/// The delivery of a stop being recorded. The server checks the same rules:
/// every product accounted for, delivered + returned + damaged + missing = loaded.
final class OutcomeDraft {
  const OutcomeDraft({required this.lines, this.receiverName = '', this.reason, this.notes = ''});

  /// Starts with everything delivered, the usual case.
  factory OutcomeDraft.start(LocalDeliveryStop stop, {Set<String> decimalItems = const {}, String? receiverName}) => OutcomeDraft(
    lines: [for (final item in stop.items) OutcomeLine(item: item, delivered: item.loaded, allowsDecimal: decimalItems.contains(item.id))],
    receiverName: receiverName ?? '',
  );

  final List<OutcomeLine> lines;
  final String receiverName;
  final String? reason;
  final String notes;

  bool get anyDelivered => lines.any((line) => !line.delivered.isZero);
  bool get allDelivered => lines.every((line) => line.isComplete);
  bool get anyReturned => lines.any((line) => !line.isComplete && line.leftover == Leftover.returned);
  DecimalValue get deliveredTotal => lines.fold(DecimalValue.zero, (total, line) => total + line.deliveredTotal);

  /// A return always needs its reason (closed, rejected, could not pay...).
  bool get needsReason => anyReturned;

  OutcomeDraft _with({List<OutcomeLine>? lines, String? receiverName, String? reason, bool clearReason = false, String? notes}) =>
      OutcomeDraft(lines: lines ?? this.lines, receiverName: receiverName ?? this.receiverName, reason: clearReason ? null : (reason ?? this.reason), notes: notes ?? this.notes);

  OutcomeDraft deliverAll() => _with(lines: [for (final line in lines) line.copyWith(delivered: line.item.loaded)]);

  /// Nothing was left: everything goes back to the truck.
  OutcomeDraft deliverNothing() => _with(
    lines: [for (final line in lines) line.copyWith(delivered: DecimalValue.zero, leftover: Leftover.returned)],
  );

  /// Sets what was delivered of one product, between nothing and what was loaded.
  OutcomeDraft withDelivered(String itemId, DecimalValue value) => _with(
    lines: [
      for (final line in lines)
        if (line.item.id != itemId) line else line.copyWith(delivered: value.isNegative ? DecimalValue.zero : (value.compareTo(line.item.loaded) > 0 ? line.item.loaded : value)),
    ],
  );

  OutcomeDraft withLeftover(String itemId, Leftover leftover) => _with(lines: [for (final line in lines) line.item.id == itemId ? line.copyWith(leftover: leftover) : line]);

  OutcomeDraft withReceiver(String value) => _with(receiverName: value);

  OutcomeDraft withReason(String? value) => value == null ? _with(clearReason: true) : _with(reason: value);

  OutcomeDraft withNotes(String value) => _with(notes: value);

  /// What stops saving, in plain words; empty when it can be saved.
  List<String> problems() => [
    for (final line in lines)
      if (!line.allowsDecimal && line.delivered.scale > 0) '${line.item.productName} se entrega en cantidades enteras.',
    if (anyDelivered && receiverName.trim().isEmpty) 'Escribe quién recibió la mercadería.',
    if (needsReason && reason == null) 'Elige el motivo de la devolución.',
  ];

  /// `items` of the `delivery.outcome` operation.
  List<Map<String, dynamic>> payloadItems() => [
    for (final line in lines)
      {
        'id': line.item.id,
        'delivered_quantity': line.delivered.toString(),
        'returned_quantity': (line.leftover == Leftover.returned ? line.rest : DecimalValue.zero).toString(),
        'damaged_quantity': (line.leftover == Leftover.damaged ? line.rest : DecimalValue.zero).toString(),
        'missing_quantity': (line.leftover == Leftover.missing ? line.rest : DecimalValue.zero).toString(),
      },
  ];
}
