import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../../core/location_capture.dart';
import '../application/preventa_actions.dart';
import '../data/order_draft.dart';
import 'product_picker.dart';

final _day = DateFormat("EEE d 'de' MMM", 'es');

/// Takes an order for a customer, with or without signal.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  late final LocationSession _location = ref.read(locationServiceProvider).start();
  OrderDraft? _draft;
  bool _saving = false;

  OrderDraft _initialDraft(String routeStopId) {
    final today = DateTime.now();
    return OrderDraft(
      customerId: widget.customerId,
      routeStopId: routeStopId,
      day: today,
      deliveryDate: DateTime(today.year, today.month, today.day + 1),
    );
  }

  Future<void> _addProduct() async {
    final picked = await pickProduct(context, day: _draft!.day);
    if (picked == null) return;
    setState(() => _draft = _draft!.add(picked.product, picked.presentation, picked.quantity));
  }

  Future<void> _editLine(OrderLine line) async {
    final picked = await showModalBottomSheet<PickedProduct>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuantitySheet(
        product: line.product,
        available: ref.read(availableStockProvider)[line.product.id] ?? DecimalValue.zero,
        day: _draft!.day,
        initial: line.quantity,
        presentationId: line.presentation.id,
      ),
    );
    if (picked == null) return;
    setState(() {
      var draft = _draft!;
      if (picked.presentation.id != line.presentation.id) draft = draft.remove(line.presentation.id);
      _draft = draft.setQuantity(picked.product, picked.presentation, picked.quantity);
    });
  }

  Future<void> _pickDeliveryDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft!.deliveryDate ?? today,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _draft = _draft!.withTerms(deliveryDate: picked));
  }

  Future<void> _save(String customerName, OrderWarnings warnings) async {
    if (warnings.any) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Revisa antes de guardar'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (warnings.shortProducts.isNotEmpty) Text('Sin existencias suficientes: ${warnings.shortProducts.join(', ')}.'),
            if (warnings.creditNotAllowed) const Text('El cliente no tiene crédito activo.'),
            if (!warnings.creditExceededBy.isZero) Text('Excede el crédito disponible en ${money(warnings.creditExceededBy)}.'),
            const SizedBox(height: 12),
            const Text('Puedes guardarlo igual: el supervisor verá la excepción.', style: TextStyle(color: AppColors.muted)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Corregir')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar igual')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(preventaActionsProvider).placeOrder(draft: _draft!, customerName: customerName, location: _location);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pedido de $customerName guardado en el teléfono.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(customerProfileProvider(widget.customerId));
    final routeStopId = ref.watch(routeStopForCustomerProvider(widget.customerId));

    if (profile == null || routeStopId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              profile == null ? 'Este cliente no está en el teléfono.' : 'El cliente no está en ninguna de tus rutas; no se le puede tomar pedido desde aquí.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final draft = _draft ??= _initialDraft(routeStopId);
    final balance = profile.balance;
    final warnings = draft.warnings(
      available: ref.watch(availableStockProvider),
      credit: balance == null ? null : (allowsCredit: balance.allowsCredit, available: balance.available),
    );

    return Scaffold(
      appBar: AppBar(title: Text(profile.customer.businessName, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (draft.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('Agrega los productos del pedido.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            )
          else
            for (final line in draft.lines)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _editLine(line),
                  title: Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${line.quantity} × ${line.presentation.name} · ${money(line.unitPrice)} c/u${line.hasTierPrice ? ' (volumen)' : ''}'
                    '${warnings.shortProducts.contains(line.product.name) ? '\nSin existencias suficientes' : ''}',
                    style: TextStyle(color: warnings.shortProducts.contains(line.product.name) ? AppColors.amber : AppColors.muted),
                  ),
                  isThreeLine: warnings.shortProducts.contains(line.product.name),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(line.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(
                      tooltip: 'Quitar',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() => _draft = draft.remove(line.presentation.id)),
                    ),
                  ]),
                ),
              ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _addProduct,
            icon: const Icon(Icons.add),
            label: const Text('Agregar producto'),
          ),
          const SizedBox(height: 20),
          const Text('Condición de pago', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'cash', label: Text('Contado')),
              ButtonSegment(value: 'credit', label: Text(balance?.allowsCredit ?? false ? 'Crédito · ${money(balance!.available.isNegative ? DecimalValue.zero : balance.available)}' : 'Crédito')),
            ],
            selected: {draft.paymentTerm},
            onSelectionChanged: (value) => setState(() => _draft = draft.withTerms(paymentTerm: value.first)),
          ),
          if (warnings.creditNotAllowed)
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('El cliente no tiene crédito activo.', style: TextStyle(color: AppColors.amber)))
          else if (!warnings.creditExceededBy.isZero)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Excede el crédito disponible en ${money(warnings.creditExceededBy)}.', style: const TextStyle(color: AppColors.amber)),
            ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Entrega'),
            subtitle: Text(draft.deliveryDate == null ? 'Sin fecha' : toBeginningOfSentenceCase(_day.format(draft.deliveryDate!))),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _pickDeliveryDate,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${draft.lines.length} productos', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Text(money(draft.total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(150, 50)),
              onPressed: draft.isEmpty || _saving ? null : () => _save(profile.customer.businessName, warnings),
              child: _saving ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar pedido'),
            ),
          ]),
        ),
      ),
    );
  }
}
