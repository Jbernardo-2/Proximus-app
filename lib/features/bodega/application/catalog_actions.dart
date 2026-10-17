import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../core/api.dart';
import '../../../data/database.dart';

final catalogActionsProvider = Provider.autoDispose<CatalogActions>((ref) => CatalogActions(ref));

/// The photo and barcodes a keeper fixes from the phone, online. The local catalog is
/// patched right away (the scanner needs the new code now) and refreshed after.
class CatalogActions {
  CatalogActions(this._ref);

  final Ref _ref;

  ProximusApi get _api => _ref.read(apiProvider) ?? (throw ApiException('Sin conexión con el servidor.'));

  /// Takes the photo with the camera or picks it from the gallery; false if none was chosen.
  Future<bool> replacePhoto(String productId, {required ImageSource source}) async {
    // A shelf photo is enough at this size and travels fast on a weak signal.
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (picked == null) return false;
    final response = await _api.upload('/products/$productId/photo', field: 'image', filePath: picked.path);
    final data = (response['data'] as Map).cast<String, dynamic>();
    await _patch(productId, (product) => {...product, 'image_url': data['image_url'], 'thumbnail_url': data['thumbnail_url'], 'image_version': data['image_version']});
    unawaited(_ref.read(productImagesProvider.notifier).update());
    return true;
  }

  /// Gives a presentation its barcode, or removes it with null.
  Future<void> setBarcode(String productId, String presentationId, String? barcode) async {
    final response = await _api.put('/products/$productId/presentations/$presentationId/barcode', {'barcode': barcode});
    final saved = (response['data'] as Map)['barcode'];
    await _patch(productId, (product) => {
      ...product,
      'presentations': [
        for (final presentation in (product['presentations'] as List? ?? const []).cast<Map>())
          presentation['id'] == presentationId ? {...presentation, 'barcode': saved} : presentation,
      ],
    });
  }

  Future<void> _patch(String productId, Map<String, dynamic> Function(Map<String, dynamic> product) change) async {
    final db = _ref.read(databaseProvider);
    final row = await (db.select(db.syncRecords)..where((r) => r.resource.equals('products') & r.id.equals(productId))).getSingleOrNull();
    if (row == null) return;
    await db.into(db.syncRecords).insertOnConflictUpdate(
      SyncRecordsCompanion.insert(resource: 'products', id: productId, data: jsonEncode(change(decodeRecord(row.data)))),
    );
    // The server lets a change settle a moment before the catalog download includes it.
    // The sync controller lives with the session, so it outlives this screen.
    final sync = _ref.read(syncProvider.notifier);
    unawaited(Future<void>.delayed(const Duration(seconds: 4), sync.sync));
  }
}
