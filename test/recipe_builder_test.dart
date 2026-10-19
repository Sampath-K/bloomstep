import 'package:budlark/core/models.dart';
import 'package:budlark/core/garden_store.dart';
import 'package:budlark/features/garden/recipe_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/budlark_windows_e2e_test.dart' as journey;

const editingHabit = Habit(
  id: 'synthetic-recipe',
  aspiration: 'Connection',
  anchor: 'finish lunch',
  behavior: 'send one kind sentence',
  celebration: 'put my hand on my heart',
  species: 'Fern',
  stage: GrowthStage.seed,
  status: 'active',
  practiceCount: 0,
  recentPractice: 0,
);

Future<void> openBuilder(
  WidgetTester tester, {
  Habit? habit,
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
                builder: (_) => RecipeBuilder(habit: habit),
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

Future<void> more(WidgetTester tester) async {
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Windows Ctrl+V works in every disclosed custom field', (tester) async {
    var clipboard = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        if (call.method == 'Clipboard.hasStrings') return {'value': true};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, null,
      ),
    );
    await openBuilder(tester);
    await more(tester);
    for (final key in ['custom-anchor', 'custom-action', 'custom-celebration']) {
      final field = find.byKey(ValueKey(key));
      clipboard = 'Pasted $key';
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field).controller!.text, clipboard);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('More retains comprehensive custom fields, plant and optional practice',
      (tester) async {
    RecipeDraft? saved;
    await openBuilder(tester, onSaved: (draft) => saved = draft);
    await more(tester);
    for (final field in [
      ('custom-aspiration', '  More quiet  '),
      ('custom-anchor', '  put my cup away  '),
      ('custom-action', '  stretch one finger  '),
      ('custom-celebration', '  whisper well done  '),
    ]) {
      final finder = find.byKey(ValueKey(field.$1));
      await tester.ensureVisible(finder);
      await tester.enterText(finder, field.$2);
    }
    final species = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(species);
    await tester.tap(species);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fern').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I practiced my celebration'));
    await tester.tap(find.text('I practiced my celebration'));
    await tester.pumpAndSettle();
    final celebration = find.byKey(const ValueKey('custom-celebration'));
    await tester.ensureVisible(celebration);
    await tester.enterText(celebration, '  a quiet hooray  ');
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
    await tester.ensureVisible(find.text('I practiced my celebration'));
    await tester.tap(find.text('I practiced my celebration'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('More'));
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Plant a Seed'));
    await tester.pumpAndSettle();
    expect(saved?.aspiration, 'More quiet');
    expect(saved?.anchor, 'put my cup away');
    expect(saved?.behavior, 'stretch one finger');
    expect(saved?.celebration, 'a quiet hooray');
    expect(saved?.species, 'Fern');
    expect(saved?.celebrationPracticed, isTrue);
    expect(saved?.templateCategory, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final recipe in starterRecipes) {
    testWidgets('More preserves ${recipe.aspiration} starter and attribution',
        (tester) async {
      RecipeDraft? saved;
      await openBuilder(tester, onSaved: (draft) => saved = draft);
      await more(tester);
      final choice = find.byKey(ValueKey('starter-${recipe.aspiration}'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plant a Seed'));
      await tester.pumpAndSettle();
      expect(saved?.aspiration, recipe.aspiration);
      expect(saved?.anchor, recipe.anchor);
      expect(saved?.behavior, recipe.behavior);
      expect(saved?.celebration, recipe.celebration);
      expect(saved?.templateCategory, recipe.aspiration.toLowerCase());
      expect(saved?.celebrationPracticed, isFalse);
    });
  }

  testWidgets('quick chips change only their own fields, not advanced choices',
      (tester) async {
    RecipeDraft? saved;
    await openBuilder(tester, onSaved: (draft) => saved = draft);
    await more(tester);
    for (final field in [
      ('custom-aspiration', 'Connection'),
      ('custom-celebration', 'a quiet hooray'),
    ]) {
      final finder = find.byKey(ValueKey(field.$1));
      await tester.ensureVisible(finder);
      await tester.enterText(finder, field.$2);
    }
    await tester.ensureVisible(find.text('More'));
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tea'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('stretch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plant a Seed'));
    await tester.pumpAndSettle();
    expect(saved?.anchor, 'drink tea');
    expect(saved?.behavior, 'stretch once');
    expect(saved?.aspiration, 'Connection');
    expect(saved?.celebration, 'a quiet hooray');
    expect(saved?.celebrationPracticed, isFalse);
  });

  for (final edit in [false, true]) {
    testWidgets('blank and overlong fields block ${edit ? "editing" : "planting"}',
        (tester) async {
      RecipeDraft? saved;
      await openBuilder(tester, habit: edit ? editingHabit : null,
          onSaved: (draft) => saved = draft);
      if (!edit) await more(tester);
      for (final key in [
        'custom-aspiration', 'custom-anchor', 'custom-action', 'custom-celebration',
      ]) {
        final field = find.byKey(ValueKey(key));
        final original = tester.widget<TextFormField>(field).controller!.text;
        for (final invalid in ['   ', List.filled(201, 'x').join()]) {
          await tester.ensureVisible(field);
          // Controller assignment also covers imported/programmatic overlength
          // values that the input formatter normally prevents typing.
          final input = tester.widget<TextFormField>(field);
          input.controller!.text = invalid;
          input.onChanged!(invalid);
          await tester.pump();
          expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isFalse);
          expect(find.textContaining('up to 200 characters each'), findsOneWidget);
          expect(saved, isNull);
        }
        final input = tester.widget<TextFormField>(field);
        input.controller!.text = original;
        input.onChanged!(original);
        await tester.pump();
      }
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isTrue);
    });
  }

  for (final variant in [
    (name: 'desktop', size: const Size(1200, 920), scale: 1.0),
    (name: 'compact', size: const Size(420, 820), scale: 1.0),
    (name: 'large text', size: const Size(420, 820), scale: 2.0),
    (name: 'short', size: const Size(800, 480), scale: 1.0),
  ]) {
    testWidgets('quick action and disclosed labels fit ${variant.name}', (tester) async {
      await tester.binding.setSurfaceSize(variant.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openBuilder(tester, textScale: variant.scale);
      expect(find.text('Plant a Seed').hitTestable(), findsOneWidget);
      await more(tester);
      for (final input in [
        ('custom-anchor', 'After I...', 'put my cup away'),
        ('custom-action', 'I will...', 'stretch one finger'),
        ('custom-celebration', 'Then I celebrate by...', 'whisper well done'),
      ]) {
        final field = find.byKey(ValueKey(input.$1));
        await tester.ensureVisible(field);
        await tester.enterText(field, input.$3);
        for (final duration in [
          Duration.zero, const Duration(milliseconds: 75), const Duration(milliseconds: 300),
        ]) {
          await tester.pump(duration);
          final label = find.descendant(of: field, matching: find.text(input.$2));
          final editor = find.descendant(of: field, matching: find.byType(EditableText));
          expect(tester.getRect(label).bottom, lessThanOrEqualTo(tester.getRect(editor).top));
          expect(tester.takeException(), isNull);
        }
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeBuilder), findsNothing);
    });
  }

  for (final change in [false, true]) {
    testWidgets('editing ${change ? "one field" : "unchanged"} never applies quick defaults',
        (tester) async {
      RecipeDraft? saved;
      await openBuilder(tester, habit: editingHabit, onSaved: (draft) => saved = draft);
      expect(find.text('Adjust your recipe'), findsOneWidget);
      expect(find.text('coffee'), findsNothing);
      if (change) {
        final field = find.byKey(const ValueKey('custom-action'));
        await tester.ensureVisible(field);
        await tester.enterText(field, 'send a smile');
        await tester.ensureVisible(find.text('I practiced my celebration'));
        await tester.tap(find.text('I practiced my celebration'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      expect(saved?.aspiration, editingHabit.aspiration);
      expect(saved?.anchor, editingHabit.anchor);
      expect(saved?.behavior, change ? 'send a smile' : editingHabit.behavior);
      expect(saved?.celebration, editingHabit.celebration);
      expect(saved?.species, editingHabit.species);
      expect(saved?.celebrationPracticed, change);
    });
  }

  testWidgets('planting shows a personal next step with one clear continuation', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PlantedRecipeDialog(habit: editingHabit)),
    ));
    expect(find.text('Your seed is planted'), findsOneWidget);
    expect(find.text(
      'After I finish lunch, I will send one kind sentence. Then I celebrate: put my hand on my heart.',
    ), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'See my garden'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('Try it when your moment comes. Practicing now is optional.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final systemReduced in [false, true]) {
    testWidgets('planted preview respects reduced motion ($systemReduced)', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: systemReduced),
          child: Scaffold(body: SeedGrowthPreview(
            species: 'Fern', reducedMotion: !systemReduced,
          )),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('growth-static-sprout')), findsOneWidget);
      expect(find.byKey(const ValueKey('growth-sprout-opacity')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Seed planted')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

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
      expect(end.isAfter(runStartedAt.toUtc().add(const Duration(minutes: 5))), isFalse);
      expect({
        for (var day = 1; day <= 31; day++)
          localDate(edited.add(Duration(days: day))),
      }, hasLength(31));
    }
  });

  test('same-day synthetic edit stays newer than monotonic undo', () async {
    var now = DateTime(2026, 10, 4, 12);
    final store = await GardenStore.open(':memory:', 'synthetic-owner', clock: () => now);
    addTearDown(store.close);
    final habit = await store.plant(
      aspiration: 'Calm', anchor: 'morning drink', behavior: 'relax my shoulders',
      celebration: 'smile', species: 'Cosmos',
    );
    await store.checkIn(habit.id, CheckInResult.didMore);
    await store.undo(habit.id);
    final uploaded = (await store.syncPayload())['habits'] as List;
    final undoUpdated = DateTime.parse((uploaded.single as Map)['updated'] as String);
    expect(undoUpdated.isAfter(now.toUtc()), isTrue);
    final day = localDate(now);
    now = now.add(const Duration(seconds: 1));
    await store.edit((await store.habits()).single,
      anchor: habit.anchor, behavior: 'take one easy breath', celebration: habit.celebration,
    );
    final edited = (await store.syncPayload())['habits'] as List;
    expect(DateTime.parse((edited.single as Map)['updated'] as String).isAfter(undoUpdated), isTrue);
    expect(localDate(now), day);
    await store.mergeSync({
      'habits': uploaded, 'checkins': [], 'reflections': [], 'voice': [],
    });
    expect((await store.habits()).single.behavior, 'take one easy breath');
    expect((await store.habits()).single.today, isNull);
    expect((await store.syncPayload())['habits'], hasLength(1));
  });
}
