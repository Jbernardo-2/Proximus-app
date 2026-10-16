import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/external_apps.dart';
import '../../../core/formatting.dart';
import '../../preventa/presentation/daily_route_screen.dart' show StatusChip;
import '../../preventa/presentation/product_image.dart';
import 'package:go_router/go_router.dart';

import '../../preventa/data/preventa_models.dart' show LocalOperationState;
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';
import '../documents/delivery_invoice.dart';
import 'delivery_invoice_screen.dart';

/// Everything the driver needs at the customer's door: who, how to reach them, how
/// it is paid and exactly what was loaded for them.
class DeliveryStopScreen extends ConsumerWidget {
  const DeliveryStopScreen({super.key, required this.runId, required this.stopId});

  final String runId;
  final String stopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(deliveryRunProvider(runId));
    final stop = run?.stops.where((item) => item.id == stopId).firstOrNull;
    if (run == null || stop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Parada')),
        body: const Center(
          child: Text('Esta parada ya no está en el teléfono.', style: TextStyle(color: AppColors.muted)),
        ),
      );
    }
    final balance = ref.watch(customerBalancesProvider)[stop.customerId];
    // Old debts the driver can collect at the door, apart from this delivery.
    final canCollect = ref.watch(manifestProvider).value?.supports('customer.payment') ?? false;
    final debts = canCollect ? ref.watch(customerProfileProvider(stop.customerId))?.receivables ?? const [] : const [];
    final customer = stop.customer;
    final phone = customer?.phone ?? customer?.whatsapp;
    final whatsapp = customer?.whatsapp ?? customer?.phone;

    return Scaffold(
      appBar: AppBar(title: Text('Parada ${stop.visitOrder} de ${run.stops.length}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(stop.customerName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(stop.customerAddress, style: const TextStyle(color: AppColors.muted)),
          if (customer?.reference != null)
            Text(
              customer!.reference!,
              style: const TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic),
            ),
          if (customer?.contactName != null) ...[const SizedBox(height: 4), Text('Contacto: ${customer!.contactName}')],
          const SizedBox(height: 12),
          Row(
            children: [
              _Action(icon: Icons.call_outlined, label: 'Llamar', onTap: phone == null ? null : () => _open(context, ExternalApps.call(phone))),
              _Action(icon: Icons.chat_outlined, label: 'WhatsApp', onTap: whatsapp == null ? null : () => _open(context, ExternalApps.whatsapp(whatsapp))),
              _Action(
                icon: Icons.map_outlined,
                label: 'Cómo llegar',
                onTap: () => _open(
                  context,
                  ExternalApps.map(
                    latitude: customer?.latitude,
                    longitude: customer?.longitude,
                    label: customer?.hasLocation ?? false ? stop.customerName : '${stop.customerAddress} ${stop.customerName}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PaymentCard(stop: stop, available: balance?.allowsCredit ?? false ? balance!.available : null, allowsCredit: balance?.allowsCredit, overdue: balance?.overdue),
          if (debts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Deudas anteriores', style: TextStyle(color: AppColors.muted)),
                          Text(
                            money(debts.fold(DecimalValue.zero, (sum, debt) => sum + debt.outstanding)),
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: debts.any((debt) => debt.isOverdue) ? AppColors.danger : AppColors.ink),
                          ),
                          Text('${debts.length} ${debts.length == 1 ? 'documento' : 'documentos'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/payment/${stop.customerId}'),
                      icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                      label: const Text('Recibir abono'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Productos (${stop.items.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              if (stop.orderNumber != null)
                Expanded(
                  child: Text(
                    stop.orderNumber!,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final (index, item) in stop.items.indexed) ...[if (index > 0) const Divider(height: 1), _ItemRow(item: item)],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Total cargado', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(money(stop.loadedTotal), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
          if (stop.hasShortItems)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('La bodega cargó menos de lo pedido en algún producto: el cliente solo paga lo que se le entrega.', style: TextStyle(fontSize: 12, color: AppColors.amber)),
            ),
          if (stop.hasOutcome) ...[const SizedBox(height: 16), _RecordedOutcome(stop: stop)],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: switch (stop.progress) {
            StopProgress.pending => FilledButton.icon(
              onPressed: () => context.push('/deliveries/$runId/stops/$stopId/outcome'),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Registrar entrega'),
            ),
            StopProgress.awaitingPayment => FilledButton.icon(
              onPressed: () => context.push('/deliveries/$runId/stops/$stopId/payment'),
              icon: const Icon(Icons.payments_outlined),
              label: Text(stop.isCredit ? 'Registrar cobro' : 'Cobrar ${money(stop.balanceDue)}'),
            ),
            StopProgress.done when stop.invoice != null => OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DeliveryInvoiceScreen(invoice: DeliveryInvoice.fromJson(stop.invoice!)))),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Ver o reimprimir factura'),
            ),
            StopProgress.done => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Future<bool> opening) async {
    if (!await opening && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay una app instalada para abrir esto.')));
    }
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
          ],
        ),
      ),
    ),
  );
}

/// How this stop is paid, and whether credit is a problem before getting off the truck.
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.stop, required this.available, required this.allowsCredit, required this.overdue});

  final LocalDeliveryStop stop;
  final DecimalValue? available;
  final bool? allowsCredit;
  final DecimalValue? overdue;

  @override
  Widget build(BuildContext context) {
    final warnings = [
      if (stop.isCredit && allowsCredit == false) 'El cliente no tiene crédito activo: cobra de contado o avisa al supervisor.',
      if (stop.isCredit && available != null && stop.loadedTotal.compareTo(available!) > 0)
        'El pedido supera el crédito disponible (${money(available!.isNegative ? DecimalValue.zero : available!)}).',
      if (overdue != null && !overdue!.isZero) 'Tiene ${money(overdue!)} vencido.',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Pago', style: TextStyle(color: AppColors.muted)),
                const SizedBox(width: 12),
                StatusChip(text: stop.isCredit ? 'Crédito' : 'Contado', color: stop.isCredit ? const Color(0xFF2F6FD0) : AppColors.brand),
              ],
            ),
            if (stop.isCredit && available != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Crédito disponible: ${money(available!.isNegative ? DecimalValue.zero : available!)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (!stop.isCredit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Cobrar al entregar: ${money(stop.loadedTotal)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.amber),
                    const SizedBox(width: 6),
                    Expanded(child: Text(warning, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _outcomeText(LocalDeliveryItem item) => [
  'Entregado ${item.delivered}',
  if (!(item.returned ?? DecimalValue.zero).isZero) 'devuelto ${item.returned}',
  if (!(item.damaged ?? DecimalValue.zero).isZero) 'dañado ${item.damaged}',
  if (!(item.missing ?? DecimalValue.zero).isZero) 'faltó ${item.missing}',
].join(' · ');

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final LocalDeliveryItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductImage(productId: item.productId, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${item.loaded} × ${item.presentationName} · ${money(item.unitPrice)} c/u', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              if (item.isShort && item.delivered == null)
                Text(
                  'Pedido ${item.requested}, cargado ${item.loaded}',
                  style: const TextStyle(fontSize: 12, color: AppColors.amber, fontWeight: FontWeight.w600),
                ),
              if (item.delivered != null)
                Text(
                  _outcomeText(item),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: item.delivered == item.loaded ? AppColors.brand : AppColors.amber),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(money(item.delivered == null ? item.loadedTotal : item.deliveredTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

/// What was recorded at this stop and whether the server has it yet.
class _RecordedOutcome extends StatelessWidget {
  const _RecordedOutcome({required this.stop});

  final LocalDeliveryStop stop;

  @override
  Widget build(BuildContext context) {
    final (sendLabel, sendColor) = switch (stop.operationState) {
      LocalOperationState.pending => ('Por enviar', AppColors.amber),
      LocalOperationState.rejected => ('Rechazado', AppColors.danger),
      _ => ('Confirmado', AppColors.brand),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Entrega registrada', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                StatusChip(text: sendLabel, color: sendColor, outlined: stop.operationState == LocalOperationState.pending),
              ],
            ),
            const SizedBox(height: 8),
            Text(stop.statusLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (stop.receiverName != null) Text('Recibió: ${stop.receiverName}', style: const TextStyle(color: AppColors.muted)),
            if (stop.outcomeReasonLabel != null) Text('Motivo: ${stop.outcomeReasonLabel}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Entregado'),
                const Spacer(),
                Text(money(stop.deliveredTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
            if (stop.progress == StopProgress.awaitingPayment)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  stop.isCredit ? 'Falta registrar el cobro (queda a crédito o se paga ahora).' : 'Falta cobrar ${money(stop.balanceDue)}.',
                  style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600),
                ),
              ),
            if (stop.rejectionMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(stop.rejectionMessage!, style: const TextStyle(color: AppColors.danger)),
              ),
          ],
        ),
      ),
    );
  }
}
