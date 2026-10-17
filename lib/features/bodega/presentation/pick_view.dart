import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/api.dart';
import '../../../core/decimal_value.dart';
import '../../preventa/presentation/product_image.dart';
import '../application/bodega_providers.dart';
import '../application/warehouse_run_actions.dart';
import '../data/warehouse_catalog.dart';
import '../data/warehouse_runs.dart';
import 'barcode_scanner_screen.dart';
import 'online.dart';
import 'warehouse_run_screen.dart' show BottomAction;

typedef PickEntry = ({RunOrder order, PickLine line});

/// Preparing a run, by product or by order. Each save goes to the server, which checks
/// the warehouse stock at that moment; the stock shown is read live.
class PickView extends ConsumerStatefulWidget {
  const PickView({super.key, required this.run});

  final WarehouseRun run;

  @override
  ConsumerState<PickView> createState() => _PickViewState();
}

class _PickViewState extends ConsumerState<PickView> {
  bool _byOrder = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final onHandValue = ref.watch(liveOnHandProvider(run.warehouseId));
    final onHand = onHandValue.value ?? const <String, DecimalValue>{};
    final byProduct = stockForRun(run, onHand: onHand);
    final groups = pickGroups(run);
    final picked = groups.where((group) => group.prepared != null).length;
    final short = [for (final entry in byProduct.entries) if (entry.value.isShort) entry];

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$picked de ${groups.length} productos revisados', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: groups.isEmpty ? 0 : picked / groups.length, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            ]),
          ),
          IconButton(tooltip: 'Escanear producto', icon: const Icon(Icons.qr_code_scanner), onPressed: () => _scan(groups)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Por producto'), icon: Icon(Icons.inventory_2_outlined)),
            ButtonSegment(value: true, label: Text('Por pedido'), icon: Icon(Icons.receipt_long_outlined)),
          ],
          selected: {_byOrder},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => setState(() => _byOrder = selection.first),
        ),
      ),
      if (onHandValue.hasError)
        _Banner('No se pudo leer la existencia: ${onHandValue.error is ApiException && (onHandValue.error as ApiException).isNetwork ? 'sin conexión' : onHandValue.error}.')
      else if (short.isNotEmpty)
        _Banner(
          '${short.length == 1 ? 'No alcanza 1 producto' : 'No alcanzan ${short.length} productos'} en bodega:\n'
          '${short.map((entry) => '${_name(entry.key)}: faltan ${entry.value.missing} ${_unit(entry.key)}').join('\n')}',
        ),
      if (onHandValue.isLoading || _loading) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator(minHeight: 2)),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async => ref.read(warehouseRunActionsProvider).refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: _byOrder ? run.orders.length : groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _byOrder
                ? _OrderTile(run: run, order: run.orders[index], stock: byProduct)
                : _GroupTile(run: run, group: groups[index], stock: byProduct[groups[index].productId], onFill: _fill),
          ),
        ),
      ),
      BottomAction(
        child: FilledButton.icon(
          onPressed: picked < groups.length || short.isNotEmpty || _loading ? null : _confirm,
          icon: const Icon(Icons.local_shipping_outlined),
          label: Text(picked < groups.length
              ? 'Faltan ${groups.length - picked} por revisar'
              : short.isNotEmpty
              ? 'No alcanza la existencia'
              : 'Confirmar carga'),
        ),
      ),
    ]);
  }

  String _name(String productId) =>
      ref.read(warehouseProductProvider(productId))?.product.name ?? widget.run.lines.where((line) => line.productId == productId).firstOrNull?.productName ?? 'Producto';

  String _unit(String productId) => ref.read(warehouseProductProvider(productId))?.product.baseUnit ?? 'u';

  Future<void> _fill(List<PickEntry> entries) async {
    setState(() => _loading = true);
    await fillEntries(context, ref, widget.run, entries);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _scan(List<PickGroup> groups) async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final product = productForBarcode(ref.read(warehouseProductsProvider), code);
    final presentation = product?.presentationWithBarcode(code.trim());
    final group = groups.where((group) => group.presentationId == presentation?.id).firstOrNull ?? groups.where((group) => group.productId == product?.product.id).firstOrNull;
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(product == null ? 'El código $code no está registrado.' : '${product.product.name} no va en esta jornada.')));
      return;
    }
    await openPickSheet(context, widget.run, title: group.productName, subtitle: '${group.presentationName} · pedido ${group.requested}', entries: group.lines, byOrder: false);
  }

  Future<void> _confirm() async {
    final run = widget.run;
    final empty = emptyOrders(run);
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
    final incomplete = [for (final line in run.lines) if (line.prepared!.compareTo(line.requested) < 0) line];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar carga'),
        content: Text([
          incomplete.isEmpty ? 'Todo lo pedido va completo.' : '${incomplete.length} ${incomplete.length == 1 ? 'línea va incompleta' : 'líneas van incompletas'}.',
          'Al confirmar, lo preparado sale de la existencia de bodega.',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar carga')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    final ok = await runOnline(context, () => ref.read(warehouseRunActionsProvider).confirmLoad(run));
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${run.runNumber} cargada.')));
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
  );
}

/// Fills [entries] with what the stock allows, earlier stops first, saves it on the
/// server and says when it fell short.
Future<void> fillEntries(BuildContext context, WidgetRef ref, WarehouseRun run, List<PickEntry> entries) async {
  final onHand = ref.read(liveOnHandProvider(run.warehouseId)).value ?? const <String, DecimalValue>{};
  final filled = fillByVisit(
    run,
    [for (final entry in entries) entry.line.orderItemId],
    onHand: onHand,
    allowsDecimal: (productId) => ref.read(warehouseProductProvider(productId))?.product.allowsDecimal ?? true,
  );
  final ok = await runOnline(context, () => ref.read(warehouseRunActionsProvider).pick(run, filled));
  final short = entries.where((entry) => filled[entry.line.orderItemId]!.compareTo(entry.line.requested) < 0).length;
  if (ok && short > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('No alcanzó para ${short == 1 ? '1 línea' : '$short líneas'}: se repartió lo disponible por orden de visita.'),
    ));
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.run, required this.group, required this.stock, required this.onFill});

  final WarehouseRun run;
  final PickGroup group;
  final ProductStock? stock;
  final Future<void> Function(List<PickEntry> entries) onFill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prepared = group.prepared;
    final complete = prepared != null && prepared.compareTo(group.requested) == 0;
    final unit = ref.watch(warehouseProductProvider(group.productId))?.product.baseUnit ?? 'u';
    final isShort = stock?.isShort ?? false;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        leading: ProductImage(productId: group.productId, size: 48),
        title: Text(group.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${group.presentationName} · ${group.lines.length} ${group.lines.length == 1 ? 'pedido' : 'pedidos'}'),
          if (stock != null)
            Text(
              isShort ? 'Hay ${stock!.available} $unit · faltan ${stock!.missing}' : 'Hay ${stock!.available} $unit',
              style: TextStyle(color: isShort ? AppColors.danger : AppColors.muted, fontWeight: isShort ? FontWeight.w700 : FontWeight.normal),
            ),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(prepared == null ? '${group.requested}' : '$prepared / ${group.requested}',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: prepared == null ? AppColors.ink : complete ? AppColors.brand : AppColors.amber)),
            Text(prepared == null ? 'por revisar' : complete ? 'completo' : 'incompleto', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
          IconButton(
            tooltip: 'Completo',
            icon: Icon(complete ? Icons.check_circle : Icons.check_circle_outline, color: complete ? AppColors.brand : AppColors.muted, size: 30),
            onPressed: () => onFill(group.lines),
          ),
        ]),
        onTap: () => openPickSheet(context, run, title: group.productName, subtitle: '${group.presentationName} · pedido ${group.requested}', entries: group.lines, byOrder: false),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.run, required this.order, required this.stock});

  final WarehouseRun run;
  final RunOrder order;
  final Map<String, ProductStock> stock;

  @override
  Widget build(BuildContext context) {
    final picked = order.lines.where((line) => line.prepared != null).length;
    final done = picked == order.lines.length;
    final short = order.lines.any((line) => stock[line.productId]?.isShort ?? false);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (done ? AppColors.brand : AppColors.muted).withValues(alpha: 0.12),
          child: Text('${order.visitOrder}', style: TextStyle(fontWeight: FontWeight.w800, color: done ? AppColors.brand : AppColors.ink)),
        ),
        title: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${order.orderNumber} · $picked de ${order.lines.length} líneas', style: TextStyle(color: short ? AppColors.danger : null)),
        trailing: Icon(short ? Icons.warning_amber_rounded : done ? Icons.check_circle : Icons.chevron_right, color: short ? AppColors.danger : done ? AppColors.brand : AppColors.muted),
        onTap: () => openPickSheet(
          context,
          run,
          title: order.customerName,
          subtitle: '${order.orderNumber} · parada ${order.visitOrder}',
          entries: [for (final line in order.lines) (order: order, line: line)],
          byOrder: true,
        ),
      ),
    );
  }
}

