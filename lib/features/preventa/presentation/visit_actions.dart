import 'package:flutter/material.dart';

/// "Sin venta", "Abono" and "Pedido" of a customer visit. Same width each and
/// one line of text, so they fit narrow phones with large system fonts.
class VisitActions extends StatelessWidget {
  const VisitActions({super.key, this.onNoSale, this.onPayment, this.onOrder});

  final VoidCallback? onNoSale;
  final VoidCallback? onPayment;
  final VoidCallback? onOrder;

  static const _padding = EdgeInsets.symmetric(horizontal: 6);
  static const _size = Size(0, 46);

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: _size, padding: _padding),
            onPressed: onNoSale,
            child: const _Label('Sin venta'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: _size, padding: _padding),
            onPressed: onPayment,
            child: const _Label('Abono'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: _size, padding: _padding),
            onPressed: onOrder,
            child: const _Label('Pedido', icon: Icons.add_shopping_cart),
          ),
        ),
      ]);
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
          Text(text, maxLines: 1, softWrap: false),
        ]),
      );
}
