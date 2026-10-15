import '../../../core/decimal_value.dart';
import 'preventa_models.dart';

/// One line of the order being taken. The price always comes from the
/// catalog rule for its quantity; the preventista cannot change it.
final class OrderLine {
  OrderLine({required this.product, required this.presentation, required this.quantity, required DateTime day})
      : _price = presentation.priceFor(quantity, day);

  final LocalProduct product;
  final LocalPresentation presentation;
  final DecimalValue quantity;
  final ({DecimalValue unitPrice, LocalPriceTier? tier}) _price;

  DecimalValue get unitPrice => _price.unitPrice;
  bool get hasTierPrice => _price.tier != null;
  DecimalValue get total => quantity * unitPrice;

  /// Quantity in the product's base unit (what the stock is counted in).
  DecimalValue get baseQuantity => quantity * presentation.conversionFactor;
}

/// What stock and credit say about the order. None of it blocks saving:
/// offline the server accepts the order and leaves the exception to the supervisor.
final class OrderWarnings {
  const OrderWarnings({required this.shortProducts, required this.creditExceededBy, required this.creditNotAllowed});

  /// Product names whose requested quantity is above what the warehouse has available.
  final List<String> shortProducts;

  /// How much the order goes over the available credit (zero when it fits).
  final DecimalValue creditExceededBy;
  final bool creditNotAllowed;

  bool get any => shortProducts.isNotEmpty || !creditExceededBy.isZero || creditNotAllowed;
}

final class OrderDraft {
  OrderDraft({
    required this.customerId,
    required this.routeStopId,
    required this.day,
    this.lines = const [],
    this.paymentTerm = 'cash',
    this.deliveryDate,
    this.notes,
  });

  final String customerId;
  final String routeStopId;
  final DateTime day;
  final List<OrderLine> lines;
  final String paymentTerm;
  final DateTime? deliveryDate;
  final String? notes;

  DecimalValue get total => lines.fold(DecimalValue.zero, (sum, line) => sum + line.total);
  bool get isEmpty => lines.isEmpty;
  bool get isCredit => paymentTerm == 'credit';

  /// Adds the quantity to the line of that presentation (the server allows one line per presentation).
  OrderDraft add(LocalProduct product, LocalPresentation presentation, DecimalValue quantity) {
    final existing = lines.where((line) => line.presentation.id == presentation.id).firstOrNull;
    return setQuantity(product, presentation, (existing?.quantity ?? DecimalValue.zero) + quantity);
  }

  /// Sets the quantity of a presentation; zero or less removes the line.
  OrderDraft setQuantity(LocalProduct product, LocalPresentation presentation, DecimalValue quantity) {
    final others = [for (final line in lines) if (line.presentation.id != presentation.id) line];
    final index = lines.indexWhere((line) => line.presentation.id == presentation.id);
    if (quantity.isNegative || quantity.isZero) return _with(lines: others);
    final line = OrderLine(product: product, presentation: presentation, quantity: quantity, day: day);
    return _with(lines: index < 0 ? [...lines, line] : (others..insert(index, line)));
  }

  OrderDraft remove(String presentationId) => _with(lines: [for (final line in lines) if (line.presentation.id != presentationId) line]);

  OrderDraft withTerms({String? paymentTerm, DateTime? deliveryDate, String? notes}) =>
      _with(paymentTerm: paymentTerm, deliveryDate: deliveryDate, notes: notes);

  /// [available] is the warehouse stock in base units per product; [credit] the customer's credit now.
  OrderWarnings warnings({required Map<String, DecimalValue> available, required ({bool allowsCredit, DecimalValue available})? credit}) {
    final requested = <String, DecimalValue>{};
    final names = <String, String>{};
    for (final line in lines) {
      requested[line.product.id] = (requested[line.product.id] ?? DecimalValue.zero) + line.baseQuantity;
      names[line.product.id] = line.product.name;
    }
    final short = [
      for (final entry in requested.entries)
        if (entry.value.compareTo(available[entry.key] ?? DecimalValue.zero) > 0) names[entry.key]!,
    ];

    var exceeded = DecimalValue.zero;
    var notAllowed = false;
    if (isCredit) {
      notAllowed = !(credit?.allowsCredit ?? false);
      final left = (credit?.available ?? DecimalValue.zero) - total;
      if (left.isNegative) exceeded = -left;
    }
    return OrderWarnings(shortProducts: short, creditExceededBy: exceeded, creditNotAllowed: notAllowed);
  }

  OrderDraft _with({List<OrderLine>? lines, String? paymentTerm, DateTime? deliveryDate, String? notes}) => OrderDraft(
        customerId: customerId,
        routeStopId: routeStopId,
        day: day,
        lines: lines ?? this.lines,
        paymentTerm: paymentTerm ?? this.paymentTerm,
        deliveryDate: deliveryDate ?? this.deliveryDate,
        notes: notes ?? this.notes,
      );
}

/// Quantity typed by the user: whole numbers unless the product sells fractions.
DecimalValue? parseQuantity(String text, {required bool allowsDecimal}) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  try {
    final value = DecimalValue.parse(normalized);
    if (value.isNegative || value.isZero) return null;
    if (!allowsDecimal && value.scale > 0) return null;
    if (value.scale > 6) return null;
    return value;
  } on FormatException {
    return null;
  }
}
