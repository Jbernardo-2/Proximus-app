import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/formatting.dart';
import '../data/order_detail.dart';
import '../data/preventa_models.dart';
import 'daily_route_screen.dart' show StatusChip;
import 'product_image.dart';

final _date = DateFormat('dd/MM/yyyy');

/// Opens an order by the phone's client reference or the server id.
void openOrder(BuildContext context, String key) => context.push('/orders/${Uri.encodeComponent(key)}');

/// An order already taken, to look at. Nothing can be changed here: it was confirmed
/// when it was saved; changes go through the supervisor.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderKey});

  final String orderKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderDetailProvider(orderKey));
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Este pedido ya no está en el teléfono. El teléfono guarda los pedidos de los últimos 30 días.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ),
      );
    }
    final customer = ref.watch(customerProfileProvider(order.customerId))?.customer;
    final (sendLabel, sendColor) = switch (order.state) {
      LocalOperationState.pending => ('Por enviar', AppColors.amber),
      LocalOperationState.rejected => ('Rechazado', AppColors.danger),
      _ => ('Confirmado', AppColors.brand),
    };

    return Scaffold(
      appBar: AppBar(title: Text(order.reference)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(customer?.businessName ?? 'Cliente', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(text: sendLabel, color: sendColor),
                ]),
                if (order.state == LocalOperationState.synchronized && order.statusLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Estado: ${order.statusLabel}', style: const TextStyle(color: AppColors.muted)),
                  ),
                const SizedBox(height: 12),
                _Fact(label: 'Fecha del pedido', value: _date.format(order.orderDate)),
                if (order.deliveryDate != null) _Fact(label: 'Entrega', value: _date.format(order.deliveryDate!)),
                _Fact(label: 'Pago', value: order.paymentTerm == 'credit' ? 'Crédito' : 'Contado'),
                if (order.notes != null) _Fact(label: 'Notas', value: order.notes!),
              ]),
            ),
          ),
          if (order.rejectionMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: Text(order.rejectionMessage!, style: const TextStyle(color: AppColors.danger)),
            ),
          ],
          const SizedBox(height: 16),
          Text('Productos (${order.lines.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final (index, line) in order.lines.indexed) ...[
                if (index > 0) const Divider(height: 1),
                _LineRow(line: line),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(money(order.total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 16),
          const Text(
            'El pedido quedó confirmado al guardarlo. Si hay que cambiarlo, avisa al supervisor.',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final OrderDetailLine line;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProductImage(productId: line.productId, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${line.quantity} × ${line.presentationName} · ${money(line.unitPrice)} c/u',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              if (line.notes != null) Text(line.notes!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(money(line.lineTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}
