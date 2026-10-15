import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../../core/location_capture.dart';
import '../application/order_draft_controller.dart';
import '../application/preventa_actions.dart';
import '../data/order_draft.dart';
import 'product_picker.dart';

final _day = DateFormat("EEE d 'de' MMM", 'es');

/// Takes an order for a customer, with or without signal: a fixed search bar on
/// top, the products below (newest first) and payment and delivery when saving.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  late final LocationSession _location = ref.read(locationServiceProvider).start();

  OrderDraftController get _controller => ref.read(orderDraftProvider(widget.customerId).notifier);

  void _openSearch() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductPickerScreen(customerId: widget.customerId)));

  Future<void> _editLine(OrderDraft draft, OrderLine line) async {
    final picked = await showModalBottomSheet<PickedProduct>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuantitySheet(
        product: line.product,
        available: ref.read(availableStockProvider)[line.product.id] ?? DecimalValue.zero,
        day: draft.day,
        initial: line.quantity,
        presentationId: line.presentation.id,
      ),
    );
    if (picked == null) return;
    if (picked.presentation.id != line.presentation.id) _controller.remove(line.presentation.id);
    _controller.put(picked.product, picked.presentation, picked.quantity);
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Descartar el pedido?'),
          content: const Text('Los productos agregados no se guardarán.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir con el pedido')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar')),
          ],
        ),
      ) ??
      false;

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

    final draft = ref.watch(orderDraftProvider(widget.customerId));
    if (draft == null) {
      Future.microtask(() => _controller.start(routeStopId));
      return const Scaffold();
    }
    final shortProducts = draft.warnings(available: ref.watch(availableStockProvider), credit: null).shortProducts;

    return PopScope(
      canPop: draft.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(profile.customer.businessName, overflow: TextOverflow.ellipsis)),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFBDBDBD))),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openSearch,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                  child: Row(children: [
                    Icon(Icons.search, color: AppColors.brand),
                    SizedBox(width: 12),
                    Expanded(child: Text('Buscar y agregar productos', style: TextStyle(color: AppColors.muted, fontSize: 16))),
                    Icon(Icons.add, color: AppColors.brand),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
            child: draft.isEmpty
                ? const Center(child: Text('Busca arriba los productos del pedido.', style: TextStyle(color: AppColors.muted)))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      for (final line in draft.lines.reversed)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () => _editLine(draft, line),
                            title: Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${line.quantity} × ${line.presentation.name} · ${money(line.unitPrice)} c/u${line.hasTierPrice ? ' (volumen)' : ''}'
                              '${shortProducts.contains(line.product.name) ? '\nSin existencias suficientes' : ''}',
                              style: TextStyle(color: shortProducts.contains(line.product.name) ? AppColors.amber : AppColors.muted),
                            ),
                            isThreeLine: shortProducts.contains(line.product.name),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(money(line.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                              IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close, size: 20), onPressed: () => _controller.remove(line.presentation.id)),
                            ]),
                          ),
                        ),
                    ],
                  ),
          ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${draft.lines.length} ${draft.lines.length == 1 ? 'producto' : 'productos'}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(money(draft.total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                ]),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                onPressed: draft.isEmpty
                    ? null
                    : () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => _ReviewSheet(customerId: widget.customerId, location: _location),
                        ),
                child: const Text('Revisar y guardar'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Payment, delivery and warnings before saving.
class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.customerId, required this.location});

  final String customerId;
  final LocationSession location;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  bool _saving = false;

  Future<void> _pickDeliveryDate(OrderDraft draft) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.deliveryDate ?? today,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 30)),
    );
    if (picked != null) ref.read(orderDraftProvider(widget.customerId).notifier).terms(deliveryDate: picked);
  }

  Future<void> _save(OrderDraft draft, String customerName) async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(preventaActionsProvider).placeOrder(draft: draft, customerName: customerName, location: widget.location);
      navigator
        ..pop()
        ..pop();
      messenger.showSnackBar(SnackBar(content: Text('Pedido de $customerName guardado en el teléfono.')));
    } catch (error, stack) {
      debugPrint('No se pudo guardar el pedido: $error\n$stack');
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(orderDraftProvider(widget.customerId));
    final profile = ref.watch(customerProfileProvider(widget.customerId));
    if (draft == null || profile == null) return const SizedBox.shrink();
    final balance = profile.balance;
    final warnings = draft.warnings(
      available: ref.watch(availableStockProvider),
      credit: balance == null ? null : (allowsCredit: balance.allowsCredit, available: balance.available),
    );
    final controller = ref.read(orderDraftProvider(widget.customerId).notifier);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Revisar pedido', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text('${profile.customer.businessName} · ${draft.lines.length} productos', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        const Text('Condición de pago', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            const ButtonSegment(value: 'cash', label: Text('Contado')),
            ButtonSegment(
              value: 'credit',
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(balance?.allowsCredit ?? false ? 'Crédito · ${money(balance!.available.isNegative ? DecimalValue.zero : balance.available)}' : 'Crédito'),
              ),
            ),
          ],
          selected: {draft.paymentTerm},
          onSelectionChanged: (value) => controller.terms(paymentTerm: value.first),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: const Text('Entrega'),
          subtitle: Text(draft.deliveryDate == null ? 'Sin fecha' : toBeginningOfSentenceCase(_day.format(draft.deliveryDate!))),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () => _pickDeliveryDate(draft),
        ),
        if (warnings.any) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (warnings.shortProducts.isNotEmpty) Text('Sin existencias suficientes: ${warnings.shortProducts.join(', ')}.'),
              if (warnings.creditNotAllowed) const Text('El cliente no tiene crédito activo.'),
              if (!warnings.creditExceededBy.isZero) Text('Excede el crédito disponible en ${money(warnings.creditExceededBy)}.'),
              const SizedBox(height: 4),
              const Text('Puedes guardarlo igual: el supervisor verá la excepción.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        Row(children: [
          const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(money(draft.total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : () => _save(draft, profile.customer.businessName),
          child: _saving ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(warnings.any ? 'Guardar igual' : 'Guardar pedido'),
        ),
      ]),
    );
  }
}
