import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeUpdates extends UpdateService {
  FakeUpdates(this.result, {this.failure});
  final UpdateInfo? result;
  final Object? failure;
  int checks = 0;

  @override
  Future<UpdateInfo?> check({
    String currentVersion = UpdateService.bundledVersion,
  }) async {
    checks++;
    if (failure != null) throw failure!;
    return result;
  }
}

Future<void> settleDatabase(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }
}

Future<(GardenStore, Habit)> fixture(WidgetTester tester) async {
  final store = (await tester.runAsync(
    () => GardenStore.open(':memory:', 'ui-learning'),
  ))!;
  final h = (await tester.runAsync(
    () => store.plant(
      aspiration: 'Calm',
      anchor: 'coffee',
      behavior: 'breathe',
      celebration: 'smile',
      species: 'Fern',
    ),
  ))!;
  addTearDown(() => tester.runAsync(store.close));
  await tester.binding.setSurfaceSize(const Size(1100, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  return (store, h);
}

void main() {
  testWidgets(
    'Settings mounts a fresh reminder observation choice and revokes it with product-event consent',
    (tester) async {
      final (store, _) = await fixture(tester);
      await tester.runAsync(() => store.setSetting('analytics', 'true'));
      await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
      await settleDatabase(tester);
      await tester.tap(find.byTooltip('Settings and privacy'));
      await settleDatabase(tester);
      final choice = find.widgetWithText(
        CheckboxListTile,
        'Observe my app reminder preference (optional)',
      );
      expect(tester.widget<CheckboxListTile>(choice).value, isFalse);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await settleDatabase(tester);
      expect(tester.widget<CheckboxListTile>(choice).value, isTrue);
      expect(await tester.runAsync(store.reminderObservationOptedIn), isTrue);
      final analytics = find.widgetWithText(
        SwitchListTile,
        'Share product event counts',
      );
      await tester.ensureVisible(analytics);
      await tester.tap(analytics);
      await settleDatabase(tester);
      expect(tester.widget<CheckboxListTile>(choice).value, isFalse);
      expect(tester.widget<CheckboxListTile>(choice).onChanged, isNull);
      expect(await tester.runAsync(store.reminderObservationOptedIn), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('foreground return celebrates once and resets absence state', (
    tester,
  ) async {
    final (store, _) = await fixture(tester);
    final old = DateTime.now().toUtc().subtract(const Duration(days: 4));
    await tester.runAsync(() async {
      await store.recordInteraction(now: old);
      await store.setSetting('reconnectCount', '2');
    });
    await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
    await settleDatabase(tester);
    expect(
      find.text('Returning is a win; your garden kept its growth'),
      findsOneWidget,
    );
    expect(await tester.runAsync(() => store.setting('reconnectCount')), '0');
    expect(await tester.runAsync(() => store.setting('ratingComebacks')), '1');
    final opened = await tester.runAsync(
      () => store.setting('lastInteraction'),
    );
    expect(DateTime.parse(opened!).isAfter(old), isTrue);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Did it'));
    await tester.tap(find.text('Did it'));
    await settleDatabase(tester);
    expect(
      find.text('Returning is a win; your garden kept its growth'),
      findsNothing,
    );
    expect(await tester.runAsync(() => store.setting('ratingComebacks')), '1');
  });

  testWidgets(
    'first opening records activity, but reload never records return',
    (tester) async {
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'first-open'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
      await settleDatabase(tester);
      expect(
        await tester.runAsync(() => store.setting('lastInteraction')),
        isNotNull,
      );
      expect(
        find.text('Returning is a win; your garden kept its growth'),
        findsNothing,
      );
      // Force stale absence state after the first opening, then trigger _load
      // through a preference action. Background refresh must not reset it.
      final old = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 4))
          .toIso8601String();
      await tester.runAsync(() async {
        await store.setSetting('lastInteraction', old);
        await store.setSetting('reconnectCount', '2');
      });
      await tester.tap(find.byTooltip('Settings and privacy'));
      await settleDatabase(tester);
      await tester.tap(find.text('Reduced motion'));
      await settleDatabase(tester);
      expect(
        await tester.runAsync(() => store.setting('lastInteraction')),
        old,
      );
      expect(await tester.runAsync(() => store.setting('reconnectCount')), '2');
      expect(
        find.text('Returning is a win; your garden kept its growth'),
        findsNothing,
      );
    },
  );

  for (final scenario in ['none', 'preview', 'error']) {
    testWidgets(
      'manual update check shows $scenario without launching installers',
      (tester) async {
        final (store, _) = await fixture(tester);
        final updates = FakeUpdates(
          scenario == 'preview'
              ? UpdateInfo(
                  '0.2.0-preview',
                  Uri.parse(
                    'https://github.com/Sampath-K/bloomstep/releases/tag/v0.2.0-preview',
                  ),
                  true,
                )
              : null,
          failure: scenario == 'error'
              ? StateError('Release service unavailable')
              : null,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: GardenScreen(store: store, updateService: updates),
          ),
        );
        await settleDatabase(tester);
        expect(updates.checks, 0);
        await tester.tap(find.byTooltip('Settings and privacy'));
        await settleDatabase(tester);
        await tester.ensureVisible(find.text('Check for updates'));
        await tester.tap(find.text('Check for updates'));
        await tester.pumpAndSettle();
        expect(updates.checks, 1);
        expect(
          find.textContaining(UpdateService.bundledVersion),
          findsOneWidget,
        );
        if (scenario == 'none') {
          expect(find.text('No newer published release found'), findsOneWidget);
          expect(find.text('Open release page'), findsNothing);
        } else if (scenario == 'error') {
          expect(
            find.textContaining('Release service unavailable'),
            findsOneWidget,
          );
          expect(find.text('Open release page'), findsNothing);
        } else {
          expect(find.textContaining('Unsigned preview'), findsOneWidget);
          expect(find.text('Open release page'), findsOneWidget);
        }
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(find.text('Open release page'), findsNothing);
      },
    );
  }

  for (final scenario in [
    (const Size(1280, 720), 1.0),
    (const Size(360, 640), 2.0),
  ]) {
    testWidgets(
      'plant never obscures check-ins at ${scenario.$1}, text ${scenario.$2}',
      (tester) async {
        final (store, _) = await fixture(tester);
        await tester.runAsync(() async {
          for (var i = 0; i < 2; i++) {
            await store.plant(
              aspiration: 'Focus $i',
              anchor: 'tea',
              behavior: 'write a word',
              celebration: 'smile',
              species: 'Fern',
            );
          }
        });
        await tester.binding.setSurfaceSize(scenario.$1);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scenario.$2)),
              child: child!,
            ),
            home: GardenScreen(store: store),
          ),
        );
        await settleDatabase(tester);
        expect(find.byType(FloatingActionButton), findsNothing);
        final plant = find.text('Plant a habit');
        expect(plant, findsOneWidget);
        for (final aspiration in ['Calm', 'Focus 0', 'Focus 1']) {
          final action = find.descendant(
            of: find.widgetWithText(Card, aspiration),
            matching: find.text('Not today'),
          );
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(action).overlaps(tester.getRect(plant)),
            isFalse,
          );
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(find.text('Rest days belong in a garden.'), findsOneWidget);
          await tester.ensureVisible(find.text('No reason needed'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('No reason needed'));
          await settleDatabase(tester);
        }
        expect(tester.takeException(), isNull);
        expect(
          (await tester.runAsync(store.habits))!
              .every((h) => h.today == CheckInResult.notToday),
          isTrue,
        );
      },
    );
  }

  testWidgets('weekly loop works during naturalness cooldown without sliders', (
    tester,
  ) async {
    final (store, h) = await fixture(tester);
    await tester.runAsync(() => store.reflect(h.id, [6, 6, 6, 6]));
    await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
    await settleDatabase(tester);
    expect(find.textContaining('Naturalness available'), findsOneWidget);
    await tester.ensureVisible(find.text('Weekly reflection / Recipe Doctor'));
    await tester.tap(find.text('Weekly reflection / Recipe Doctor'));
    await settleDatabase(tester);
    expect(find.text('A minute for your recipe'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.text('Keep my recipe'));
    await settleDatabase(tester);
    expect(
      await tester.runAsync(() => store.setting('weeklyGardenStorySeenWeek')),
      isNotNull,
    );
    expect(find.textContaining('cooldown'), findsNothing);
    expect((await tester.runAsync(store.export))!['reflections'], hasLength(1));
  });

  testWidgets('rating invitation waits for celebration and snooze persists', (
    tester,
  ) async {
    final (store, h) = await fixture(tester);
    await tester.runAsync(() async {
      final now = DateTime.now();
      for (var i = 30; i > 0; i--) {
        await store.checkIn(
          h.id,
          CheckInResult.did,
          now: now.subtract(Duration(days: i)),
        );
      }
    });
    await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
    await settleDatabase(tester);
    expect(find.text('Rate Bloomstep'), findsNothing);
    await tester.ensureVisible(find.text('Did it'));
    await tester.tap(find.text('Did it'));
    await settleDatabase(tester);
    expect(find.textContaining('That tiny step counts!'), findsOneWidget);
    expect(find.text('Rate Bloomstep'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await settleDatabase(tester);
    expect(find.text('Rate Bloomstep'), findsOneWidget);
    await tester.tap(find.text('Snooze 120 days'));
    await settleDatabase(tester);
    expect(find.text('Rate Bloomstep'), findsNothing);
    await tester.ensureVisible(find.text('Did more'));
    await tester.tap(find.text('Did more'));
    await settleDatabase(tester);
    await tester.pump(const Duration(seconds: 6));
    await settleDatabase(tester);
    expect(find.text('Rate Bloomstep'), findsNothing);
    await tester.tap(find.byTooltip('Help us grow'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rating').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save feedback'));
    await settleDatabase(tester);
    expect((await tester.runAsync(store.voice))!.single['rating'], 5);
    expect((await tester.runAsync(store.voice))!.single['body'], '');
  });
}
