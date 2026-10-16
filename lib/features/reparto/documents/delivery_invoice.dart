import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../preventa/documents/payment_receipt.dart' show ReceiptFormat;

/// Everything printed on a delivery invoice, frozen when it is issued so it can be
/// reprinted the same way, with or without signal.
final class DeliveryInvoice {
  const DeliveryInvoice({
    required this.number,
    required this.issuedAt,
    required this.company,
    required this.customerName,
    required this.customerCode,
    required this.customerAddress,
    required this.runNumber,
    required this.deliveredBy,
    required this.receiverName,
    required this.items,
    required this.lines,
    required this.total,
    this.orderNumber,
  });

  factory DeliveryInvoice.fromJson(Map<String, dynamic> json) => DeliveryInvoice(
    number: json['number'] as String,
    issuedAt: DateTime.parse(json['issued_at'] as String),
    company: (json['company'] as Map? ?? const {}).cast<String, dynamic>(),
    customerName: json['customer_name'] as String? ?? '',
    customerCode: json['customer_code'] as String? ?? '',
    customerAddress: json['customer_address'] as String? ?? '',
    runNumber: json['run_number'] as String? ?? '',
    orderNumber: json['order_number'] as String?,
    deliveredBy: json['delivered_by'] as String? ?? '',
    receiverName: json['receiver_name'] as String? ?? '',
    items: [
      for (final item in json['items'] as List? ?? const [])
        (name: (item as Map)['name'].toString(), presentation: item['presentation'].toString(), quantity: DecimalValue.parse(item['quantity']), unitPrice: DecimalValue.parse(item['unit_price'])),
    ],
    lines: [
      for (final line in json['lines'] as List? ?? const [])
        (
          label: (line as Map)['label'].toString(),
          reference: line['reference'] as String?,
          receiptNumber: line['receipt_number'] as String?,
          amount: DecimalValue.parse(line['amount']),
          isCredit: line['is_credit'] == true,
        ),
    ],
    total: DecimalValue.parse(json['total']),
  );

  final String number;
  final DateTime issuedAt;
  final Map<String, dynamic> company;
  final String customerName;
  final String customerCode;
  final String customerAddress;
  final String runNumber;
  final String? orderNumber;
  final String deliveredBy;
  final String receiverName;
  final List<({String name, String presentation, DecimalValue quantity, DecimalValue unitPrice})> items;
  final List<({String label, String? reference, String? receiptNumber, DecimalValue amount, bool isCredit})> lines;
  final DecimalValue total;

  DecimalValue get paid => lines.where((line) => !line.isCredit).fold(DecimalValue.zero, (sum, line) => sum + line.amount);
  DecimalValue get onCredit => total - paid;

  Map<String, dynamic> toJson() => {
    'number': number,
    'issued_at': issuedAt.toIso8601String(),
    'company': company,
    'customer_name': customerName,
    'customer_code': customerCode,
    'customer_address': customerAddress,
    'run_number': runNumber,
    'order_number': orderNumber,
    'delivered_by': deliveredBy,
    'receiver_name': receiverName,
    'items': [
      for (final item in items) {'name': item.name, 'presentation': item.presentation, 'quantity': item.quantity.toString(), 'unit_price': item.unitPrice.toString()},
    ],
    'lines': [
      for (final line in lines) {'label': line.label, 'reference': line.reference, 'receipt_number': line.receiptNumber, 'amount': line.amount.toString(), 'is_credit': line.isCredit},
    ],
    'total': total.toString(),
  };

  String get filename => 'factura-${number.toLowerCase()}.pdf';
}

