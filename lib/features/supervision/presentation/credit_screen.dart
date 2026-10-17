import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/formatting.dart';
import '../../bodega/presentation/online.dart';
import '../application/supervision_providers.dart';
import '../data/supervision_models.dart';

final _day = DateFormat('d MMM yyyy', 'es');

/// Who owes and how much is past due, most overdue first. Read only: the owner is not
/// strict with credit limits, so the limit is not managed here.
class CreditScreen extends ConsumerStatefulWidget {
  const CreditScreen({super.key});

  @override
  ConsumerState<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends ConsumerState<CreditScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _overdueOnly = false;
  int _pages = 1;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = (search: _query, overdue: _overdueOnly, pages: _pages);
    final portfolio = ref.watch(portfolioProvider(key));
    final data = portfolio.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Crédito')),
      body: Column(children: [
        if (data != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              _Total(label: 'Por cobrar', value: money(data.balance)),
              _Total(label: 'Vencido', value: money(data.overdue), color: AppColors.danger),
              _Total(label: 'Deudores', value: '${data.debtors}'),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (text) => setState(() {
              _query = text.trim();
              _pages = 1;
            }),
            decoration: const InputDecoration(hintText: 'Cliente o código', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilterChip(
              label: const Text('Solo con saldo vencido'),
              selected: _overdueOnly,
              onSelected: (value) => setState(() {
                _overdueOnly = value;
                _pages = 1;
              }),
            ),
          ),
        ),
        Expanded(
          child: data == null
              ? portfolio.hasError
                    ? LiveError(error: portfolio.error!, onRetry: () => ref.invalidate(portfolioProvider(key)))
                    : const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(portfolioProvider(key)),
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                    if (data.rows.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('Ningún cliente con estos filtros.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))),
                    for (final row in data.rows)
                      Card(
                        child: ListTile(
                          title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([row.code, if (!row.committed.isZero) 'por entregar ${money(row.committed)}'].join(' · ')),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(money(row.outstanding), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            if (!row.overdue.isZero) Text('vencido ${money(row.overdue)}', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 12)),
                          ]),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CustomerCreditScreen(row: row))),
                        ),
                      ),
                    if (data.hasMore)
                      TextButton(onPressed: portfolio.isLoading ? null : () => setState(() => _pages++), child: Text(portfolio.isLoading ? 'Cargando…' : 'Ver más clientes')),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, this.color = AppColors.ink});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color))),
    ]),
  );
}

/// One customer's open invoices, oldest due first, and their latest movements.
class _CustomerCreditScreen extends ConsumerWidget {
  const _CustomerCreditScreen({required this.row});

  final PortfolioRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credit = ref.watch(customerCreditProvider(row.customerId));
    return Scaffold(
      appBar: AppBar(title: Text(row.name)),
      body: credit.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LiveError(error: error, onRetry: () => ref.invalidate(customerCreditProvider(row.customerId))),
        data: (credit) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(customerCreditProvider(row.customerId)),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              _Total(label: 'Debe', value: money(row.outstanding)),
              _Total(label: 'Vencido', value: money(row.overdue), color: AppColors.danger),
              _Total(label: 'Por entregar', value: money(row.committed)),
            ]),
            const SizedBox(height: 16),
            Text('Facturas pendientes (${credit.debts.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (credit.debts.isEmpty) const Text('No debe nada.', style: TextStyle(color: AppColors.muted)),
            for (final debt in credit.debts)
              Card(
                child: ListTile(
                  title: Text(debt.documentNumber ?? 'Saldo', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    debt.dueDate == null
                        ? 'Sin vencimiento'
                        : debt.isOverdue
                        ? 'Venció el ${_day.format(debt.dueDate!)} · ${DateTime.now().difference(debt.dueDate!).inDays} días de atraso'
                        : 'Vence el ${_day.format(debt.dueDate!)}',
                    style: TextStyle(color: debt.isOverdue ? AppColors.danger : null),
                  ),
                  trailing: Text(money(debt.outstanding), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            const SizedBox(height: 16),
            const Text('Últimos movimientos', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final entry in credit.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text([entry.typeLabel, ?entry.receiptNumber].join(' · '), style: TextStyle(decoration: entry.reversed ? TextDecoration.lineThrough : null)),
                subtitle: entry.occurredAt == null ? null : Text(_day.format(entry.occurredAt!)),
                trailing: Text(
                  entry.debit.isZero ? '−${money(entry.credit)}' : '+${money(entry.debit)}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: entry.debit.isZero ? AppColors.brand : AppColors.ink),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
