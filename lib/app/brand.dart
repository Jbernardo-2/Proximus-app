import 'package:flutter/material.dart';

import 'theme.dart';

/// Proximus brand lockup drawn natively so it stays sharp at every density.
class ProximusLogo extends StatelessWidget {
  const ProximusLogo({super.key, this.markSize = 72});

  final double markSize;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Proximus',
    image: true,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size.square(markSize),
            painter: const _ProximusMarkPainter(),
          ),
          SizedBox(width: markSize * 0.12),
          Text(
            'Proximus',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: AppColors.brand,
              fontSize: markSize * 0.52,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProximusMarkPainter extends CustomPainter {
  const _ProximusMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 128, size.height / 128);

    final route = Path()
      ..moveTo(14, 108)
      ..lineTo(14, 36)
      ..cubicTo(14, 21.6406, 25.6406, 10, 40, 10)
      ..lineTo(72, 10)
      ..cubicTo(95.19596, 10, 114, 28.80404, 114, 52)
      ..cubicTo(114, 75.19596, 95.19596, 94, 72, 94)
      ..lineTo(56, 94)
      ..cubicTo(50.47715, 94, 46, 89.52285, 46, 84)
      ..cubicTo(46, 78.47715, 50.47715, 74, 56, 74)
      ..lineTo(72, 74)
      ..cubicTo(84.15026, 74, 94, 64.15026, 94, 52)
      ..cubicTo(94, 39.84974, 84.15026, 30, 72, 30)
      ..lineTo(40, 30)
      ..cubicTo(36.68629, 30, 34, 32.68629, 34, 36)
      ..lineTo(34, 108)
      ..cubicTo(34, 113.52285, 29.52285, 118, 24, 118)
      ..cubicTo(18.47715, 118, 14, 113.52285, 14, 108)
      ..close();

    canvas.drawPath(route, Paint()..color = AppColors.brand);
    canvas.drawCircle(
      const Offset(56, 84),
      10,
      Paint()..color = const Color(0xFFF3A629),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
