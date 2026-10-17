import '../../../core/decimal_value.dart';
import '../../preventa/data/preventa_models.dart';
import 'warehouse_runs.dart';

/// A product as the warehouse sees it: every presentation and its stock in each warehouse.
final class WarehouseProduct {
  const WarehouseProduct({required this.product, required this.stocks});

  final LocalProduct product;

  /// By warehouse id; a warehouse without a stock row has none of it.
  final Map<String, LocalStock> stocks;

  DecimalValue onHandIn(String? warehouseId) => warehouseId == null ? DecimalValue.zero : stocks[warehouseId]?.onHand ?? DecimalValue.zero;

  LocalPresentation? presentationWithBarcode(String code) =>
      product.presentations.where((presentation) => presentation.barcode != null && presentation.barcode == code).firstOrNull;
}

/// Active products (sellable or not, the warehouse handles both) with their stock, by name.
List<WarehouseProduct> warehouseProducts({required List<Map<String, dynamic>> products, required List<Map<String, dynamic>> stocks}) {
  final byProduct = <String, Map<String, LocalStock>>{};
  for (final json in stocks) {
    final stock = LocalStock.fromJson(json);
    byProduct.putIfAbsent(stock.productId, () => {})[stock.warehouseId] = stock;
  }
  return [
    for (final json in products)
      if (json['deleted'] != true && json['is_active'] == true)
        WarehouseProduct(product: LocalProduct.fromJson(json), stocks: byProduct[json['id'].toString()] ?? const {}),
  ]..sort((a, b) => a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase()));
}

/// Every word must appear in the name, code, brand, category or a barcode.
List<WarehouseProduct> searchWarehouseProducts(List<WarehouseProduct> products, String query) {
  final terms = query.toLowerCase().split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
  if (terms.isEmpty) return products;
  return [
    for (final item in products)
      if (terms.every([
        item.product.name,
        item.product.sku,
        item.product.brand ?? '',
        item.product.category ?? '',
        for (final presentation in item.product.presentations) presentation.barcode ?? '',
      ].join(' ').toLowerCase().contains))
        item,
  ];
}

/// The product a scanned code belongs to, or null when no presentation has it.
WarehouseProduct? productForBarcode(List<WarehouseProduct> products, String code) {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return null;
  return products.where((item) => item.presentationWithBarcode(trimmed) != null).firstOrNull;
}

/// What waits for the warehouse, from the downloaded runs and orders.
final class WarehouseWork {
  const WarehouseWork({
    required this.ordersWaiting,
    required this.drafts,
    required this.preparingMine,
    required this.preparingOthers,
    required this.loaded,
  });

  factory WarehouseWork.of({required List<WarehouseRun> runs, required int ordersWaiting, required int userId}) {
    final preparing = runs.where((run) => run.isPreparing);
    bool mine(WarehouseRun run) => run.preparationStartedBy == userId;
    return WarehouseWork(
      ordersWaiting: ordersWaiting,
      drafts: runs.where((run) => run.isDraft).length,
      preparingMine: preparing.where(mine).length,
      preparingOthers: preparing.where((run) => !mine(run)).length,
      loaded: runs.where((run) => run.isLoaded).length,
    );
  }

  final int ordersWaiting;
  final int drafts;
  final int preparingMine;
  final int preparingOthers;
  final int loaded;
}
