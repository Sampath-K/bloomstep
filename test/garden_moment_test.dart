import 'package:budlark/core/models.dart';
import 'package:budlark/features/garden/garden_moment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved timing policy has exact finite boundaries', () {
    expect(GardenMoment.phaseAt(Duration.zero),
        GardenMomentPhase.growthAndLanding);
    expect(GardenMoment.phaseAt(const Duration(milliseconds: 299)),
        GardenMomentPhase.growthAndLanding);
    expect(GardenMoment.phaseAt(const Duration(milliseconds: 300)),
        GardenMomentPhase.song);
    expect(GardenMoment.phaseAt(const Duration(milliseconds: 799)),
        GardenMomentPhase.song);
    expect(GardenMoment.phaseAt(const Duration(milliseconds: 800)),
        GardenMomentPhase.settling);
    expect(GardenMoment.phaseAt(const Duration(milliseconds: 1000)),
        GardenMomentPhase.complete);
    expect(GardenMoment.phaseAt(Duration.zero, reducedMotion: true),
        GardenMomentPhase.complete);
  });
  for (final appReduced in [false, true]) {
    for (final osReduced in [false, true]) {
      testWidgets('finite moment, app=$appReduced OS=$osReduced', (tester) async {
        var finished = 0;
        Widget scene() => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: osReduced),
            child: SizedBox(
              width: 300,
              height: 200,
              child: GardenMoment(
                stage: GrowthStage.sprout,
                previousStage: GrowthStage.seed,
                species: 'Fern',
                reducedMotion: appReduced,
                completion: 'account/habit/day/revision',
                onFinished: () => finished++,
              ),
            ),
          ),
        );
        double progress() => (tester
            .widget<AnimatedBuilder>(find.descendant(
              of: find.byType(GardenMoment),
              matching: find.byType(AnimatedBuilder),
            ))
            .animation as Animation<double>).value;
        await tester.pumpWidget(scene());
        if (appReduced || osReduced) {
          expect(progress(), 1);
        } else {
          expect(progress(), 0);
          await tester.pump(const Duration(milliseconds: 300));
          expect(progress(), closeTo(.3, .01));
          await tester.pump(const Duration(milliseconds: 500));
          expect(progress(), closeTo(.8, .01));
          await tester.pump(const Duration(milliseconds: 200));
          expect(progress(), 1);
        }
        await tester.pump();
        expect(finished, 1);
        await tester.pumpWidget(scene());
        expect(progress(), 1, reason: 'A rebuild must not replay the moment.');
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
