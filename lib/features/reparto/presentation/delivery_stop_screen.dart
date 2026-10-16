import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/external_apps.dart';
import '../../../core/formatting.dart';
import '../../preventa/presentation/daily_route_screen.dart' show StatusChip;
import '../../preventa/presentation/product_image.dart';
import '../application/delivery_providers.dart';
import '../data/delivery_models.dart';

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
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Productos (${stop.items.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              if (stop.orderNumber != null)
                Expanded(
                  child: Text(stop.orderNumber!, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
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
          if (!run.hasLeft)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Cuando salgas a ruta podrás registrar aquí lo que entregues.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ),
        ],
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
              if (item.isShort)
                Text(
                  'Pedido ${item.requested}, cargado ${item.loaded}',
                  style: const TextStyle(fontSize: 12, color: AppColors.amber, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(money(item.loadedTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
