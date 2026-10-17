import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/bodega_providers.dart';
import '../application/warehouse_run_actions.dart';
import '../data/warehouse_catalog.dart';
import '../data/warehouse_runs.dart';
import 'barcode_scanner_screen.dart';

/// One run, by stage: assemble its orders, pick them, and confirm the load.
class WarehouseRunScreen extends ConsumerWidget {
  const WarehouseRunScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(warehouseRunProvider(runId));
    if (run == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Esta jornada ya salió o se canceló.', style: TextStyle(color: AppColors.muted))));
    }
    final session = ref.watch(sessionProvider).value;
    final canPick = session != null && run.preparableBy(session.userId, supervises: session.role != 'bodeguero');

    return Scaffold(
      appBar: AppBar(title: Text(run.title)),
      body: Column(children: [
        _Header(run: run),
        for (final rejection in run.rejections)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(rejection, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        Expanded(
          child: switch (run.status) {
            'draft' => _Assemble(run: run),
            'preparing' when canPick => _Pick(run: run),
            'preparing' => const _Message('Otro bodeguero está preparando esta jornada. Solo él o un supervisor pueden continuarla.'),
            _ => _Loaded(run: run),
          },
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.run});

  final WarehouseRun run;

  @override
  Widget build(BuildContext context) {
    final stage = {'draft': 'Armando', 'preparing': 'Preparando', 'loaded': 'Lista para salir'}[run.status] ?? run.status;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(run.driverName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              [if (run.vehicle != null) run.vehicle!, if (run.scheduledDate != null) DateFormat("EEEE d 'de' MMMM", 'es').format(run.scheduledDate!)].join(' · '),
              style: const TextStyle(color: AppColors.muted),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(stage, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
          if (run.pending) const Text('Sin enviar', style: TextStyle(color: AppColors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted))));
}

/// Draft: which orders go on the truck.
class _Assemble extends ConsumerWidget {
  const _Assemble({required this.run});

  final WarehouseRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = run.orders.fold(DecimalValue.zero, (sum, order) => sum + order.total);
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Row(children: [
              Expanded(child: Text('${run.orders.length} ${run.orders.length == 1 ? 'pedido' : 'pedidos'} · ${money(total)}', style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton.icon(onPressed: () => context.push('/warehouse-runs/${run.id}/orders'), icon: const Icon(Icons.add), label: const Text('Agregar pedidos')),
            ]),
            if (run.orders.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Text('Agrega los pedidos que van en esta jornada.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))),
            for (final order in run.orders)
              Card(
                child: ListTile(
                  title: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([order.orderNumber, if (order.routeName != null) order.routeName!, '${order.lines.length} líneas'].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(order.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                    IconButton(tooltip: 'Quitar', icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger), onPressed: () => _remove(context, ref, order)),
                  ]),
                ),
              ),
          ],
        ),
      ),
      _BottomBar(
        child: FilledButton.icon(
          onPressed: run.orders.isEmpty ? null : () => ref.read(warehouseRunActionsProvider).startPreparation(run),
          icon: const Icon(Icons.inventory_outlined),
          label: const Text('Iniciar preparación'),
        ),
      ),
    ]);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, RunOrder order) async {
    try {
      await ref.read(warehouseRunActionsProvider).unassign(run, order);
    } on StateError catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: SizedBox(width: double.infinity, height: 52, child: child)),
  );
}

/// Preparing: every presentation of the run, picked once across its orders.
class _Pick extends ConsumerWidget {
  const _Pick({required this.run});

  final WarehouseRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(pickingDraftProvider(run.id));
    final groups = pickGroups(run);
    final picked = groups.where((group) => group.preparedWith(draft) != null).length;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$picked de ${groups.length} productos revisados', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: groups.isEmpty ? 0 : picked / groups.length, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            ]),
          ),
          IconButton(tooltip: 'Escanear producto', icon: const Icon(Icons.qr_code_scanner), onPressed: () => _scan(context, ref, groups)),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _PickTile(run: run, group: groups[index], draft: draft),
        ),
      ),
      _BottomBar(
        child: FilledButton.icon(
          onPressed: picked < groups.length ? null : () => _confirm(context, ref, draft),
          icon: const Icon(Icons.local_shipping_outlined),
          label: Text(picked < groups.length ? 'Faltan ${groups.length - picked} por revisar' : 'Confirmar carga'),
        ),
      ),
    ]);
  }

  Future<void> _scan(BuildContext context, WidgetRef ref, List<PickGroup> groups) async {
    final code = await scanBarcode(context);
    if (code == null || !context.mounted) return;
    final product = productForBarcode(ref.read(warehouseProductsProvider), code);
    final presentation = product?.presentationWithBarcode(code.trim());
    final group = groups.where((group) => group.presentationId == presentation?.id).firstOrNull ?? groups.where((group) => group.productId == product?.product.id).firstOrNull;
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(product == null ? 'El código $code no está registrado.' : '${product.product.name} no va en esta jornada.')));
      return;
    }
    await openPickSheet(context, run, group);
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, Map<String, DecimalValue> draft) async {
    final quantities = preparedQuantities(run, draft)!;
    final empty = emptyOrders(run, quantities);
    if (empty.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pedido sin mercancía'),
          content: Text('${empty.map((order) => '${order.orderNumber} · ${order.customerName}').join('\n')}\n\nNo se puede cargar un pedido vacío. Prepara al menos una línea o pide al supervisor que lo retire de la jornada.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
        ),
      );
      return;
    }
    final short = [for (final line in run.lines) if (quantities[line.orderItemId]!.compareTo(line.requested) < 0) line];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar carga'),
        content: Text(short.isEmpty
            ? 'Todo lo pedido va completo. Al confirmar, la mercancía sale de la existencia de bodega.'
            : '${short.length} ${short.length == 1 ? 'línea va incompleta' : 'líneas van incompletas'}. Al confirmar, lo preparado sale de la existencia de bodega.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar carga')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(warehouseRunActionsProvider).confirmLoad(run, quantities);
  }
}

