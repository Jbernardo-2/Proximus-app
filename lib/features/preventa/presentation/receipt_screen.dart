import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../app/theme.dart';
import '../../../core/formatting.dart';
import '../documents/payment_receipt.dart';

/// The receipt just issued (or reprinted): print it as a ticket or letter, share it, or finish.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.receipt, this.justIssued = false});

  final PaymentReceipt receipt;
  final bool justIssued;

  Future<void> _print(BuildContext context, ReceiptFormat format) async {
    try {
      await Printing.layoutPdf(
        name: receipt.number,
        format: format == ReceiptFormat.ticket ? PdfPageFormat.roll80 : PdfPageFormat.letter,
        onLayout: (_) => buildReceiptPdf(receipt, format),
      );
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo imprimir: $error')));
    }
  }

  Future<void> _share(BuildContext context) async {
    try {
      await Printing.sharePdf(bytes: await buildReceiptPdf(receipt, ReceiptFormat.letter), filename: receipt.filename);
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo compartir: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Comprobante'), automaticallyImplyLeading: !justIssued),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (justIssued)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: const Color(0xFFE7F5EF), borderRadius: BorderRadius.circular(12)),
                child: const Text('Abono guardado en el teléfono. Se enviará al servidor en cuanto haya señal.', style: TextStyle(color: AppColors.brand)),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(receipt.number, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(DateFormat('dd/MM/yyyy HH:mm').format(receipt.issuedAt), style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 8),
                  Text(receipt.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Divider(height: 24),
                  for (final line in receipt.lines)
                    _Row(label: '${line.label}${(line.reference ?? '').isEmpty ? '' : ' · ${line.reference}'}', value: money(line.amount)),
                  const Divider(height: 24),
                  for (final item in receipt.allocations) _Row(label: item.document, value: money(item.applied), muted: true),
                  const Divider(height: 24),
                  _Row(label: 'Total abonado', value: money(receipt.total), strong: true),
                  _Row(label: 'Saldo pendiente', value: money(receipt.debtAfter)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () => _print(context, ReceiptFormat.ticket), icon: const Icon(Icons.receipt_long), label: const Text('Imprimir ticket 80 mm')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => _print(context, ReceiptFormat.letter),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Imprimir carta'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => _share(context),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartir'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Terminar')),
          ],
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.strong = false, this.muted = false});

  final String label;
  final String value;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w500, color: muted ? AppColors.muted : AppColors.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]),
    );
  }
}
