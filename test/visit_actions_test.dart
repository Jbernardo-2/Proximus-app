import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/app/theme.dart';
import 'package:proximus_app/features/preventa/presentation/visit_actions.dart';

void main() {
  // Measures of the test phone (Samsung S21 Ultra): 384 dp wide, system font at 110 %.
  for (final (width, scale) in [(384.0, 1.1), (320.0, 1.3)]) {
    testWidgets('visit actions keep one line at $width dp and font $scale', (tester) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Padding(padding: const EdgeInsets.all(30), child: VisitActions(onNoSale: () {}))),
        ),
      ));

      expect(tester.takeException(), isNull);
      for (final label in ['Sin venta', 'Abono', 'Pedido']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
        expect(tester.getSize(find.text(label)).height, lessThan(30), reason: '$label should stay on one line');
      }
    });
  }
}
