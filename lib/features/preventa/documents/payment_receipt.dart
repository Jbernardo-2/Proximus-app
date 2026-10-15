import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';

/// Everything printed on an account payment receipt, frozen when it is issued so
/// it can be reprinted the same way, with or without signal.
final class PaymentReceipt {
  const PaymentReceipt({
    required this.number,
    required this.issuedAt,
    required this.company,
    required this.customerName,
    required this.customerCode,
    required this.collectedBy,
    required this.lines,
    required this.allocations,
    required this.total,
    required this.debtBefore,
  });

  factory PaymentReceipt.fromJson(Map<String, dynamic> json) => PaymentReceipt(
        number: json['number'] as String,
        issuedAt: DateTime.parse(json['issued_at'] as String),
        company: (json['company'] as Map? ?? const {}).cast<String, dynamic>(),
        customerName: json['customer_name'] as String? ?? '',
        customerCode: json['customer_code'] as String? ?? '',
        collectedBy: json['collected_by'] as String? ?? '',
        lines: [
          for (final line in json['lines'] as List? ?? const [])
            (label: (line as Map)['label'].toString(), reference: line['reference'] as String?, amount: DecimalValue.parse(line['amount'])),
        ],
        allocations: [
          for (final item in json['allocations'] as List? ?? const [])
            (
              document: (item as Map)['document'].toString(),
              before: DecimalValue.parse(item['before']),
              applied: DecimalValue.parse(item['applied']),
            ),
        ],
        total: DecimalValue.parse(json['total']),
        debtBefore: DecimalValue.parse(json['debt_before']),
      );

  final String number;
  final DateTime issuedAt;
  final Map<String, dynamic> company;
  final String customerName;
  final String customerCode;
  final String collectedBy;
  final List<({String label, String? reference, DecimalValue amount})> lines;
  final List<({String document, DecimalValue before, DecimalValue applied})> allocations;
  final DecimalValue total;
  final DecimalValue debtBefore;

  DecimalValue get debtAfter => debtBefore - total;

  Map<String, dynamic> toJson() => {
        'number': number,
        'issued_at': issuedAt.toIso8601String(),
        'company': company,
        'customer_name': customerName,
        'customer_code': customerCode,
        'collected_by': collectedBy,
        'lines': [
          for (final line in lines) {'label': line.label, 'reference': line.reference, 'amount': line.amount.toString()},
        ],
        'allocations': [
          for (final item in allocations) {'document': item.document, 'before': item.before.toString(), 'applied': item.applied.toString()},
        ],
        'total': total.toString(),
        'debt_before': debtBefore.toString(),
      };

  String get filename => 'comprobante-${number.toLowerCase()}.pdf';
}

enum ReceiptFormat { ticket, letter }

/// The receipt as a PDF: an 80 mm roll for thermal printers or a letter page.
Future<Uint8List> buildReceiptPdf(PaymentReceipt receipt, ReceiptFormat format) async {
  final ticket = format == ReceiptFormat.ticket;
  final base = ticket ? 8.0 : 10.0;
  final small = pw.TextStyle(fontSize: base - 1);
  final normal = pw.TextStyle(fontSize: base);
  final bold = pw.TextStyle(fontSize: base, fontWeight: pw.FontWeight.bold);
  final title = pw.TextStyle(fontSize: base + 4, fontWeight: pw.FontWeight.bold);
  final date = DateFormat('dd/MM/yyyy HH:mm').format(receipt.issuedAt);
  final company = receipt.company;

  pw.Widget row(String label, String value, {pw.TextStyle? style}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [pw.Expanded(child: pw.Text(label, style: style ?? normal)), pw.Text(value, style: style ?? normal)]),
      );

  final content = <pw.Widget>[
    pw.Center(child: pw.Text((company['commercial_name'] ?? 'Proximus').toString(), style: title, textAlign: pw.TextAlign.center)),
    if ((company['legal_name'] ?? '').toString().isNotEmpty) pw.Center(child: pw.Text(company['legal_name'].toString(), style: small)),
    if ((company['rtn'] ?? '').toString().isNotEmpty) pw.Center(child: pw.Text('RTN ${company['rtn']}', style: small)),
    if ((company['address'] ?? '').toString().isNotEmpty) pw.Center(child: pw.Text(company['address'].toString(), style: small, textAlign: pw.TextAlign.center)),
    if ((company['phone'] ?? '').toString().isNotEmpty) pw.Center(child: pw.Text('Tel. ${company['phone']}', style: small)),
    pw.SizedBox(height: 8),
    pw.Center(child: pw.Text('COMPROBANTE DE ABONO', style: bold)),
    pw.Center(child: pw.Text(receipt.number, style: bold)),
    pw.Center(child: pw.Text(date, style: small)),
    pw.Divider(thickness: 0.5),
    pw.Text('Cliente: ${receipt.customerName}', style: normal),
    if (receipt.customerCode.isNotEmpty) pw.Text('Código: ${receipt.customerCode}', style: small),
    pw.Divider(thickness: 0.5),
    pw.Text('Forma de pago', style: bold),
    for (final line in receipt.lines) row('${line.label}${(line.reference ?? '').isEmpty ? '' : ' · ${line.reference}'}', money(line.amount)),
    pw.Divider(thickness: 0.5),
    pw.Text('Aplicado a', style: bold),
    for (final item in receipt.allocations)
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          row(item.document, money(item.applied)),
          pw.Text('Saldo anterior ${money(item.before)} · nuevo ${money(item.before - item.applied)}', style: small),
        ]),
      ),
    pw.Divider(thickness: 0.5),
    row('TOTAL ABONADO', money(receipt.total), style: bold),
    row('Saldo anterior', money(receipt.debtBefore)),
    row('Saldo pendiente', money(receipt.debtAfter), style: bold),
    pw.SizedBox(height: 10),
    pw.Text('Recibió: ${receipt.collectedBy}', style: small),
    pw.SizedBox(height: 18),
    pw.Center(child: pw.Text('______________________________', style: small)),
    pw.Center(child: pw.Text('Firma del cliente', style: small)),
    pw.SizedBox(height: 6),
    pw.Center(child: pw.Text('Documento interno, no fiscal.', style: small)),
  ];

  final document = pw.Document(title: receipt.number);
  if (ticket) {
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(8),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: content),
    ));
  } else {
    document.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(48),
      build: (_) => pw.Center(
        child: pw.Container(
          width: 300,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, mainAxisSize: pw.MainAxisSize.min, children: content),
        ),
      ),
    ));
  }
  return document.save();
}
