import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/recipe_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edited recipe can re-practice celebration and save its draft', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    RecipeDraft? saved;
    const habit = Habit(
      id: 'synthetic-recipe',
      aspiration: 'Calm',
      anchor: 'pour my morning drink',
      behavior: 'take one slow breath',
      celebration: 'smile',
      species: 'Cosmos',
      stage: GrowthStage.seed,
      status: 'active',
      practiceCount: 0,
      recentPractice: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<RecipeDraft>(
                  context: context,
                  builder: (_) => const RecipeBuilder(habit: habit),
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'I will...'),
      'take one easy breath',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.ensureVisible(find.text('I practiced my celebration'));
    await tester.tap(find.text('I practiced my celebration'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save recipe'),
          )
          .enabled,
      isTrue,
    );
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(saved?.behavior, 'take one easy breath');
    expect(saved?.celebrationPracticed, isTrue);
    expect(find.text('Adjust your recipe'), findsNothing);
  });
}