/// The invoice as a PDF: an 80 mm roll for thermal printers or a letter page.
Future<Uint8List> buildInvoicePdf(DeliveryInvoice invoice, ReceiptFormat format) async {
  final ticket = format == ReceiptFormat.ticket;
  final base = ticket ? 8.0 : 10.0;
  final small = pw.TextStyle(fontSize: base - 1);
  final normal = pw.TextStyle(fontSize: base);
  final bold = pw.TextStyle(fontSize: base, fontWeight: pw.FontWeight.bold);
  final title = pw.TextStyle(fontSize: base + 4, fontWeight: pw.FontWeight.bold);
  final company = invoice.company;

  pw.Widget row(String label, String value, {pw.TextStyle? style}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: pw.Text(label, style: style ?? normal)),
        pw.Text(value, style: style ?? normal),
      ],
    ),
  );

  String? field(String key) => (company[key] ?? '').toString().isEmpty ? null : company[key].toString();

  final content = <pw.Widget>[
    pw.Center(
      child: pw.Text(field('commercial_name') ?? 'Proximus', style: title, textAlign: pw.TextAlign.center),
    ),
    if (field('legal_name') != null) pw.Center(child: pw.Text(field('legal_name')!, style: small)),
    if (field('rtn') != null) pw.Center(child: pw.Text('RTN ${field('rtn')}', style: small)),
    if (field('address') != null)
      pw.Center(
        child: pw.Text(field('address')!, style: small, textAlign: pw.TextAlign.center),
      ),
    if (field('phone') != null) pw.Center(child: pw.Text('Tel. ${field('phone')}', style: small)),
    pw.SizedBox(height: 8),
    pw.Center(child: pw.Text('FACTURA DE ENTREGA', style: bold)),
    pw.Center(child: pw.Text(invoice.number, style: bold)),
    pw.Center(child: pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(invoice.issuedAt), style: small)),
    pw.Divider(thickness: 0.5),
    pw.Text('Cliente: ${invoice.customerName}', style: normal),
    if (invoice.customerCode.isNotEmpty) pw.Text('Código: ${invoice.customerCode}', style: small),
    if (invoice.customerAddress.isNotEmpty) pw.Text(invoice.customerAddress, style: small),
    pw.Text('Jornada ${invoice.runNumber}${invoice.orderNumber == null ? '' : ' · Pedido ${invoice.orderNumber}'}', style: small),
    pw.Divider(thickness: 0.5),
    for (final item in invoice.items)
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(item.name, style: normal),
            row('  ${item.quantity} × ${item.presentation} @ ${money(item.unitPrice)}', money(item.quantity * item.unitPrice), style: small),
          ],
        ),
      ),
    pw.Divider(thickness: 0.5),
    row('TOTAL', money(invoice.total), style: bold),
    pw.SizedBox(height: 4),
    pw.Text('Forma de pago', style: bold),
    for (final line in invoice.lines)
      row([line.label, if ((line.reference ?? '').isNotEmpty) line.reference!, if (line.receiptNumber != null) 'Recibo ${line.receiptNumber}'].join(' · '), money(line.amount)),
    if (!invoice.onCredit.isZero) row('Saldo a crédito', money(invoice.onCredit), style: bold),
    pw.SizedBox(height: 10),
    pw.Text('Entregó: ${invoice.deliveredBy}', style: small),
    if (invoice.receiverName.isNotEmpty) pw.Text('Recibió: ${invoice.receiverName}', style: small),
    pw.SizedBox(height: 18),
    pw.Center(child: pw.Text('______________________________', style: small)),
    pw.Center(child: pw.Text('Firma del cliente', style: small)),
    pw.SizedBox(height: 6),
    pw.Center(child: pw.Text('Documento interno no fiscal', style: small)),
    pw.Center(child: pw.Text('¡Gracias por su compra!', style: small)),
  ];

  final document = pw.Document(title: invoice.number);
  if (ticket) {
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(8),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: content),
      ),
    );
  } else {
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(48),
        build: (_) => pw.Center(
          child: pw.Container(
            width: 320,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, mainAxisSize: pw.MainAxisSize.min, children: content),
          ),
        ),
      ),
    );
  }
  return document.save();
}
