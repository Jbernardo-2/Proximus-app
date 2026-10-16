import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/payment_split.dart';
import 'package:proximus_app/features/preventa/presentation/payment_split_editor.dart';

DecimalValue d(String value) => DecimalValue.parse(value);

const methods = [(value: 'cash', label: 'Efectivo'), (value: 'bank_transfer', label: 'Transferencia'), (value: 'card', label: 'Tarjeta'), (value: 'credit', label: 'Crédito')];

void main() {
  final total = d('2347.83');

  test('the example: 1000 cash, then 750 by transfer, leaves 597.83 to assign', () {
    var lines = <SplitLine>[(method: 'cash', amount: total, reference: null)];
    lines = splitEdit(lines, 0, d('1000'), total);
    expect(total - splitAssigned(lines), d('1347.83'), reason: 'a single line never adjusts itself');

    lines = splitAdd(lines, 'bank_transfer', total);
    expect(lines.last.amount, d('1347.83'), reason: 'a new method brings what is missing');

    lines = splitEdit(lines, 1, d('750'), total);
    expect(lines.first.amount, d('1000'), reason: 'changing the second line never moves the first');
    expect(total - splitAssigned(lines), d('597.83'));

    lines = splitEdit(lines, 0, d('1200'), total);
    expect(lines.last.amount, d('1147.83'), reason: 'changing the first of two balances the second');

    lines = splitAdd(splitEdit(lines, 0, d('500'), total), 'card', total);
    lines = splitEdit(lines, 2, d('100'), total);
    expect(total - splitAssigned(lines), d('-100'), reason: '500 + 1847.83 + 100 is 100 over');
    lines = splitComplete(lines, 2, total);
    expect(lines[2].amount, DecimalValue.zero, reason: '"Ajustar" gives back what is over, never below zero');
    expect(splitAssigned(lines), total);

    expect(splitRemove(splitRemove(lines, 2, total), 1, total).single.amount, total);
  });

  testWidgets('the bar always says what is left', (tester) async {
    tester.view.physicalSize = const Size(384 * 3, 820 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    var lines = <SplitLine>[(method: 'cash', amount: total, reference: null)];
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [
            PaymentSplitEditor(total: total, lines: lines, methods: methods, requiringReference: const {'card'}, onChanged: (next) => setState(() => lines = next)),
          ]),
          bottomNavigationBar: SplitRemainingBar(total: total, lines: lines),
        ),
      ),
    ));
    expect(find.text('Completo'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '1000');
    await tester.pump();
    expect(find.text('Falta distribuir L 1,347.83'), findsOneWidget);
    expect(find.text('Agregar forma de pago (L 1,347.83)'), findsOneWidget);

    await tester.tap(find.text('Agregar forma de pago (L 1,347.83)'));
    await tester.pump();
    expect(find.text('Completo'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Monto').last, '750');
    await tester.pump();
    expect(find.text('Falta distribuir L 597.83'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Monto').first, '3000');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Monto').last, '750');
    await tester.pump();
    expect(find.text('Sobran L 1,402.17'), findsOneWidget);

    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Quitar').last);
    await tester.pumpAndSettle();
    expect(find.text('Completo'), findsOneWidget, reason: 'back to one method, it takes the whole total');
    expect(tester.takeException(), isNull);
  });
}
