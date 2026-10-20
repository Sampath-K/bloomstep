import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'plant_art.dart';

enum GardenMomentPhase { growthAndLanding, song, settling, complete }

/// One finite, silent moment for an accepted, durably saved practice.
/// Sound is deliberately unavailable rather than substituting a notification beep.
class GardenMoment extends StatefulWidget {
  const GardenMoment({
    super.key,
    required this.stage,
    required this.species,
    required this.reducedMotion,
    this.completion,
    this.previousStage,
    this.animate = true,
    this.onFinished,
  });

  static const duration = Duration(milliseconds: 1000);
  static GardenMomentPhase phaseAt(
    Duration elapsed, {
    bool reducedMotion = false,
  }) {
    if (reducedMotion || elapsed >= duration) {
      return GardenMomentPhase.complete;
    }
    if (elapsed < const Duration(milliseconds: 300)) {
      return GardenMomentPhase.growthAndLanding;
    }
    if (elapsed < const Duration(milliseconds: 800)) {
      return GardenMomentPhase.song;
    }
    return GardenMomentPhase.settling;
  }
  final GrowthStage stage;
  final GrowthStage? previousStage;
  final String species;
  final bool reducedMotion;
  final String? completion;
  final bool animate;
  final VoidCallback? onFinished;

  @override
  State<GardenMoment> createState() => _GardenMomentState();
}

class _GardenMomentState extends State<GardenMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: GardenMoment.duration,
    value: 1,
  );
  String? _played;
  String? _finished;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  void _finish() {
    final completion = widget.completion;
    if (!widget.animate || completion == null || completion == _finished) return;
    _finished = completion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.completion == completion) widget.onFinished?.call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(GardenMoment oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final reduce =
        widget.reducedMotion || MediaQuery.disableAnimationsOf(context);
    if (reduce || !widget.animate) {
      final finishStatic =
          widget.completion != null &&
          widget.completion != _played &&
          widget.animate &&
          _controller.value == 1;
      _controller.stop();
      _controller.value = 1;
      _played = widget.completion;
      if (finishStatic) _finish();
    } else if (widget.completion != null && widget.completion != _played) {
      _played = widget.completion;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label:
        '${widget.species}, ${widget.stage.name}${widget.completion == null ? '' : ', lark perched. Practice saved'}.',
    child: ExcludeSemantics(
      child: FittedBox(
        child: SizedBox(
          width: 300,
          height: 200,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final growth = (t / .3).clamp(0.0, 1.0).toDouble();
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.previousStage != null && growth < 1)
                    Opacity(
                      opacity: 1 - growth,
                      child: PlantArt(
                        stage: widget.previousStage!,
                        species: widget.species,
                      ),
                    ),
                  Opacity(
                    opacity: growth,
                    child: PlantArt(
                      stage: widget.stage,
                      species: widget.species,
                    ),
                  ),
                  if (widget.completion != null)
                    CustomPaint(
                      painter: _LarkPainter(t, Theme.of(context).colorScheme),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _LarkPainter extends CustomPainter {
  _LarkPainter(this.progress, this.colors);
  final double progress;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final landing = (progress / .3).clamp(0.0, 1.0).toDouble();
    final settle = progress >= .8
        ? math.sin((progress - .8) / .2 * math.pi) * 2
        : 0.0;
    final perch = Offset(size.width * .69, size.height * .775);
    final point = perch.translate(
      (1 - landing) * size.width * .22,
      -(1 - landing) * size.height * .48 + settle,
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..color = colors.tertiary;
    canvas.drawOval(
      Rect.fromCenter(center: point, width: 29, height: 19),
      paint,
    );
    canvas.drawCircle(point.translate(-12, -10), 9, paint);
    canvas.drawPath(
      Path()
        ..moveTo(point.dx - 20, point.dy - 10)
        ..lineTo(point.dx - 28, point.dy - 7)
        ..lineTo(point.dx - 20, point.dy - 4)
        ..close(),
      paint..color = colors.primary,
    );
    canvas.drawPath(
      Path()
        ..moveTo(point.dx + 11, point.dy)
        ..lineTo(point.dx + 25, point.dy - 10)
        ..lineTo(point.dx + 20, point.dy + 6)
        ..close(),
      paint..color = colors.tertiary,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: point.translate(2, -2 - (1 - landing) * 9),
        width: 16,
        height: 9 + (1 - landing) * 12,
      ),
      paint..color = colors.secondary,
    );
    canvas.drawCircle(
      point.translate(-15, -12),
      1.8,
      paint..color = colors.onTertiary,
    );
    paint
      ..color = colors.primary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final dx in [-3.0, 5.0]) {
      canvas.drawLine(
        point.translate(dx, 8),
        perch.translate(dx, 15),
        paint,
      );
    }
    canvas.drawLine(
      perch.translate(-12, 15),
      perch.translate(18, 15),
      paint,
    );
    // Song marks are visual only, confined to the approved 300–800 ms window.
    final phase = GardenMoment.phaseAt(
      Duration(microseconds: (progress * 1000000).round()),
    );
    if (phase == GardenMomentPhase.song) {
      final song = (progress - .3) / .5;
      for (var i = 0; i < 3; i++) {
        final note = point.translate(-35 - i * 12, -20 - i * 10 - song * 6);
        canvas.drawCircle(note, 2.5, paint);
        canvas.drawLine(note, note.translate(0, -9), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LarkPainter oldDelegate) =>
      progress != oldDelegate.progress || colors != oldDelegate.colors;
}
