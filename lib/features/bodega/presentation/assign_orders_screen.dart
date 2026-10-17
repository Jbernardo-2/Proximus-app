import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/formatting.dart';
import '../application/warehouse_run_actions.dart';
import '../data/warehouse_runs.dart';
import 'online.dart';

/// Confirmed orders of the run's warehouse, read now; each one added goes onto the run.
class AssignOrdersScreen extends ConsumerStatefulWidget {
  const AssignOrdersScreen({super.key, required this.runId});

  final String runId;

  @override
  ConsumerState<AssignOrdersScreen> createState() => _AssignOrdersScreenState();
}

class _AssignOrdersScreenState extends ConsumerState<AssignOrdersScreen> {
  final _search = TextEditingController();
  String? _route;
  final _adding = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add(WarehouseRun run, DispatchOrder dispatch) async {
    setState(() => _adding.add(dispatch.order.orderId));
    await runOnline(context, () => ref.read(warehouseRunActionsProvider).assign(run, dispatch));
    if (mounted) setState(() => _adding.remove(dispatch.order.orderId));
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(warehouseRunProvider(widget.runId)).value;
    final available = ref.watch(availableOrdersProvider);
    if (run != null && !run.isDraft) return Scaffold(appBar: AppBar(), body: const Center(child: Text('La jornada ya no acepta pedidos.')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agregar pedidos'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Listo (${run?.orders.length ?? 0})'))],
      ),
      body: available.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LiveError(error: error, onRetry: () => ref.read(warehouseRunActionsProvider).refresh()),
        data: (all) {
          final orders = [
            for (final dispatch in all)
              if (run?.warehouseId == null || dispatch.warehouseId == null || dispatch.warehouseId == run!.warehouseId) dispatch,
          ]..sort((a, b) => (a.requestedDate ?? DateTime(2100)).compareTo(b.requestedDate ?? DateTime(2100)));
          final routes = {for (final dispatch in orders) dispatch.order.routeName ?? 'Fuera de ruta'}.toList()..sort();
          final terms = _search.text.toLowerCase().split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
          final shown = orders.where((dispatch) {
            if (_route != null && (dispatch.order.routeName ?? 'Fuera de ruta') != _route) return false;
            final text = '${dispatch.order.customerName} ${dispatch.order.orderNumber} ${dispatch.order.routeName ?? ''}'.toLowerCase();
            return terms.every(text.contains);
          }).toList();

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Cliente, pedido o ruta', prefixIcon: Icon(Icons.search)),
              ),
            ),
            if (routes.length > 1)
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), children: [
                  for (final route in routes)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(label: Text(route), selected: _route == route, onSelected: (selected) => setState(() => _route = selected ? route : null)),
                    ),
                ]),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.read(warehouseRunActionsProvider).refresh(),
                child: shown.isEmpty
                    ? ListView(children: const [Padding(padding: EdgeInsets.all(48), child: Text('No hay pedidos confirmados por asignar.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)))])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _OrderTile(
                          dispatch: shown[index],
                          busy: _adding.contains(shown[index].order.orderId),
                          onAdd: run == null ? null : () => _add(run, shown[index]),
                        ),
                      ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.dispatch, required this.busy, required this.onAdd});

  final DispatchOrder dispatch;
  final bool busy;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final order = dispatch.order;
    final late = dispatch.requestedDate != null && dispatch.requestedDate!.isBefore(DateUtils.dateOnly(DateTime.now()));
    return Card(
      child: ListTile(
        title: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [order.orderNumber, order.routeName ?? 'Fuera de ruta', '${order.lines.length} líneas', if (dispatch.requestedDate != null) 'entrega ${DateFormat('d/M').format(dispatch.requestedDate!)}'].join(' · '),
          style: TextStyle(color: late ? AppColors.danger : null),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(money(order.total), style: const TextStyle(fontWeight: FontWeight.w600)),
          busy
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(tooltip: 'Agregar', icon: const Icon(Icons.add_circle, color: AppColors.brand, size: 30), onPressed: onAdd),
        ]),
      ),
    );
  }
}
