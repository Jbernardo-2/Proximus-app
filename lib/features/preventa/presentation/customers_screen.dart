import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/formatting.dart';

/// The preventista's customers, searchable without signal.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final terms = _query.toLowerCase().split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
    final customers = ref.watch(customerListProvider).where((customer) {
      final haystack = '${customer.businessName} ${customer.code} ${customer.address} ${customer.contactName ?? ''} ${customer.phone ?? ''}'.toLowerCase();
      return terms.every(haystack.contains);
    }).toList();
    final balances = ref.watch(customerBalancesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nombre, código, dirección o teléfono'),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: customers.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty ? 'No hay clientes en el teléfono. Sincroniza con señal.' : 'Ningún cliente coincide.',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: customers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final customer = customers[index];
                    final balance = balances[customer.id];
                    return Card(
                      child: ListTile(
                        onTap: () => context.go('/customer/${customer.id}'),
                        title: Text(customer.businessName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(customer.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: balance == null || balance.outstanding.isZero
                            ? const Icon(Icons.chevron_right)
                            : Text(
                                money(balance.outstanding),
                                style: TextStyle(fontWeight: FontWeight.w700, color: balance.overdue.isZero ? AppColors.ink : AppColors.danger),
                              ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
