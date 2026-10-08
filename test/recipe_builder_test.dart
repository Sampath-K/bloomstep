import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/recipe_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/bloomstep_windows_e2e_test.dart' as journey;

void main() {
  Future<void> openBuilder(
    WidgetTester tester, {
    void Function(RecipeDraft?)? onSaved,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final draft = await showDialog<RecipeDraft>(
                  context: context,
                  builder: (_) => const RecipeBuilder(),
                );
                onSaved?.call(draft);
              },
              child: const Text('Create'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'three picks plant a complete recipe without typing or practice',
    (tester) async {
      RecipeDraft? saved;
      await openBuilder(tester, onSaved: (draft) => saved = draft);
      expect(
        find.text('Step 1 of 3 · Start with something familiar'),
        findsOneWidget,
      );
      expect(find.text('Choose an anchor to continue.'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'After I...'), findsOneWidget);
      await tester.ensureVisible(find.text('pour my morning drink'));
      await tester.tap(find.text('pour my morning drink'));
      await tester.pumpAndSettle();
      expect(
        find.text('Step 2 of 3 · Make it wonderfully small'),
        findsOneWidget,
      );
      expect(
        find.textContaining('After I pour my morning drink'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('take one slow breath'));
      await tester.tap(find.text('take one slow breath'));
      await tester.pumpAndSettle();
      expect(find.text('Step 3 of 3 · Almost there'), findsOneWidget);
      await tester.ensureVisible(find.text('relax my shoulders and smile'));
      await tester.tap(find.text('relax my shoulders and smile'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Then I celebrate: relax my shoulders and smile'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Plant this seed'),
            )
            .enabled,
        isTrue,
      );
      await tester.tap(find.text('Plant this seed'));
      await tester.pumpAndSettle();
      expect(saved?.anchor, starterRecipes.first.anchor);
      expect(saved?.behavior, starterRecipes.first.behavior);
      expect(saved?.celebration, starterRecipes.first.celebration);
      expect(saved?.templateCategory, 'calm');
      expect(saved?.celebrationPracticed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom values are visible on every step and survive Back and keyboard navigation',
    (tester) async {
      RecipeDraft? saved;
      await openBuilder(tester, onSaved: (draft) => saved = draft);
      final anchor = find.byKey(const ValueKey('custom-anchor'));
      expect(anchor, findsOneWidget);
      await tester.enterText(anchor, '  put my cup away  ');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('custom-action'));
      expect(action, findsOneWidget);
      await tester.enterText(action, '  stretch one finger  ');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      final celebration = find.byKey(const ValueKey('custom-celebration'));
      await tester.enterText(celebration, '  whisper well done  ');
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(action).controller!.text,
        '  stretch one finger  ',
      );
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(anchor).controller!.text,
        '  put my cup away  ',
      );
      await tester.enterText(anchor, '   ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Choose a tiny action'),
            )
            .enabled,
        isFalse,
      );
      await tester.enterText(anchor, '  put my cup away  ');
      await tester.pump();
      await tester.tap(find.text('Choose a tiny action'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a celebration'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(celebration).controller!.text,
        '  whisper well done  ',
      );
      await tester.tap(find.text('Plant this seed'));
      await tester.pumpAndSettle();
      expect(saved?.anchor, 'put my cup away');
      expect(saved?.behavior, 'stretch one finger');
      expect(saved?.celebration, 'whisper well done');
      expect(saved?.templateCategory, isNull);
    },
  );

  testWidgets(
    'Back retains choices and an incomplete recipe explains its disabled action',
    (tester) async {
      await openBuilder(tester, textScale: 1.5);
      await tester.ensureVisible(find.text('open my laptop'));
      await tester.tap(find.text('open my laptop'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('write my one next step'));
      await tester.tap(find.text('write my one next step'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a celebration to plant your seed.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Plant this seed'),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('I will write my one next step'),
        findsOneWidget,
      );
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.textContaining('After I open my laptop'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('picker reflows on a compact window with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openBuilder(tester, textScale: 1.5);
    await tester.ensureVisible(find.text('sit down with a book'));
    await tester.tap(find.text('sit down with a book'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('read one sentence'));
    await tester.tap(find.text('read one sentence'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('say "I learned something"'));
    await tester.tap(find.text('say "I learned something"'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'planting shows a personal next step with one clear continuation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlantedRecipeDialog(
              habit: const Habit(
                id: 'synthetic-saved-seed',
                aspiration: 'Calm',
                anchor: 'pour my morning drink',
                behavior: 'take one slow breath',
                celebration: 'relax my shoulders and smile',
                species: 'Cosmos',
                stage: GrowthStage.seed,
                status: 'active',
                practiceCount: 0,
                recentPractice: 0,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Your seed is planted'), findsOneWidget);
      expect(
        find.text(
          'Your next step:\nAfter I pour my morning drink, I will take one slow breath. Then I celebrate: relax my shoulders and smile.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'See my seed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
