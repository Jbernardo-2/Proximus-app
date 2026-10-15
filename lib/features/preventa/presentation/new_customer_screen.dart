import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/location_capture.dart';
import '../application/preventa_actions.dart';

const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _businessTypes = ['Pulpería', 'Minisúper', 'Abarrotería', 'Bodega', 'Cafetería', 'Comedor', 'Farmacia'];

/// Registers a customer met on the route. It works without signal: the customer is
/// on the phone at once (orders, no-sale visits) and reaches the server later.
class NewCustomerScreen extends ConsumerStatefulWidget {
  const NewCustomerScreen({super.key});

  @override
  ConsumerState<NewCustomerScreen> createState() => _NewCustomerScreenState();
}

class _NewCustomerScreenState extends ConsumerState<NewCustomerScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _type = TextEditingController();
  final _address = TextEditingController();
  final _reference = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _notes = TextEditingController();
  LocationSession? _location;
  int _visitDay = DateTime.now().weekday;
  String? _routeId;
  bool _sameWhatsapp = true;
  bool _useLocation = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _location = ref.read(locationServiceProvider).start();
  }

  @override
  void dispose() {
    for (final controller in [_name, _type, _address, _reference, _contact, _phone, _whatsapp, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  static String? _text(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save(List<({String id, String name})> routes) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final phone = _text(_phone);
      final id = await ref.read(preventaActionsProvider).registerCustomer(
            businessName: _name.text.trim(),
            address: _address.text.trim(),
            visitDay: _visitDay,
            salesRouteId: _routeId ?? (routes.length == 1 ? routes.single.id : null),
            businessType: _text(_type),
            contactName: _text(_contact),
            phone: phone,
            whatsapp: _sameWhatsapp ? phone : _text(_whatsapp),
            reference: _text(_reference),
            notes: _text(_notes),
            location: _useLocation ? _location : null,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cliente guardado en el teléfono: ${_name.text.trim()}.')));
      context.pushReplacement('/customer/$id');
    } catch (error, stack) {
      debugPrint('No se pudo registrar el cliente: $error\n$stack');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo registrar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final routes = [
      for (final route in ref.watch(localRecordsProvider('routes')).value ?? const <Map<String, dynamic>>[])
        (id: route['id'].toString(), name: route['name']?.toString() ?? 'Ruta'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo cliente')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre del negocio *'),
              validator: (value) => (value ?? '').trim().isEmpty ? 'Escribe el nombre del negocio.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _type,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Tipo de negocio'),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final type in _businessTypes)
                ChoiceChip(
                  label: Text(type),
                  visualDensity: VisualDensity.compact,
                  selected: _type.text == type,
                  onSelected: (_) => setState(() => _type.text = type),
                ),
            ]),
            const SizedBox(height: 16),
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Dirección *'),
              validator: (value) => (value ?? '').trim().isEmpty ? 'Escribe la dirección.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reference,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Referencia', hintText: 'Ej.: frente a la iglesia'),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _useLocation,
              onChanged: (value) => setState(() => _useLocation = value),
              title: const Text('Guardar mi ubicación como la del negocio'),
              subtitle: const Text('Actívalo solo si estás en el negocio.'),
            ),
            const Divider(height: 24),
            TextFormField(
              controller: _contact,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Persona de contacto'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _sameWhatsapp,
              onChanged: (value) => setState(() => _sameWhatsapp = value ?? true),
              title: const Text('El WhatsApp es el mismo número'),
            ),
            if (!_sameWhatsapp)
              TextFormField(
                controller: _whatsapp,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'WhatsApp'),
              ),
            const Divider(height: 24),
            if (routes.length > 1) ...[
              DropdownButtonFormField<String>(
                initialValue: _routeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ruta *'),
                items: [for (final route in routes) DropdownMenuItem(value: route.id, child: Text(route.name))],
                onChanged: (value) => setState(() => _routeId = value),
                validator: (value) => value == null ? 'Elige en qué ruta queda el cliente.' : null,
              ),
              const SizedBox(height: 12),
            ],
            const Text('Día de visita', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var day = 1; day <= 7; day++)
                ChoiceChip(
                  label: Text(_weekdays[day - 1]),
                  selected: _visitDay == day,
                  onSelected: (_) => setState(() => _visitDay = day),
                ),
            ]),
            if (_visitDay == DateTime.now().weekday)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Aparecerá hoy en tu ruta del día.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : () => _save(routes),
            child: _saving ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar cliente'),
          ),
        ),
      ),
    );
  }
}