class _PickTile extends ConsumerWidget {
  const _PickTile({required this.run, required this.group, required this.draft});

  final WarehouseRun run;
  final PickGroup group;
  final Map<String, DecimalValue> draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prepared = group.preparedWith(draft);
    final complete = prepared != null && prepared.compareTo(group.requested) == 0;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        leading: ProductImage(productId: group.productId, size: 48),
        title: Text(group.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${group.presentationName} · ${group.lines.length} ${group.lines.length == 1 ? 'pedido' : 'pedidos'}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(prepared == null ? '${group.requested}' : '$prepared / ${group.requested}',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: prepared == null ? AppColors.ink : complete ? AppColors.brand : AppColors.amber)),
            Text(prepared == null ? 'por revisar' : complete ? 'completo' : 'incompleto', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
          IconButton(
            tooltip: 'Completo',
            icon: Icon(complete ? Icons.check_circle : Icons.check_circle_outline, color: complete ? AppColors.brand : AppColors.muted, size: 30),
            onPressed: () => ref.read(warehouseRunActionsProvider).pick(run.id, {for (final entry in group.lines) entry.line.orderItemId: entry.line.requested}),
          ),
        ]),
        onTap: () => openPickSheet(context, run, group),
      ),
    );
  }
}

/// What goes to each order when a presentation is short.
Future<void> openPickSheet(BuildContext context, WarehouseRun run, PickGroup group) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _PickSheet(run: run, group: group),
);

class _PickSheet extends ConsumerStatefulWidget {
  const _PickSheet({required this.run, required this.group});

  final WarehouseRun run;
  final PickGroup group;

  @override
  ConsumerState<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends ConsumerState<_PickSheet> {
  late final Map<String, TextEditingController> _fields;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(pickingDraftProvider(widget.run.id));
    _fields = {
      for (final entry in widget.group.lines)
        entry.line.orderItemId: TextEditingController(text: '${draft[entry.line.orderItemId] ?? entry.line.prepared ?? entry.line.requested}'),
    };
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String? _error(PickLine line) {
    final DecimalValue value;
    try {
      value = DecimalValue.parse(_fields[line.orderItemId]!.text);
    } on FormatException {
      return 'Cantidad no válida';
    }
    if (value.compareTo(line.requested) > 0) return 'Máximo ${line.requested}';
    final allowsDecimal = ref.read(warehouseProductProvider(line.productId))?.product.allowsDecimal ?? true;
    if (!allowsDecimal && value.scale > 0) return 'Solo enteros';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final valid = widget.group.lines.every((entry) => _error(entry.line) == null);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.group.productName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text('${widget.group.presentationName} · pedido ${widget.group.requested}', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 12),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final entry in widget.group.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(entry.order.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${entry.order.orderNumber} · pidió ${entry.line.requested}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    ]),
                  ),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _fields[entry.line.orderItemId],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      textAlign: TextAlign.end,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(errorText: _error(entry.line), isDense: true),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: !valid
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  await ref.read(warehouseRunActionsProvider).pick(widget.run.id, {
                    for (final entry in widget.group.lines) entry.line.orderItemId: DecimalValue.parse(_fields[entry.line.orderItemId]!.text),
                  });
                  navigator.pop();
                },
          child: const Text('Guardar'),
        ),
      ]),
    );
  }
}

/// Loaded: what went on the truck, waiting for the driver to leave.
class _Loaded extends StatelessWidget {
  const _Loaded({required this.run});

  final WarehouseRun run;

  @override
  Widget build(BuildContext context) {
    final groups = pickGroups(run);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(run.pending ? 'La carga se enviará al tener señal.' : 'Cargada. El repartidor ya puede iniciar ruta.', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        for (final group in groups)
          Card(
            child: ListTile(
              leading: ProductImage(productId: group.productId, size: 40),
              title: Text(group.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(group.presentationName),
              trailing: Text('${group.preparedWith(const {}) ?? group.requested}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
  }
}
