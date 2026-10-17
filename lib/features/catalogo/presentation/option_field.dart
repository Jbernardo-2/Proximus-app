import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/api.dart';
import '../../bodega/presentation/online.dart';
import '../application/catalog_admin.dart';
import '../data/catalog_models.dart';

/// A form field that picks a category, brand, unit or supplier from the server.
class OptionField extends StatelessWidget {
  const OptionField({super.key, required this.kind, required this.value, required this.onChanged, this.required = true, this.enabled = true});

  final OptionKind kind;
  final CatalogOption? value;
  final ValueChanged<CatalogOption?> onChanged;
  final bool required;
  final bool enabled;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: !enabled
        ? null
        : () async {
            final picked = await Navigator.of(context).push<CatalogOption>(MaterialPageRoute(builder: (_) => OptionPickerScreen(kind: kind)));
            if (picked != null) onChanged(picked);
          },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: '${kind.label}${required ? ' *' : ' (opcional)'}',
        suffixIcon: !required && value != null && enabled ? IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: () => onChanged(null)) : const Icon(Icons.arrow_drop_down),
      ),
      isEmpty: value == null,
      child: value == null ? null : Text(value!.label),
    ),
  );
}

/// Searches the list on the server; what is not there can be created with what was typed.
class OptionPickerScreen extends ConsumerStatefulWidget {
  const OptionPickerScreen({super.key, required this.kind});

  final OptionKind kind;

  @override
  ConsumerState<OptionPickerScreen> createState() => _OptionPickerScreenState();
}

class _OptionPickerScreenState extends ConsumerState<OptionPickerScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _creating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _query.trim();
    String? symbol;
    if (widget.kind == OptionKind.unit) {
      symbol = await showDialog<String>(context: context, builder: (_) => _SymbolDialog(name: name));
      if (symbol == null) return;
    }
    if (!mounted) return;
    setState(() => _creating = true);
    CatalogOption? created;
    await runOnline(context, () async => created = await ref.read(catalogAdminProvider).createOption(widget.kind, name, symbol: symbol));
    if (!mounted) return;
    setState(() => _creating = false);
    if (created != null) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(catalogOptionsProvider((kind: widget.kind, search: _query.trim())));
    final exact = options.value?.any((option) => option.name.toLowerCase() == _query.trim().toLowerCase()) ?? false;

    return Scaffold(
      appBar: AppBar(title: Text('Elegir ${widget.kind.label.toLowerCase()}')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: (text) => setState(() => _query = text),
            decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search)),
          ),
        ),
        if (_query.trim().isNotEmpty && !exact)
          ListTile(
            leading: _creating ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_circle, color: AppColors.brand),
            title: Text('Crear «${_query.trim()}»', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
            onTap: _creating ? null : _create,
          ),
        Expanded(
          child: options.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => LiveError(error: error, onRetry: () => ref.invalidate(catalogOptionsProvider)),
            data: (options) => ListView(children: [
              for (final option in options) ListTile(title: Text(option.label), onTap: () => Navigator.pop(context, option)),
              if (options.isEmpty && _query.trim().isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Escribe para buscar o crear.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SymbolDialog extends StatefulWidget {
  const _SymbolDialog({required this.name});

  final String name;

  @override
  State<_SymbolDialog> createState() => _SymbolDialogState();
}

class _SymbolDialogState extends State<_SymbolDialog> {
  late final _symbol = TextEditingController(text: widget.name.length <= 4 ? widget.name.toLowerCase() : '');

  @override
  void dispose() {
    _symbol.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Unidad «${widget.name}»'),
    content: TextField(controller: _symbol, autofocus: true, maxLength: 20, decoration: const InputDecoration(labelText: 'Símbolo', hintText: 'Ejemplo: lb, kg, u')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: () => _symbol.text.trim().isEmpty ? null : Navigator.pop(context, _symbol.text.trim()), child: const Text('Crear')),
    ],
  );
}

/// The server's reason a save was refused, in the form being saved.
class Refusal extends StatelessWidget {
  const Refusal(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
    child: Text(message, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
  );
}

/// Runs a save; returns the refusal to show, or null when it went through.
Future<String?> trySave(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } on ApiException catch (error) {
    return error.isNetwork ? 'Sin conexión: no se guardó. Revisa la señal e intenta de nuevo.' : error.message;
  }
}
