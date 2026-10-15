import 'dart:io';

import 'api.dart';

/// Product thumbnails kept on the phone, so they show without signal. Each file is
/// named `<product id>_<image version>.jpg`: a new photo has a new version and replaces
/// the old file; a product without photo leaves nothing behind.
final class ProductImageStore {
  ProductImageStore(this.directory);

  final Directory directory;

  /// Thumbnails already on the phone, by product id.
  Future<Map<String, String>> index() async {
    if (!await directory.exists()) return {};
    final files = <String, String>{};
    await for (final entity in directory.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is! File || !name.endsWith('.jpg')) continue;
      final separator = name.lastIndexOf('_');
      if (separator <= 0) continue;
      files[name.substring(0, separator)] = entity.path;
    }
    return files;
  }

  /// Downloads what is missing and removes what is no longer used. Stops at the first
  /// failure (no signal, too many requests): the next sync picks up where this one left.
  /// [onSaved] reports each new file so the screens show it right away.
  Future<int> update({
    required List<Map<String, dynamic>> products,
    required ProximusApi api,
    void Function(String productId, String path)? onSaved,
  }) async {
    await directory.create(recursive: true);
    final wanted = <String, ({String url, String file})>{
      for (final product in products)
        if (product['deleted'] != true && product['thumbnail_url'] != null && product['image_version'] != null)
          product['id'].toString(): (
            url: product['thumbnail_url'].toString(),
            file: '${directory.path}/${product['id']}_${product['image_version']}.jpg',
          ),
    };

    final keep = {for (final item in wanted.values) File(item.file).uri.pathSegments.last};
    await for (final entity in directory.list()) {
      if (entity is File && !keep.contains(entity.uri.pathSegments.last)) {
        await entity.delete().catchError((_) => entity);
      }
    }

    var saved = 0;
    for (final MapEntry(key: productId, value: item) in wanted.entries) {
      if (await File(item.file).exists()) continue;
      try {
        await api.download(item.url, item.file);
      } on ApiException catch (error) {
        if (error.status == 404) continue; // The photo is gone on the server; try the others.
        break;
      }
      saved++;
      onSaved?.call(productId, item.file);
    }
    return saved;
  }
}
