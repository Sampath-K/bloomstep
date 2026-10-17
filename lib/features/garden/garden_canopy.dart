import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'plant_art.dart';

/// Decorative garden scenery, not a visualization of practice or progress.
class GardenCanopy extends StatelessWidget {
  const GardenCanopy({
    super.key,
    required this.reducedMotion,
    required this.heading,
    this.compact = false,
  });

  final bool reducedMotion;
  final Widget heading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduce = reducedMotion || MediaQuery.disableAnimationsOf(context);
    final scenery = ExcludeSemantics(
      child: SizedBox(
        height: 190,
        width: 310,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduce ? 1 : 0, end: 1),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 12),
              child: child,
            ),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                right: 24,
                top: 12,
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: theme.colorScheme.tertiaryContainer,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.all(
                      Radius.elliptical(150, 50),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                bottom: 4,
                width: 110,
                height: 136,
                child: PlantArt(stage: GrowthStage.sprout, species: 'Fern'),
              ),
              const Positioned(
                left: 80,
                bottom: 0,
                width: 140,
                height: 185,
                child: PlantArt(stage: GrowthStage.budding, species: 'Cosmos'),
              ),
              const Positioned(
                right: 0,
                bottom: 4,
                width: 110,
                height: 155,
                child: PlantArt(stage: GrowthStage.sapling, species: 'Fern'),
              ),
            ],
          ),
        ),
      ),
    );
    final welcome = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading,
        const SizedBox(height: 8),
        const Text(
          'Your plants keep their growth. Rest days and returning both belong here.',
        ),
      ],
    );
    final art = compact
        ? SizedBox(width: 160, height: 88, child: FittedBox(child: scenery))
        : scenery;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: EdgeInsets.all(compact ? 12 : 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 620) {
            return Row(
              children: [
                Expanded(child: welcome),
                const SizedBox(width: 24),
                art,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) ...[
                Center(child: art),
                const SizedBox(height: 12),
                welcome,
              ] else
                Row(
                  children: [
                    Expanded(child: welcome),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      height: 80,
                      child: FittedBox(child: scenery),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
