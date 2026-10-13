import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/features/garden/recipe_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'first_habit_invitation_test.dart' show ready;

const savedHabit = Habit(
  id: 'synthetic-saved-seed',
  aspiration: 'Calm',
  anchor: 'put my cup away',
  behavior: 'stretch one finger',
  celebration: 'whisper well done',
  species: 'Cosmos',
  stage: GrowthStage.seed,
  status: 'active',
  practiceCount: 0,
  recentPractice: 0,
);

void main() {
  testWidgets(
    'saved confirmation grows seed to sprout and never blocks continuation',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PlantedRecipeDialog(habit: savedHabit)),
        ),
      );
      expect(find.text('Your seed is planted'), findsOneWidget);
      expect(
        tester.getRect(find.byType(SeedGrowthPreview)).top,
        greaterThanOrEqualTo(
          tester.getRect(find.text('Your seed is planted')).bottom,
        ),
        reason: 'The scaled final plant must not paint over the dialog title.',
      );
      expect(find.byKey(const ValueKey('growth-seed')), findsOneWidget);
      final start = tester
          .widget<Opacity>(find.byKey(const ValueKey('growth-sprout-opacity')))
          .opacity;
      expect(start, 0);
      expect(find.textContaining('put my cup away'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'See my seed'),
            )
            .enabled,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 700));
      final middle = tester
          .widget<Opacity>(find.byKey(const ValueKey('growth-sprout-opacity')))
          .opacity;
      expect(middle, greaterThan(start));
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('growth-sprout-opacity')),
            )
            .opacity,
        1,
      );
      expect(savedHabit.stage, GrowthStage.seed);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final platformReduced in [false, true]) {
    testWidgets('reduced motion is static and announced ($platformReduced)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: platformReduced),
            child: Scaffold(
              body: PlantedRecipeDialog(
                habit: savedHabit,
                reducedMotion: !platformReduced,
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('growth-static-sprout')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('growth-seed')), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Seed planted.*practice')),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final failSave in [false, true]) {
    testWidgets(
      'custom values show growth only after successful persistence ($failSave)',
      (tester) async {
        final store = (await tester.runAsync(
          () => GardenStore.open(':memory:', 'synthetic-save'),
        ))!;
        addTearDown(() => tester.runAsync(store.close));
        await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
        await ready(tester, find.text('A little is enough.'));
        await tester.tap(find.text('Plant a habit'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('custom-anchor')),
          'put my cup away',
        );
        await tester.pump();
        await tester.tap(find.text('Choose a tiny action'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('custom-action')),
          'stretch one finger',
        );
        await tester.pump();
        await tester.tap(find.text('Choose a celebration'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('custom-celebration')),
          'whisper well done',
        );
        await tester.pump();
        expect(find.byType(PlantedRecipeDialog), findsNothing);
        if (failSave) {
          await tester.runAsync(store.close);
        }
        await tester.tap(find.text('Plant this seed'));
        if (failSave) {
          await ready(tester, find.textContaining('database_closed'));
          expect(find.byType(PlantedRecipeDialog), findsNothing);
        } else {
          await ready(tester, find.byType(PlantedRecipeDialog));
          final persisted = (await tester.runAsync(store.habits))!.single;
          final confirmation = tester.widget<PlantedRecipeDialog>(
            find.byType(PlantedRecipeDialog),
          );
          expect(confirmation.habit.id, persisted.id);
          expect(persisted.anchor, savedHabit.anchor);
          expect(persisted.behavior, savedHabit.behavior);
          expect(persisted.celebration, savedHabit.celebration);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
