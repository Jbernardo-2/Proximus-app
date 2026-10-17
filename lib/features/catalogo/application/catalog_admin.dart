import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api.dart';
import '../data/catalog_models.dart';

ProximusApi _api(Ref ref) => ref.read(apiProvider) ?? (throw ApiException('Sin conexión con el servidor.'));

/// A product read now from the server, with its presentations, prices and suppliers.
final productDataProvider = FutureProvider.autoDispose.family<ProductData, String>((ref, id) async {
  ref.watch(apiProvider);
  final response = await _api(ref).get('/products/$id');
  return ProductData.fromJson((response['data'] as Map).cast<String, dynamic>());
});

/// Categories, brands, units or suppliers matching what is typed.
final catalogOptionsProvider = FutureProvider.autoDispose.family<List<CatalogOption>, ({OptionKind kind, String search})>((ref, query) async {
  ref.watch(apiProvider);
  final response = await _api(ref).get(query.kind.path, query: {'search': query.search, 'per_page': 100});
  return [for (final json in (response['data'] as List).cast<Map>()) CatalogOption.fromJson(json.cast<String, dynamic>())];
});

final catalogAdminProvider = Provider.autoDispose<CatalogAdmin>((ref) => CatalogAdmin(ref));

/// Products, presentations, prices and suppliers changed from the phone, online. After each
/// change the phone catalog (search, scanner, orders) refreshes from the server.
class CatalogAdmin {
  CatalogAdmin(this._ref);

  final Ref _ref;

  Future<Map<String, dynamic>> _send(Future<Map<String, dynamic>> Function(ProximusApi api) call, {String? productId}) async {
    final response = await call(_api(_ref));
    if (productId != null) _ref.invalidate(productDataProvider(productId));
    // The server lets a change settle a moment before the catalog download includes it;
    // the sync controller lives with the session, so it outlives this screen.
    final sync = _ref.read(syncProvider.notifier);
    unawaited(Future<void>.delayed(const Duration(seconds: 4), sync.sync));
    return response;
  }

  Future<CatalogOption> createOption(OptionKind kind, String name, {String? symbol}) async {
    final response = await _api(_ref).post(kind.path, kind.create(name.trim(), symbol: symbol?.trim()));
    return CatalogOption.fromJson((response['data'] as Map).cast<String, dynamic>());
  }

  /// Returns the new product's id.
  Future<String> createProduct(Map<String, dynamic> payload) async {
    final response = await _send((api) => api.post('/products', payload));
    return (response['data'] as Map)['id'].toString();
  }

  Future<void> updateProduct(String productId, Map<String, dynamic> payload) => _send((api) => api.put('/products/$productId', payload), productId: productId);

  Future<void> savePresentation(String productId, String? presentationId, Map<String, dynamic> payload) => _send(
    (api) => presentationId == null ? api.post('/products/$productId/presentations', payload) : api.put('/products/$productId/presentations/$presentationId', payload),
    productId: productId,
  );

  Future<void> saveTier(String productId, String presentationId, String? tierId, Map<String, dynamic> payload) => _send(
    (api) => tierId == null
        ? api.post('/products/$productId/presentations/$presentationId/price-tiers', payload)
        : api.put('/products/$productId/presentations/$presentationId/price-tiers/$tierId', payload),
    productId: productId,
  );

  Future<void> saveSupplierLink(String productId, String? linkId, Map<String, dynamic> payload) => _send(
    (api) => linkId == null ? api.post('/products/$productId/suppliers', payload) : api.put('/products/$productId/suppliers/$linkId', payload),
    productId: productId,
  );
}
