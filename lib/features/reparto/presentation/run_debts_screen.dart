import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/decimal_value.dart';
import '../../../core/formatting.dart';
import '../application/delivery_providers.dart';

/// A customer of the run who owes money from before, apart from today's delivery.
typedef RunDebt = ({String customerId, String name, String address, DecimalValue outstanding, DecimalValue overdue});

/// Customers of the run with old debts, overdue first: the driver sees in one place who
/// to collect from, instead of finding it stop by stop.
final runDebtsProvider = Provider.family<List<RunDebt>, String>((ref, runId) {
  final run = ref.watch(deliveryRunProvider(runId));
  if (run == null) return const [];
  final balances = ref.watch(customerBalancesProvider);
  final seen = <String>{};
  return [
    for (final stop in run.stops)
      if (seen.add(stop.customerId) && !(balances[stop.customerId]?.outstanding ?? DecimalValue.zero).isZero)
        (customerId: stop.customerId, name: stop.customerName, address: stop.customerAddress, outstanding: balances[stop.customerId]!.outstanding, overdue: balances[stop.customerId]!.overdue),
  ]..sort((a, b) {
    final byOverdue = b.overdue.compareTo(a.overdue);
    return byOverdue != 0 ? byOverdue : b.outstanding.compareTo(a.outstanding);
  });
});

class RunDebtsScreen extends ConsumerWidget {
  const RunDebtsScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(runDebtsProvider(runId));
    final total = debts.fold(DecimalValue.zero, (sum, debt) => sum + debt.outstanding);
    final canCollect = ref.watch(manifestProvider).value?.supports('customer.payment') ?? false;

    return Scaffold(
      appBar: AppBar(title: Text('Saldos pendientes (${debts.length})')),
      body: debts.isEmpty
          ? const Center(
              child: Text('Ningún cliente de esta jornada tiene saldo pendiente.', style: TextStyle(color: AppColors.muted)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Text('Por cobrar en total ${money(total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final debt in debts)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(debt.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(
                                  debt.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  money(debt.outstanding),
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: debt.overdue.isZero ? AppColors.ink : AppColors.danger),
                                ),
                                if (!debt.overdue.isZero)
                                  Text(
                                    'Vencido ${money(debt.overdue)}',
                                    style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600),
                                  ),
                              ],
                            ),
                          ),
                          if (canCollect)
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: () => context.push('/payment/${debt.customerId}'),
                              child: const Text('Recibir abono'),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
