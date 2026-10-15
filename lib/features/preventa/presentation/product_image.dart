import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';

/// Thumbnail of a product from the phone, or an icon while there is none. It is
/// decoded at the size it is drawn, so long lists stay light on memory.
class ProductImage extends ConsumerWidget {
  const ProductImage({super.key, required this.productId, this.size = 48});

  final String? productId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = productId == null ? null : ref.watch(productImagesProvider.select((images) => images[productId]));
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: const Color(0xFFF1F1EF), borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.inventory_2_outlined, size: size * 0.5, color: AppColors.muted),
    );
    if (path == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
