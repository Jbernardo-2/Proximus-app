import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../preventa/documents/payment_receipt.dart' show ReceiptFormat;
import '../data/delivery_models.dart';
import '../data/run_closing.dart';

/// The run closing as a PDF to print or share with the supervisor.
Future<Uint8List> buildRunClosingPdf({
  required LocalDeliveryRun run,
  required RunClosing closing,
  required String driver,
  required Map<String, String> methodLabels,
  required ReceiptFormat format,
  DateTime? at,
}) async {
  final ticket = format == ReceiptFormat.ticket;
  final base = ticket ? 8.0 : 10.0;
  final small = pw.TextStyle(fontSize: base - 1);
  final normal = pw.TextStyle(fontSize: base);
  final bold = pw.TextStyle(fontSize: base, fontWeight: pw.FontWeight.bold);
  final title = pw.TextStyle(fontSize: base + 3, fontWeight: pw.FontWeight.bold);

  pw.Widget row(String label, String value, {pw.TextStyle? style}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label, style: style ?? normal)),
        pw.Text(value, style: style ?? normal),
      ],
    ),
  );
  String label(String method) => methodLabels[method] ?? method;

  final content = <pw.Widget>[
    pw.Center(child: pw.Text('CIERRE DE JORNADA', style: title)),
    pw.Center(child: pw.Text(run.runNumber, style: bold)),
    pw.Center(child: pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(at ?? DateTime.now()), style: small)),
    pw.Text('Repartidor: $driver', style: small),
    if (run.vehicleCode != null) pw.Text('Camión: ${run.vehicleCode}', style: small),
    if (!closing.isFinal) pw.Text('PRELIMINAR: hay paradas abiertas u operaciones sin enviar.', style: bold),
    pw.Divider(thickness: 0.5),
    pw.Text('Paradas (${run.stops.length})', style: bold),
    row('Entregadas', '${closing.delivered}'),
    row('Entrega parcial', '${closing.partial}'),
    row('No entregadas', '${closing.notDelivered}'),
    if (closing.open > 0) row('Sin terminar', '${closing.open}'),
    pw.Divider(thickness: 0.5),
    pw.Text('Cobrado por forma de pago', style: bold),
    for (final entry in closing.byMethod.entries) row(label(entry.key), money(entry.value)),
    row('Total cobrado', money(closing.collected), style: bold),
    if (closing.accountPaymentCount > 0) row('  incluye ${closing.accountPaymentCount} abonos a cuenta', money(closing.accountPayments.values.fold(DecimalValue.zero, (a, b) => a + b)), style: small),
    row('Crédito otorgado', money(closing.credit)),
    pw.SizedBox(height: 4),
    row('EFECTIVO A ENTREGAR', money(closing.cash), style: title),
    if (closing.returns.isNotEmpty) ...[
      pw.Divider(thickness: 0.5),
      pw.Text('Mercadería que regresa', style: bold),
      for (final item in closing.returns)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('${item.product} · ${item.presentation}', style: normal),
              pw.Text(
                [if (!item.returned.isZero) 'devuelto ${item.returned}', if (!item.damaged.isZero) 'dañado ${item.damaged}', if (!item.missing.isZero) 'faltó ${item.missing}'].join(' · '),
                style: small,
              ),
            ],
          ),
        ),
    ],
    pw.SizedBox(height: 22),
    pw.Row(
      children: [
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Text('______________', style: small),
              pw.Text('Repartidor', style: small),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Text('______________', style: small),
              pw.Text('Supervisor', style: small),
            ],
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 6),
    pw.Center(child: pw.Text('Conteo del repartidor; la liquidación se hace en la web.', style: small)),
  ];

  final document = pw.Document(title: 'Cierre ${run.runNumber}');
  document.addPage(
    pw.Page(
      pageFormat: ticket ? PdfPageFormat.roll80 : PdfPageFormat.letter,
      margin: pw.EdgeInsets.all(ticket ? 8 : 48),
      build: (_) => ticket
          ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: content)
          : pw.Center(
              child: pw.Container(
                width: 340,
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, mainAxisSize: pw.MainAxisSize.min, children: content),
              ),
            ),
    ),
  );
  return document.save();
}
