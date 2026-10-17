import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/theme.dart';

/// Opens the camera and returns the first code read, or null if the user goes back.
Future<String?> scanBarcode(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.map((barcode) => barcode.rawValue?.trim()).whereType<String>().where((code) => code.isNotEmpty).firstOrNull;
    if (code == null || _done) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear código'),
        actions: [IconButton(tooltip: 'Linterna', icon: const Icon(Icons.flashlight_on_outlined), onPressed: _controller.toggleTorch)],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(denied: error.errorCode == MobileScannerErrorCode.permissionDenied),
          ),
          // A frame to aim with; the whole image is read anyway.
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Text(
              'Apunta al código de barras del producto',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.denied});

  final bool denied;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 44, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              denied ? 'La app no tiene permiso para usar la cámara.' : 'No se pudo abrir la cámara.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              denied ? 'Actívalo en Ajustes del teléfono > Aplicaciones > Proximus > Permisos.' : 'Cierra esta pantalla e intenta de nuevo.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}
