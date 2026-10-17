import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme.dart';
import '../../../core/api.dart';
import '../../preventa/data/preventa_models.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/catalog_actions.dart';
import '../data/warehouse_catalog.dart';
import 'barcode_scanner_screen.dart';
import 'online.dart';
import 'product_search_screen.dart';

/// The product photo; tapping it replaces it with one from the camera or the gallery.
class EditablePhoto extends ConsumerStatefulWidget {
  const EditablePhoto({super.key, required this.productId, this.size = 96});

  final String productId;
  final double size;

  @override
  ConsumerState<EditablePhoto> createState() => _EditablePhotoState();
}

class _EditablePhotoState extends ConsumerState<EditablePhoto> {
  bool _uploading = false;

  Future<void> _replace() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de la galería'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _uploading = true);
    var changed = false;
    await runOnline(context, () async => changed = await ref.read(catalogActionsProvider).replacePhoto(widget.productId, source: source));
    if (!mounted) return;
    setState(() => _uploading = false);
    if (changed) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto actualizada. Los demás teléfonos la verán al sincronizar.')));
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: _uploading ? null : _replace,
    borderRadius: BorderRadius.circular(8),
    child: Stack(alignment: Alignment.center, children: [
      ProductImage(productId: widget.productId, size: widget.size),
      if (_uploading)
        const CircularProgressIndicator()
      else
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.photo_camera, size: 16, color: Colors.white),
          ),
        ),
    ]),
  );
}

/// Gives a presentation its barcode, typed or read with the camera.
Future<void> openBarcodeSheet(BuildContext context, String productId, LocalPresentation presentation, {String? code}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _BarcodeSheet(productId: productId, presentation: presentation, initial: code),
);

class _BarcodeSheet extends ConsumerStatefulWidget {
  const _BarcodeSheet({required this.productId, required this.presentation, this.initial});

  final String productId;
  final LocalPresentation presentation;
  final String? initial;

  @override
  ConsumerState<_BarcodeSheet> createState() => _BarcodeSheetState();
}

class _BarcodeSheetState extends ConsumerState<_BarcodeSheet> {
  late final _code = TextEditingController(text: widget.initial ?? widget.presentation.barcode ?? '');
  bool _saving = false;
  String? _refusal;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _save(String? barcode) async {
    setState(() {
      _saving = true;
      _refusal = null;
    });
    try {
      await ref.read(catalogActionsProvider).setBarcode(widget.productId, widget.presentation.id, barcode);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _refusal = error.isNetwork ? 'Sin conexión: no se guardó. Revisa la señal e intenta de nuevo.' : error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Código de ${widget.presentation.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      TextField(
        controller: _code,
        maxLength: 80,
        autofocus: widget.initial == null,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Código de barras',
          suffixIcon: IconButton(
            tooltip: 'Escanear',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final code = await scanBarcode(context);
              if (code != null) setState(() => _code.text = code);
            },
          ),
        ),
      ),
      if (_refusal != null)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Text(_refusal!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 12),
      Row(children: [
        if (widget.presentation.barcode != null) ...[
          Expanded(child: OutlinedButton(onPressed: _saving ? null : () => _save(null), child: const Text('Quitar código'))),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: FilledButton(
            onPressed: _saving || _code.text.trim().isEmpty || _code.text.trim() == widget.presentation.barcode ? null : () => _save(_code.text.trim()),
            child: Text(_saving ? 'Guardando…' : 'Guardar'),
          ),
        ),
      ]),
    ]),
  );
}

/// A scanned code nobody has: choose the product and presentation it belongs to.
Future<void> assignScannedCode(BuildContext context, String code) async {
  final item = await Navigator.of(context).push<WarehouseProduct>(
    MaterialPageRoute(builder: (context) => ProductSearchScreen(title: 'Asignar $code', onPick: (item) => Navigator.pop(context, item))),
  );
  if (item == null || !context.mounted) return;
  final presentations = [for (final presentation in item.product.presentations) if (presentation.isActive) presentation];
  final presentation = presentations.length == 1
      ? presentations.single
      : await showModalBottomSheet<LocalPresentation>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('¿De qué presentación es el código?', style: TextStyle(fontWeight: FontWeight.w700))),
              for (final presentation in presentations)
                ListTile(
                  title: Text(presentation.name),
                  subtitle: Text(presentation.barcode == null ? 'Sin código' : 'Hoy: ${presentation.barcode}'),
                  onTap: () => Navigator.pop(context, presentation),
                ),
            ]),
          ),
        );
  if (presentation == null || !context.mounted) return;
  await openBarcodeSheet(context, item.product.id, presentation, code: code);
}
