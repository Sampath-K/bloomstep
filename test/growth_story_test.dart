import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'first_habit_invitation_test.dart' show ready;

Future<(GardenStore, Habit)> fixture(
  WidgetTester tester, {
  bool closeOnTearDown = true,
}) async {
  final store = (await tester.runAsync(
    () => GardenStore.open(':memory:', 'growth-story-ui'),
  ))!;
  final habit = (await tester.runAsync(
    () => store.plant(
      aspiration: 'Calm',
      anchor: 'finish breakfast',
      behavior: 'take one breath',
      celebration: 'smile',
      species: 'Cosmos',
    ),
  ))!;
  if (closeOnTearDown) addTearDown(() => tester.runAsync(store.close));
  await tester.binding.setSurfaceSize(const Size(1100, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  return (store, habit);
}

void main() {
  testWidgets(
    'weekly recap shows local growth and saves only local seen state',
    (tester) async {
      final (store, habit) = await fixture(tester);
      await tester.runAsync(
        () => store.checkIn(habit.id, CheckInResult.did, now: DateTime.now()),
      );
      final eventsBefore = await tester.runAsync(store.eventCount);
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(store: store, testDisableServices: true),
        ),
      );
      await ready(tester, find.text('A little is enough.'));
      await tester.ensureVisible(
        find.text('Weekly reflection / Recipe Doctor'),
      );
      await tester.tap(find.text('Weekly reflection / Recipe Doctor'));
      await ready(tester, find.text('A minute for your recipe'));

      final story = (await tester.runAsync(store.weeklyGardenStory))!;
      expect(
        find.text('Local week: ${story.weekStart} through ${story.through}'),
        findsOneWidget,
      );
      expect(find.textContaining('evergreen Grove.'), findsOneWidget);
      expect(
        find.textContaining('An optional next step for Calm'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Recipe Doctor is a deterministic suggestion'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Keep my recipe'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('A minute for your recipe'), findsNothing);
      expect(
        await tester.runAsync(() => store.setting('weeklyGardenStorySeenWeek')),
        story.weekStart,
      );
      expect(await tester.runAsync(store.eventCount), eventsBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed recap completion is shown instead of reported successful',
    (tester) async {
      final (store, _) = await fixture(tester, closeOnTearDown: false);
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(store: store, testDisableServices: true),
        ),
      );
      await ready(tester, find.text('A little is enough.'));
      await tester.ensureVisible(
        find.text('Weekly reflection / Recipe Doctor'),
      );
      await tester.tap(find.text('Weekly reflection / Recipe Doctor'));
      await ready(tester, find.text('A minute for your recipe'));
      await tester.runAsync(store.close);

      await tester.tap(find.text('Keep my recipe'));
      await ready(tester, find.textContaining('could not be saved'));
      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
