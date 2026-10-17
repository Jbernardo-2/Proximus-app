import '../../../core/decimal_value.dart';

DecimalValue _d(Object? value) => value == null ? DecimalValue.zero : DecimalValue.parse(value);

DecimalValue? _dn(Object? value) => value == null ? null : DecimalValue.parse(value);

DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '');

String? dateText(DateTime? date) => date == null ? null : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// A category, brand, unit or supplier to choose from.
final class CatalogOption {
  const CatalogOption({required this.id, required this.name, this.detail});

  factory CatalogOption.fromJson(Map<String, dynamic> json) => CatalogOption(
    id: json['id'].toString(),
    name: json['name']?.toString() ?? '',
    detail: json['symbol']?.toString() ?? json['code']?.toString(),
  );

  final String id;
  final String name;

  /// The unit symbol or the supplier code.
  final String? detail;

  String get label => detail == null || detail!.isEmpty ? name : '$name ($detail)';
}

/// The lists a product draws from, each with its API path and how to create one.
enum OptionKind {
  category('/categories', 'Categoría'),
  brand('/brands', 'Marca'),
  unit('/measurement-units', 'Unidad base'),
  supplier('/suppliers', 'Proveedor');

  const OptionKind(this.path, this.label);

  final String path;
  final String label;

  /// The smallest payload the server accepts to create one from its name.
  Map<String, dynamic> create(String name, {String? symbol}) => switch (this) {
    OptionKind.unit => {'name': name, 'symbol': symbol ?? name, 'decimal_places': 0, 'is_active': true},
    _ => {'name': name, 'is_active': true},
  };
}

final class PriceTierData {
  const PriceTierData({required this.id, required this.minQuantity, required this.unitPrice, required this.isActive, this.maxQuantity, this.startsAt, this.endsAt});

  factory PriceTierData.fromJson(Map<String, dynamic> json) => PriceTierData(
    id: json['id'].toString(),
    minQuantity: _d(json['min_quantity']),
    maxQuantity: _dn(json['max_quantity']),
    unitPrice: _d(json['unit_price']),
    startsAt: _date(json['starts_at']),
    endsAt: _date(json['ends_at']),
    isActive: json['is_active'] == true,
  );

  final String id;
  final DecimalValue minQuantity;
  final DecimalValue? maxQuantity;
  final DecimalValue unitPrice;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;
}

final class PresentationData {
  const PresentationData({
    required this.id,
    required this.name,
    required this.conversionFactor,
    required this.salePrice,
    required this.isBase,
    required this.isSellable,
    required this.isPurchasable,
    required this.isActive,
    required this.tiers,
    this.barcode,
  });

  factory PresentationData.fromJson(Map<String, dynamic> json) => PresentationData(
    id: json['id'].toString(),
    name: json['name']?.toString() ?? '',
    barcode: json['barcode']?.toString(),
    conversionFactor: _d(json['conversion_factor']),
    salePrice: _d(json['sale_price']),
    isBase: json['is_base'] == true,
    isSellable: json['is_sellable'] == true,
    isPurchasable: json['is_purchasable'] == true,
    isActive: json['is_active'] == true,
    tiers: [for (final tier in (json['price_tiers'] as List? ?? const []).cast<Map>()) PriceTierData.fromJson(tier.cast<String, dynamic>())],
  );

  final String id;
  final String name;
  final String? barcode;
  final DecimalValue conversionFactor;
  final DecimalValue salePrice;
  final bool isBase;
  final bool isSellable;
  final bool isPurchasable;
  final bool isActive;
  final List<PriceTierData> tiers;
}

/// Who sells the product to us, at what cost, for which presentation.
final class SupplierLinkData {
  const SupplierLinkData({required this.id, required this.supplier, required this.presentationId, required this.costPrice, required this.isPreferred, required this.isActive, this.supplierSku, this.notes});

  factory SupplierLinkData.fromJson(Map<String, dynamic> json) => SupplierLinkData(
    id: json['id'].toString(),
    supplier: CatalogOption.fromJson(((json['supplier'] as Map?) ?? {'id': json['supplier_id'], 'name': ''}).cast<String, dynamic>()),
    presentationId: json['product_presentation_id'].toString(),
    supplierSku: json['supplier_sku']?.toString(),
    costPrice: _d(json['cost_price']),
    isPreferred: json['is_preferred'] == true,
    isActive: json['is_active'] == true,
    notes: json['notes']?.toString(),
  );

  final String id;
  final CatalogOption supplier;
  final String presentationId;
  final String? supplierSku;
  final DecimalValue costPrice;
  final bool isPreferred;
  final bool isActive;
  final String? notes;
}

/// A product as the server holds it, to edit.
final class ProductData {
  const ProductData({
    required this.id,
    required this.sku,
    required this.name,
    required this.category,
    required this.baseUnit,
    required this.allowsDecimal,
    required this.tracksLots,
    required this.tracksExpiration,
    required this.isActive,
    required this.presentations,
    required this.suppliers,
    this.brand,
    this.description,
  });

  factory ProductData.fromJson(Map<String, dynamic> json) => ProductData(
    id: json['id'].toString(),
    sku: json['sku']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    description: json['description']?.toString(),
    category: CatalogOption.fromJson((json['category'] as Map).cast<String, dynamic>()),
    brand: json['brand'] == null ? null : CatalogOption.fromJson((json['brand'] as Map).cast<String, dynamic>()),
    baseUnit: CatalogOption.fromJson((json['base_unit'] as Map).cast<String, dynamic>()),
    allowsDecimal: json['allows_decimal'] == true,
    tracksLots: json['tracks_lots'] == true,
    tracksExpiration: json['tracks_expiration'] == true,
    isActive: json['is_active'] == true,
    presentations: [for (final presentation in (json['presentations'] as List? ?? const []).cast<Map>()) PresentationData.fromJson(presentation.cast<String, dynamic>())],
    suppliers: [for (final link in (json['suppliers'] as List? ?? const []).cast<Map>()) SupplierLinkData.fromJson(link.cast<String, dynamic>())],
  );

  final String id;
  final String sku;
  final String name;
  final String? description;
  final CatalogOption category;
  final CatalogOption? brand;
  final CatalogOption baseUnit;
  final bool allowsDecimal;
  final bool tracksLots;
  final bool tracksExpiration;
  final bool isActive;
  final List<PresentationData> presentations;
  final List<SupplierLinkData> suppliers;

  String presentationName(String id) => presentations.where((presentation) => presentation.id == id).firstOrNull?.name ?? '';
}
