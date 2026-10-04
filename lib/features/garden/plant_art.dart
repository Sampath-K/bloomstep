import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/models.dart';

class PlantArt extends StatelessWidget {
  const PlantArt({super.key, required this.stage, required this.species});
  final GrowthStage stage;
  final String species;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PlantPainter(stage, species, Theme.of(context).colorScheme),
  );
}

class _PlantPainter extends CustomPainter {
  _PlantPainter(this.stage, this.species, this.colors);
  final GrowthStage stage;
  final String species;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .85);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, 8),
        width: size.width * .65,
        height: 25,
      ),
      paint..color = colors.secondaryContainer,
    );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 46, height: 20),
      paint..color = colors.tertiary,
    );
    if (stage == GrowthStage.seed) {
      canvas.drawOval(
        Rect.fromCenter(center: center.translate(0, -7), width: 14, height: 20),
        paint..color = colors.primary,
      );
      canvas.drawCircle(
        center.translate(0, -23),
        3,
        paint..color = colors.primaryContainer,
      );
      return;
    }
    final height = 45.0 + stage.index * 23;
    final tip = center.translate(0, -height);
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(
          center.dx - 12,
          center.dy - height / 2,
          tip.dx,
          tip.dy,
        ),
      paint
        ..color = colors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    paint.style = PaintingStyle.fill;
    final leafCount = species == 'Fern' ? stage.index * 3 : stage.index + 1;
    for (var i = 0; i < leafCount; i++) {
      final y = center.dy - 24 - (height - 40) * i / max(1, leafCount - 1);
      final sign = i.isEven ? -1.0 : 1.0;
      final leaf = Path()
        ..moveTo(center.dx, y)
        ..quadraticBezierTo(
          center.dx + sign * 50,
          y - 38,
          center.dx + sign * 45,
          y - 5,
        )
        ..quadraticBezierTo(center.dx + sign * 20, y + 10, center.dx, y);
      canvas.drawPath(
        leaf,
        paint..color = i.isEven ? colors.primary : colors.secondary,
      );
    }
    if (stage.index >= 3) {
      final radius = stage == GrowthStage.bloom ? 24.0 : 9.0;
      final petals = species == 'Sunflower' ? 12 : 6;
      for (var i = 0; i < petals; i++) {
        final a = i * pi * 2 / petals;
        canvas.drawCircle(
          tip.translate(cos(a) * radius * .7, sin(a) * radius * .7),
          radius * .6,
          paint..color = colors.tertiaryContainer,
        );
      }
      canvas.drawCircle(tip, radius * .45, paint..color = colors.tertiary);
    }
    if (stage == GrowthStage.bloom) {
      for (final offset in [const Offset(-70, -90), const Offset(65, -60)]) {
        canvas.drawCircle(center + offset, 4, paint..color = colors.tertiary);
        canvas.drawOval(
          Rect.fromCenter(
            center: center + offset + const Offset(0, -5),
            width: 14,
            height: 5,
          ),
          paint..color = colors.primaryContainer,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PlantPainter oldDelegate) =>
      stage != oldDelegate.stage ||
      species != oldDelegate.species ||
      colors != oldDelegate.colors;
}
