import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../application/receipt_actions.dart';
import '../data/receipts.dart';
import 'online.dart';

final _date = DateFormat('d MMM yyyy', 'es');

/// Merchandise that came in lately: supplier receipts, customer returns and adjustments.
class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Entradas')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => context.push('/receipts/new'), icon: const Icon(Icons.add), label: const Text('Nueva entrada')),
      body: receipts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LiveError(error: error, onRetry: () => ref.invalidate(receiptsProvider)),
        data: (receipts) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(receiptsProvider),
          child: receipts.isEmpty
              ? ListView(children: const [
                  Padding(padding: EdgeInsets.all(32), child: Text('Registra aquí la mercadería que entra a bodega.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: receipts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ReceiptTile(receipt: receipts[index]),
                ),
        ),
      ),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({required this.receipt});

  final PostedReceipt receipt;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.move_to_inbox_outlined)),
      title: Text(receipt.number, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([receipt.typeLabel, ?receipt.supplier, ?receipt.reference, _date.format(receipt.occurredOn)].join(' · ')),
      trailing: Text('${receipt.itemsCount} ${receipt.itemsCount == 1 ? 'línea' : 'líneas'}', style: const TextStyle(color: AppColors.muted)),
      onTap: () => context.push('/receipts/${receipt.id}'),
    ),
  );
}

class ReceiptDetailScreen extends ConsumerWidget {
  const ReceiptDetailScreen({super.key, required this.receiptId});

  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(receiptDetailProvider(receiptId));
    return Scaffold(
      appBar: AppBar(title: Text(receipt.value?.number ?? 'Entrada')),
      body: receipt.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LiveError(error: error, onRetry: () => ref.invalidate(receiptDetailProvider(receiptId))),
        data: (receipt) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(receipt.typeLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text([?receipt.supplier, ?receipt.reference, _date.format(receipt.occurredOn), ?receipt.createdBy].join(' · '), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            for (final item in receipt.items)
              Card(
                child: ListTile(
                  title: Text(item.product, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([item.presentation, if (item.lot != null) 'Lote ${item.lot}'].join(' · ')),
                  trailing: Text('${item.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