/// The lines of one product (each order) or one order (each product), checked against
/// the live stock as they are typed and saved on the server.
Future<void> openPickSheet(BuildContext context, WarehouseRun run, {required String title, required String subtitle, required List<PickEntry> entries, required bool byOrder}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickSheet(run: run, title: title, subtitle: subtitle, entries: entries, byOrder: byOrder),
    );

class _PickSheet extends ConsumerStatefulWidget {
  const _PickSheet({required this.run, required this.title, required this.subtitle, required this.entries, required this.byOrder});

  final WarehouseRun run;
  final String title;
  final String subtitle;
  final List<PickEntry> entries;
  final bool byOrder;

  @override
  ConsumerState<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends ConsumerState<_PickSheet> {
  late final Map<String, TextEditingController> _fields;
  late final Map<String, FocusNode> _focus;
  bool _saving = false;

  /// What the server answered when it refused the save.
  String? _refusal;

  @override
  void initState() {
    super.initState();
    _fields = {for (final entry in widget.entries) entry.line.orderItemId: TextEditingController(text: '${entry.line.prepared ?? entry.line.requested}')};
    _focus = {for (final entry in widget.entries) entry.line.orderItemId: FocusNode()};
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  DecimalValue? _value(String orderItemId) {
    try {
      return DecimalValue.parse(_fields[orderItemId]!.text);
    } on FormatException {
      return null;
    }
  }

  /// The stock with what is typed here over what was picked; unreviewed lines do not count.
  Map<String, ProductStock> _stock() => stockForRun(
    widget.run,
    onHand: ref.read(liveOnHandProvider(widget.run.warehouseId)).value ?? const {},
    typed: {for (final entry in widget.entries) entry.line.orderItemId: ?_value(entry.line.orderItemId)},
    unpickedAsRequested: false,
  );

  String? _error(PickLine line, Map<String, ProductStock> stock) {
    final value = _value(line.orderItemId);
    if (value == null) return 'Cantidad no válida';
    if (value.compareTo(line.requested) > 0) return 'Máximo ${line.requested}';
    final allowsDecimal = ref.read(warehouseProductProvider(line.productId))?.product.allowsDecimal ?? true;
    if (!allowsDecimal && value.scale > 0) return 'Solo enteros';
    final productStock = stock[line.productId];
    if (productStock != null && productStock.isShort && !value.isZero) return 'Solo hay ${productStock.available}';
    return null;
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final product = productForBarcode(ref.read(warehouseProductsProvider), code);
    final presentation = product?.presentationWithBarcode(code.trim());
    final entry = widget.entries.where((entry) => entry.line.presentationId == presentation?.id).firstOrNull ??
        widget.entries.where((entry) => entry.line.productId == product?.product.id).firstOrNull;
    if (entry == null) {
      setState(() => _refusal = product == null ? 'El código $code no está registrado.' : '${product.product.name} no va en este pedido.');
      return;
    }
    _focus[entry.line.orderItemId]!.requestFocus();
    _fields[entry.line.orderItemId]!.selection = TextSelection(baseOffset: 0, extentOffset: _fields[entry.line.orderItemId]!.text.length);
  }

  Future<void> _save(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _refusal = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _refusal = error.isNetwork ? 'Sin conexión: no se guardó. Revisa la señal e intenta de nuevo.' : error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stock = _stock();
    final valid = widget.entries.every((entry) => _error(entry.line, stock) == null);
    final productId = widget.entries.first.line.productId;
    final actions = ref.read(warehouseRunActionsProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(widget.subtitle, style: const TextStyle(color: AppColors.muted)),
            ]),
          ),
          if (widget.byOrder) IconButton(tooltip: 'Escanear producto', icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
        ]),
        if (!widget.byOrder && stock[productId] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'En bodega: ${stock[productId]!.available} · la jornada lleva ${stock[productId]!.needed} ${ref.read(warehouseProductProvider(productId))?.product.baseUnit ?? 'u'}',
              style: TextStyle(color: stock[productId]!.isShort ? AppColors.danger : AppColors.muted, fontWeight: FontWeight.w600),
            ),
          ),
        if (_refusal != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Text(_refusal!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final entry in widget.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.byOrder ? entry.line.productName : entry.order.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        widget.byOrder ? '${entry.line.presentationName} · pidió ${entry.line.requested}' : '${entry.order.orderNumber} · parada ${entry.order.visitOrder} · pidió ${entry.line.requested}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ]),
                  ),
                  SizedBox(
                    width: 104,
                    child: TextField(
                      controller: _fields[entry.line.orderItemId],
                      focusNode: _focus[entry.line.orderItemId],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      textAlign: TextAlign.end,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(errorText: _error(entry.line, stock), errorMaxLines: 2, isDense: true),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => _save(() => actions.pick(
                        widget.run,
                        fillByVisit(
                          widget.run,
                          [for (final entry in widget.entries) entry.line.orderItemId],
                          onHand: ref.read(liveOnHandProvider(widget.run.warehouseId)).value ?? const {},
                          allowsDecimal: (id) => ref.read(warehouseProductProvider(id))?.product.allowsDecimal ?? true,
                        ),
                      )),
              child: Text(widget.byOrder ? 'Pedido completo' : 'Todo completo'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: !valid || _saving
                  ? null
                  : () => _save(() => actions.pick(widget.run, {for (final entry in widget.entries) entry.line.orderItemId: _value(entry.line.orderItemId)!})),
              child: Text(_saving ? 'Guardando…' : 'Guardar'),
            ),
          ),
        ]),
      ]),
    );
  }
}
