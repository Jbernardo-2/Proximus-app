import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/external_apps.dart';
import '../../../core/formatting.dart';
import '../data/customer_profile.dart';
import '../data/preventa_models.dart';
import 'no_sale_sheet.dart';

final _date = DateFormat('dd/MM/yyyy');

/// Customer profile: contact, credit, open debts, recent orders and account history.
class CustomerScreen extends ConsumerWidget {
  const CustomerScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(customerProfileProvider(customerId));

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Este cliente no está en el teléfono. Sincroniza con señal para descargarlo.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final customer = profile.customer;
    return Scaffold(
      appBar: AppBar(title: Text(customer.businessName, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _Contact(customer: customer),
          const SizedBox(height: 12),
          _Actions(profile: profile),
          const SizedBox(height: 20),
          _Credit(profile: profile),
          const SizedBox(height: 20),
          _Section(
            title: 'Deudas abiertas',
            trailing: profile.receivables.isEmpty ? null : money(profile.openDebt),
            child: profile.receivables.isEmpty
                ? const _Empty('No tiene deudas abiertas.')
                : Column(children: [for (final debt in profile.receivables) _DebtRow(debt: debt)]),
          ),
          _Section(
            title: 'Pedidos recientes',
            child: profile.orders.isEmpty
                ? const _Empty('Sin pedidos en los últimos 30 días.')
                : Column(children: [for (final order in profile.orders.take(10)) _OrderRow(order: order)]),
          ),
          _Section(title: 'Últimos movimientos', child: _Movements(customerId: customerId)),
        ],
      ),
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({required this.customer});

  final LocalCustomer customer;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              [if (customer.code.isNotEmpty) customer.code, if ((customer.businessType ?? '').isNotEmpty) customer.businessType!].join(' · '),
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            _Line(icon: Icons.place_outlined, text: customer.address),
            if ((customer.reference ?? '').isNotEmpty) _Line(icon: Icons.signpost_outlined, text: customer.reference!),
            if ((customer.contactName ?? '').isNotEmpty) _Line(icon: Icons.person_outline, text: customer.contactName!),
            if ((customer.phone ?? '').isNotEmpty) _Line(icon: Icons.call_outlined, text: customer.phone!),
            if ((customer.whatsapp ?? '').isNotEmpty && customer.whatsapp != customer.phone) _Line(icon: Icons.chat_outlined, text: customer.whatsapp!),
            if (!customer.hasLocation) const _Line(icon: Icons.location_off_outlined, text: 'Sin ubicación registrada', muted: true),
          ]),
        ),
      );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.profile});

  final CustomerProfile profile;

  @override
  Widget build(BuildContext context) {
    final customer = profile.customer;
    final phone = customer.phone ?? customer.whatsapp;
    final whatsapp = customer.whatsapp ?? customer.phone;

    Future<void> open(Future<bool> opening) async {
      if (!await opening && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay una app instalada para abrir esto.')));
      }
    }

    return Column(children: [
      Row(children: [
        _QuickAction(icon: Icons.call_outlined, label: 'Llamar', onTap: phone == null ? null : () => open(ExternalApps.call(phone))),
        _QuickAction(icon: Icons.chat_outlined, label: 'WhatsApp', onTap: whatsapp == null ? null : () => open(ExternalApps.whatsapp(whatsapp))),
        _QuickAction(
          icon: Icons.map_outlined,
          label: 'Mapa',
          onTap: () => open(ExternalApps.map(
            latitude: customer.latitude,
            longitude: customer.longitude,
            label: customer.hasLocation ? customer.businessName : '${customer.address} ${customer.businessName}',
          )),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () async {
              final saved = await showNoSaleSheet(context, customer, routeStopId: profile.todayStop?.routeStopId);
              if (saved == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visita sin venta guardada en el teléfono.')));
              }
            },
            child: const Text('Sin venta'),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: OutlinedButton(style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 44))), onPressed: null, child: Text('Abono')),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: null,
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Pedido'),
          ),
        ),
      ]),
    ]);
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Icon(icon, color: onTap == null ? AppColors.muted.withValues(alpha: 0.4) : AppColors.brand),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: onTap == null ? AppColors.muted.withValues(alpha: 0.6) : AppColors.ink)),
            ]),
          ),
        ),
      );
}

class _Credit extends StatelessWidget {
  const _Credit({required this.profile});

  final CustomerProfile profile;

  @override
  Widget build(BuildContext context) {
    final balance = profile.balance;
    if (balance == null) {
      return const _Section(title: 'Crédito', child: _Empty('Sin información de crédito en el teléfono.'));
    }
    final available = balance.available.isNegative ? DecimalValue.zero : balance.available;

    return _Section(
      title: 'Crédito',
      trailing: balance.allowsCredit ? 'Activo' : 'Sin crédito',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Row(children: [
            _Figure(label: 'Límite', value: money(balance.limit)),
            _Figure(label: 'Disponible', value: balance.allowsCredit ? money(available) : '—', color: AppColors.brand),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _Figure(label: 'Saldo', value: money(balance.outstanding)),
            _Figure(label: 'Vencido', value: money(balance.overdue), color: balance.overdue.isZero ? null : AppColors.danger),
          ]),
        ]),
      ),
    );
  }
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.debt});

  final LocalReceivable debt;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(debt.documentNumber ?? 'Saldo', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                debt.dueDate == null ? 'Sin vencimiento' : '${debt.isOverdue ? 'Venció' : 'Vence'} ${_date.format(debt.dueDate!)}',
                style: TextStyle(fontSize: 12, color: debt.isOverdue ? AppColors.danger : AppColors.muted),
              ),
            ]),
          ),
          Text(money(debt.outstanding), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final LocalOrderSummary order;

  @override
  Widget build(BuildContext context) {
    final color = switch (order.state) {
      LocalOperationState.pending => AppColors.amber,
      LocalOperationState.rejected => AppColors.danger,
      _ => AppColors.muted,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order.reference, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${_date.format(order.orderDate)} · ${order.statusLabel} · ${order.paymentTerm == 'credit' ? 'Crédito' : 'Contado'}',
              style: TextStyle(fontSize: 12, color: color),
            ),
            if (order.rejectionMessage != null) Text(order.rejectionMessage!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ]),
        ),
        Text(money(order.total), style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Movements extends ConsumerWidget {
  const _Movements({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(accountEntriesProvider(customerId)).when(
        loading: () => const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        error: (_, _) => const _Empty('Disponible con señal.'),
        data: (entries) => entries.isEmpty
            ? const _Empty('Sin movimientos.')
            : Column(children: [
                for (final entry in entries.take(10))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            '${entry.typeLabel}${entry.reversed ? ' (revertido)' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            [if (entry.occurredAt != null) _date.format(entry.occurredAt!.toLocal()), if (entry.receiptNumber != null) entry.receiptNumber!].join(' · '),
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ]),
                      ),
                      Text(
                        entry.credit.isZero ? money(entry.debit) : '-${money(entry.credit)}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: entry.credit.isZero ? AppColors.ink : AppColors.brand),
                      ),
                    ]),
                  ),
              ]),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
            if (trailing != null) Text(trailing!, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted)),
          ]),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: child)),
        ]),
      );
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color ?? AppColors.ink)),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: muted ? AppColors.muted : AppColors.ink))),
        ]),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(text, style: const TextStyle(color: AppColors.muted)),
      );
}
