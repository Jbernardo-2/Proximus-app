import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../preventa/presentation/daily_route_screen.dart' show StatusChip;
import '../application/bodega_providers.dart';
import '../application/warehouse_run_actions.dart';
import '../data/warehouse_runs.dart';

final _date = DateFormat('EEE d MMM', 'es');

const _sections = {'draft': 'Por armar', 'preparing': 'En preparación', 'loaded': 'Listas para salir'};

/// The runs the warehouse assembles, prepares and loads, in that order.
class WarehouseRunsScreen extends ConsumerWidget {
  const WarehouseRunsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(warehouseRunsProvider);
    final waiting = ref.watch(availableOrdersProvider).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Jornadas de bodega')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _newRun(context, ref), icon: const Icon(Icons.add), label: const Text('Nueva jornada')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (waiting > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('$waiting ${waiting == 1 ? 'pedido espera' : 'pedidos esperan'} jornada.', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ),
          if (runs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text('No hay jornadas abiertas. Crea una para asignar pedidos.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            ),
          for (final section in _sections.entries)
            if (runs.any((run) => run.status == section.key)) ...[
              Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Text(section.value, style: const TextStyle(fontWeight: FontWeight.w700))),
              for (final run in runs.where((run) => run.status == section.key)) RunCard(run: run),
            ],
        ],
      ),
    );
  }

  Future<void> _newRun(BuildContext context, WidgetRef ref) async {
    final id = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const NewRunSheet());
    if (id != null && context.mounted) context.push('/warehouse-runs/$id');
  }
}

class RunCard extends ConsumerWidget {
  const RunCard({super.key, required this.run});

  final WarehouseRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final heldByOther = run.isPreparing && session != null && !run.preparableBy(session.userId, supervises: session.role != 'bodeguero');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(run.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text([run.driverName, if (run.scheduledDate != null) _date.format(run.scheduledDate!), '${run.orders.length} ${run.orders.length == 1 ? 'pedido' : 'pedidos'}'].join(' · ')),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (run.pending) const StatusChip(text: 'Sin enviar', color: AppColors.amber),
            if (heldByOther) const StatusChip(text: 'La prepara otro', color: AppColors.muted),
            if (run.rejections.isNotEmpty) const StatusChip(text: 'Rechazo', color: AppColors.danger),
          ]),
        ]),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/warehouse-runs/${run.id}'),
      ),
    );
  }
}

/// Who drives, with what and when; the orders come next on the run itself.
class NewRunSheet extends ConsumerStatefulWidget {
  const NewRunSheet({super.key});

  @override
  ConsumerState<NewRunSheet> createState() => _NewRunSheetState();
}

class _NewRunSheetState extends ConsumerState<NewRunSheet> {
  String? _driverId;
  String? _vehicleId;
  String? _warehouseId;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final drivers = ref.watch(driversProvider);
    final vehicles = ref.watch(vehiclesProvider);
    final warehouses = ref.watch(warehouseNamesProvider);
    final warehouseId = _warehouseId ?? warehouses.keys.firstOrNull;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Nueva jornada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        if (drivers.isEmpty)
          const Text('No hay repartidores descargados. Sincroniza con señal.', style: TextStyle(color: AppColors.danger))
        else
          DropdownButtonFormField<String>(
            initialValue: _driverId,
            decoration: const InputDecoration(labelText: 'Repartidor'),
            items: [for (final driver in drivers.entries) DropdownMenuItem(value: driver.key, child: Text(driver.value))],
            onChanged: (value) => setState(() => _driverId = value),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _vehicleId,
          decoration: const InputDecoration(labelText: 'Vehículo (opcional)'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Sin vehículo')),
            for (final vehicle in vehicles.entries) DropdownMenuItem(value: vehicle.key, child: Text(vehicle.value)),
          ],
          onChanged: (value) => setState(() => _vehicleId = value),
        ),
        if (warehouses.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: warehouseId,
            decoration: const InputDecoration(labelText: 'Bodega'),
            items: [for (final warehouse in warehouses.entries) DropdownMenuItem(value: warehouse.key, child: Text(warehouse.value))],
            onChanged: (value) => setState(() => _warehouseId = value),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.event_outlined),
          label: Text('Sale el ${DateFormat("EEEE d 'de' MMMM", 'es').format(_date)}'),
          onPressed: () async {
            final today = DateTime.now();
            final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(today.year, today.month, today.day), lastDate: today.add(const Duration(days: 30)));
            if (picked != null) setState(() => _date = picked);
          },
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _driverId == null || warehouseId == null || _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  final navigator = Navigator.of(context);
                  final id = await ref.read(warehouseRunActionsProvider).create(warehouseId: warehouseId, driverId: _driverId!, vehicleId: _vehicleId, date: _date);
                  navigator.pop(id);
                },
          child: const Text('Crear y asignar pedidos'),
        ),
      ]),
    );
  }
}
