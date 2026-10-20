import 'package:budlark/core/models.dart';
import 'package:budlark/features/garden/recipe_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final customize in [false, true]) {
    testWidgets(
      'P14 ${customize ? "three taps" : "one tap"} plants without typing under ten wallclock seconds',
      (tester) async {
        RecipeDraft? saved;
        var interactions = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final draft = await showDialog<RecipeDraft>(
                      context: context,
                      builder: (_) => const RecipeBuilder(),
                    );
                    if (draft == null || !context.mounted) return;
                    saved = draft;
                    await showDialog<void>(
                      context: context,
                      builder: (_) => PlantedRecipeDialog(
                        habit: Habit(
                          id: 'synthetic-quick-plant',
                          aspiration: draft.aspiration,
                          anchor: draft.anchor,
                          behavior: draft.behavior,
                          celebration: draft.celebration,
                          species: draft.species,
                          stage: GrowthStage.seed,
                          status: 'active',
                          practiceCount: 0,
                          recentPractice: 0,
                        ),
                      ),
                    );
                  },
                  child: const Text('Create'),
                ),
              ),
            ),
          ),
        );
        final elapsed = Stopwatch()..start();
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        expect(find.text('Plant a habit'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.header == true,
          ),
          findsOneWidget,
        );
        expect(find.text('After I'), findsOneWidget);
        expect(find.text('I will'), findsOneWidget);
        expect(find.text('coffee'), findsOneWidget);
        expect(find.text('take one breath'), findsOneWidget);
        expect(
          tester.widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, 'coffee'),
          ).selected,
          isTrue,
        );
        expect(
          tester.widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, 'take one breath'),
          ).selected,
          isTrue,
        );
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.byType(ExpansionTile), findsOneWidget);
        expect(find.text('More'), findsOneWidget);
        final body = tester.widget<AlertDialog>(find.byType(AlertDialog)).content!;
        final bodyText = find.descendant(
          of: find.byWidget(body),
          matching: find.byType(Text),
        );
        final words = tester.widgetList<Text>(bodyText).expand(
          (text) => (text.data ?? '').split(RegExp(r'\s+')),
        ).where((word) => word.isNotEmpty);
        expect(words.length, inInclusiveRange(10, 14));
        if (customize) {
          await tester.tap(find.text('tea'));
          interactions++;
          await tester.pumpAndSettle();
          await tester.tap(find.text('stretch'));
          interactions++;
          await tester.pumpAndSettle();
        }
        final plant = find.widgetWithText(FilledButton, 'Plant a Seed');
        expect(plant.hitTestable(), findsOneWidget);
        await tester.tap(plant);
        interactions++;
        await tester.pumpAndSettle();
        expect(interactions, lessThanOrEqualTo(3));
        expect(saved?.anchor, customize ? 'drink tea' : 'drink coffee');
        expect(saved?.behavior, customize ? 'stretch once' : 'take one breath');
        expect(saved?.celebration, 'smile');
        expect(saved?.aspiration, 'Calm');
        expect(saved?.species, 'Cosmos');
        expect(saved?.celebrationPracticed, isFalse);
        expect(find.text('Your seed is planted'), findsOneWidget);
        await tester.tap(find.text('See my garden'));
        await tester.pumpAndSettle();
        elapsed.stop();
        expect(find.byType(PlantedRecipeDialog), findsNothing);
        expect(elapsed.elapsed, lessThan(const Duration(seconds: 10)),
            reason: 'Measure actual widget-flow wallclock time, not pump time.');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
