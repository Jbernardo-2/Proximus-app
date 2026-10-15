import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/location_capture.dart';
import '../application/preventa_actions.dart';
import '../data/preventa_models.dart';

/// Asks why there was no sale and saves the visit on the phone. True when saved.
Future<bool?> showNoSaleSheet(BuildContext context, LocalCustomer customer, {String? routeStopId}) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NoSaleSheet(customer: customer, routeStopId: routeStopId),
    );

class _NoSaleSheet extends ConsumerStatefulWidget {
  const _NoSaleSheet({required this.customer, this.routeStopId});

  final LocalCustomer customer;
  final String? routeStopId;

  @override
  ConsumerState<_NoSaleSheet> createState() => _NoSaleSheetState();
}

class _NoSaleSheetState extends ConsumerState<_NoSaleSheet> {
  late final LocationSession _location = ref.read(locationServiceProvider).start();
  final _notes = TextEditingController();
  String? _reason;
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(preventaActionsProvider).recordNoSale(
            customer: widget.customer,
            routeStopId: widget.routeStopId,
            reason: _reason!,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            location: _location,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasons = ref.watch(manifestProvider).value?.options('visit_reasons') ?? const [];
    final needsNotes = _reason == 'other';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sin venta', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(widget.customer.businessName, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (value) => setState(() => _reason = value),
            child: Column(children: [
              for (final reason in reasons)
                RadioListTile<String>(value: reason.value, title: Text(reason.label), contentPadding: EdgeInsets.zero, dense: true),
            ]),
          ),
          TextField(
            controller: _notes,
            decoration: InputDecoration(labelText: needsNotes ? 'Explica el motivo' : 'Notas (opcional)'),
            maxLines: 2,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving || _reason == null || (needsNotes && _notes.text.trim().isEmpty) ? null : _save,
            child: _saving ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar visita'),
          ),
        ],
      ),
    );
  }
}
