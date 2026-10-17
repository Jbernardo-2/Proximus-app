import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/api.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../../bodega/application/warehouse_run_actions.dart';
import '../../bodega/presentation/online.dart';
import '../../bodega/presentation/warehouse_run_screen.dart' show BottomAction;
import '../application/supervision_providers.dart';
import '../data/supervision_models.dart';

/// Runs back from the road with their cash still to count.
class SettlementsScreen extends ConsumerWidget {
  const SettlementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(settlementsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Liquidar jornadas')),
      body: runs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LiveError(error: error, onRetry: () => ref.invalidate(liveResourceProvider('delivery_runs'))),
        data: (runs) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(liveResourceProvider('delivery_runs')),
          child: runs.isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('No hay jornadas por liquidar.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)))])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: runs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => Card(
                    child: ListTile(
                      title: Text('${runs[index].runNumber} · ${runs[index].driverName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('Efectivo a recibir ${money(runs[index].cashToReceive)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settlements/${runs[index].runId}'),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Counting a run's cash, as on the web: the sale must balance, the counted cash is
/// compared live with what the driver must hand over, and a difference needs a note.
class SettlementScreen extends ConsumerStatefulWidget {
  const SettlementScreen({super.key, required this.runId});

  final String runId;

  @override
  ConsumerState<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends ConsumerState<SettlementScreen> {
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  final _reasons = <String, TextEditingController>{};
  bool _saving = false;
  String? _refusal;

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    for (final field in _reasons.values) {
      field.dispose();
    }
    super.dispose();
  }

  DecimalValue? get _countedValue {
    try {
      return _counted.text.trim().isEmpty ? null : DecimalValue.parse(_counted.text.trim());
    } on FormatException {
      return null;
    }
  }

  Future<void> _settle(SettlementView run, DecimalValue counted) async {
    final difference = run.difference(counted);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liquidar jornada'),
        content: Text([
          'Efectivo contado ${money(counted)}.',
          difference.isZero ? 'Cuadra con lo que debía entregar.' : '${difference.isNegative ? 'Faltan' : 'Sobran'} ${money(difference.isNegative ? -difference : difference)}.',
          'Los resultados ya no podrán editarse.',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Revisar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Liquidar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _refusal = null;
    });
    try {
      await ref.read(settlementActionsProvider).settle(run, counted: counted, notes: _notes.text, creditReasons: {for (final entry in _reasons.entries) entry.key: entry.value.text});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${run.runNumber} liquidada${difference.isZero ? ': efectivo cuadrado' : ''}.')));
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _refusal = error.isNetwork ? 'Sin conexión: no se liquidó. Revisa la señal e intenta de nuevo.' : error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(settlementProvider(widget.runId));
    final run = value.value;
    if (run == null) {
      return Scaffold(
        appBar: AppBar(),
        body: value.isLoading
            ? const Center(child: CircularProgressIndicator())
            : value.hasError
            ? LiveError(error: value.error!, onRetry: () => ref.invalidate(liveResourceProvider('delivery_runs')))
            : const Center(child: Text('Esta jornada ya no está por liquidar.', style: TextStyle(color: AppColors.muted))),
      );
    }
    final counted = _countedValue;
    final difference = counted == null ? null : run.difference(counted);
    final needsNote = difference != null && !difference.isZero && _notes.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(run.runNumber)),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(run.driverName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: (run.balanced ? AppColors.brand : AppColors.danger).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(run.balanced ? 'La venta cuadra ✓' : 'La venta no cuadra', style: TextStyle(fontWeight: FontWeight.w800, color: run.balanced ? AppColors.brand : AppColors.danger)),
                const SizedBox(height: 4),
                Text('Entregado ${money(run.delivered)} = cobrado ${money(run.collected)} + crédito ${money(run.credit)}'),
                Text('Transferencias ${money(run.transfers)} · tarjeta, cheque y otros ${money(run.otherMethods)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 12),
            _Line(label: 'Efectivo de entregas', value: money(run.deliveryCash)),
            _Line(label: 'Efectivo de abonos', value: money(run.accountPaymentCash)),
            _Line(label: 'Efectivo a recibir', value: money(run.cashToReceive), lead: true),
            const SizedBox(height: 12),
            TextField(
              controller: _counted,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Efectivo contado', prefixText: 'L ', hintText: 'Cuenta el efectivo'),
            ),
            if (difference != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  difference.isZero ? 'Cuadra ✓' : '${difference.isNegative ? 'Faltan' : 'Sobran'} ${money(difference.isNegative ? -difference : difference)}',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: difference.isZero ? AppColors.brand : AppColors.danger),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              enabled: !_saving,
              maxLength: 3000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Observaciones', helperText: needsNote ? 'Obligatorio cuando hay diferencia de efectivo' : null, helperStyle: const TextStyle(color: AppColors.danger)),
            ),
            if (run.returns.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Mercadería que regresa', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('Lo devuelto vuelve a bodega; lo dañado y lo faltante quedan como pérdida.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              for (final row in run.returns)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${row.product} · ${row.presentation}'),
                  subtitle: Text([
                    if (!row.returned.isZero) 'Devuelto ${row.returned}',
                    if (!row.damaged.isZero) 'Dañado ${row.damaged}',
                    if (!row.missing.isZero) 'Faltó ${row.missing}',
                  ].join(' · ')),
                ),
            ],
            if (run.cashOrdersWithBalance.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Saldos de contado sin acuerdo (${run.cashOrdersWithBalance.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Opcional: anota el acuerdo con el cliente.'),
                children: [
                  for (final order in run.cashOrdersWithBalance)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _reasons.putIfAbsent(order.runOrderId, TextEditingController.new),
                        maxLength: 2000,
                        decoration: InputDecoration(labelText: '${order.label} — saldo ${money(order.balance)}', hintText: 'Ejemplo: pagará en su próxima visita'),
                      ),
                    ),
                ],
              ),
            if (_refusal != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Text(_refusal!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        BottomAction(
          child: FilledButton.icon(
            onPressed: counted == null || needsNote || _saving ? null : () => _settle(run, counted),
            icon: const Icon(Icons.point_of_sale_outlined),
            label: Text(_saving ? 'Liquidando…' : 'Liquidar jornada'),
          ),
        ),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.lead = false});

  final String label;
  final String value;
  final bool lead;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(color: lead ? AppColors.ink : AppColors.muted, fontWeight: lead ? FontWeight.w700 : FontWeight.normal))),
      Text(value, style: TextStyle(fontSize: lead ? 20 : 15, fontWeight: lead ? FontWeight.w800 : FontWeight.w600)),
    ]),
  );
}
