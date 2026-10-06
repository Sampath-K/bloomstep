import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/recipe_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/bloomstep_windows_e2e_test.dart' as journey;

void main() {
  test('synthetic UTC window respects API future cap and distinct days', () {
    for (final runStartedAt in [
      DateTime.utc(2026, 10, 6),
      DateTime.utc(2026, 10, 6, 8),
      DateTime.utc(2026, 10, 6, 23, 59, 59),
      DateTime.parse('2026-10-06T00:00:00+05:30'),
    ]) {
      final start = journey.syntheticJourneyStart(runStartedAt);
      final edited = start.add(const Duration(seconds: 1));
      final end = edited.add(const Duration(days: 31));
      expect(start.isUtc, isTrue);
      expect(localDate(edited), localDate(start));
      expect(localDate(end), localDate(runStartedAt.toUtc()));
      expect(
        end.isAfter(runStartedAt.toUtc().add(const Duration(minutes: 5))),
        isFalse,
      );
      expect({
        for (var day = 1; day <= 31; day++)
          localDate(edited.add(Duration(days: day))),
      }, hasLength(31));
    }
  });

  test('same-day synthetic edit stays newer than monotonic undo', () async {
    var now = DateTime(2026, 10, 4, 12);
    final store = await GardenStore.open(
      ':memory:',
      'synthetic-owner',
      clock: () => now,
    );
    addTearDown(store.close);
    final habit = await store.plant(
      aspiration: 'Calm',
      anchor: 'morning drink',
      behavior: 'relax my shoulders',
      celebration: 'smile',
      species: 'Cosmos',
    );
    await store.checkIn(habit.id, CheckInResult.didMore);
    await store.undo(habit.id);
    final uploaded = (await store.syncPayload())['habits'] as List;
    final undoUpdated = DateTime.parse(
      (uploaded.single as Map)['updated'] as String,
    );
    expect(undoUpdated.isAfter(now.toUtc()), isTrue);
    final day = localDate(now);
    now = now.add(const Duration(seconds: 1));
    await store.edit(
      (await store.habits()).single,
      anchor: habit.anchor,
      behavior: 'take one easy breath',
      celebration: habit.celebration,
    );
    final edited = (await store.syncPayload())['habits'] as List;
    expect(
      DateTime.parse((edited.single as Map)['updated'] as String)
          .isAfter(undoUpdated),
      isTrue,
    );
    expect(localDate(now), day);
    await store.mergeSync({
      'habits': uploaded,
      'checkins': [],
      'reflections': [],
      'voice': [],
    });
    expect((await store.habits()).single.behavior, 'take one easy breath');
    expect((await store.habits()).single.today, isNull);
    expect((await store.syncPayload())['habits'], hasLength(1));
  });

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
