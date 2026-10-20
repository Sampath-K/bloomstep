import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:budlark/core/garden_store.dart';
import 'package:budlark/core/models.dart';
import 'package:budlark/features/garden/garden_screen.dart';
import 'package:budlark/features/garden/garden_moment.dart';
import 'package:budlark/services/desktop_reminders.dart';
import 'package:budlark/services/remote_config.dart';
import 'package:budlark/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/garden_navigation.dart';

Future<void> settleGardenMore(WidgetTester tester) async {
  await settleDatabase(tester);
  await openGardenMore(tester);
}

class FakeUpdates extends UpdateService {
  FakeUpdates(this.result, {this.failure, this.pending});
  final UpdateInfo? result;
  final Object? failure;
  final Future<void>? pending;
  int checks = 0;

  @override
  Future<UpdateInfo?> check({
    String currentVersion = UpdateService.bundledVersion,
  }) async {
    checks++;
    await pending;
    if (failure != null) throw failure!;
    return result;
  }
}

class FakeWidgetReminderGateway implements ReminderGateway {
  Future<void> Function(String)? action;
  Object? initializeFailure;
  int initializations = 0;
  final requests = <ReminderRequest>[];
  final cancellations = <int>[];

  @override
  Future<void> initialize(Future<void> Function(String) action) async {
    initializations++;
    this.action = action;
    if (initializeFailure != null) throw initializeFailure!;
  }

  @override
  Future<void> show(ReminderRequest request) async => requests.add(request);

  @override
  Future<void> cancel(int id) async => cancellations.add(id);

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> showAndFocus() async {}

  @override
  Future<void> shutdown() async {}
}

Future<void> settleDatabase(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }
}

Future<(GardenStore, Habit)> fixture(
  WidgetTester tester, {
  DateTime Function()? clock,
}) async {
  final store = (await tester.runAsync(
    () => GardenStore.open(':memory:', 'ui-learning', clock: clock),
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
  // These cases exercise the existing advanced controls behind More.
  Future<void> settleDatabase(WidgetTester tester) =>
      settleGardenMore(tester);

  testWidgets(
    'feedback supports Ctrl+V into the focused text field on Windows',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': 'Pasted feedback'};
          }
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final (store, _) = await fixture(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(store: store, testDisableServices: true),
        ),
      );
      await settleDatabase(tester);
      await tester.tap(find.byTooltip('Help us grow'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Your feedback');
      await tester.tap(field);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Pasted feedback',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send feedback'));
      await settleDatabase(tester);
      expect(
        (await tester.runAsync(store.voice))!.single['body'],
        'Pasted feedback',
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Settings mounts a fresh reminder observation choice and revokes it with product-event consent',
    (tester) async {
      final (store, _) = await fixture(tester);
      await tester.runAsync(() => store.setSetting('analytics', 'true'));
      await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
      await settleDatabase(tester);
      await tester.tap(find.byTooltip('Settings and privacy'));
      await settleDatabase(tester);
      await tester.tap(find.text('Privacy & measurement'));
      await tester.pumpAndSettle();
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

  testWidgets(
    'failed reminder enable reports an actionable error in Settings without changing the saved choice',
    (tester) async {
      final (store, _) = await fixture(tester);
      await tester.runAsync(() => store.setSetting('reminders', 'false'));
      final gateway = FakeWidgetReminderGateway()
        ..initializeFailure = StateError('synthetic private platform detail');
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            reminderGateway: gateway,
            configLoader: (_) async =>
                const RemoteConfigResult(RemoteConfig.defaults),
          ),
        ),
      );
      await settleDatabase(tester);
      await tester.tap(find.byTooltip('Settings and privacy'));
      await settleDatabase(tester);
      await tester.tap(find.text('Reminders'));
      await tester.pumpAndSettle();
      final reminderSwitch = find.widgetWithText(
        SwitchListTile,
        'Gentle Windows reminders',
      );
      await tester.ensureVisible(reminderSwitch);
      await tester.tap(reminderSwitch);
      await settleDatabase(tester);
      await tester.tap(find.text('Details').last);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(
            'Windows reminders couldn’t be started. Check Windows Settings > System > Notifications, then try again.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('synthetic private platform detail'),
        findsNothing,
      );
      expect(tester.widget<SwitchListTile>(reminderSwitch).value, isFalse);
      expect(await tester.runAsync(() => store.setting('reminders')), 'false');
    },
  );

  testWidgets(
    'persisted default-on reminder choice stays visible after a startup capability failure',
    (tester) async {
      final (store, _) = await fixture(tester);
      await tester.runAsync(() => store.setSetting('reminders', 'true'));
      final gateway = FakeWidgetReminderGateway()
        ..initializeFailure = StateError('synthetic private platform detail');
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            reminderGateway: gateway,
            configLoader: (_) async =>
                const RemoteConfigResult(RemoteConfig.defaults),
          ),
        ),
      );
      await settleDatabase(tester);
      await tester.tap(find.byTooltip('Settings and privacy'));
      await settleDatabase(tester);
      await tester.tap(find.text('Reminders'));
      await tester.pumpAndSettle();
      final reminderSwitch = find.widgetWithText(
        SwitchListTile,
        'Gentle Windows reminders',
      );
      await tester.ensureVisible(reminderSwitch);
      await tester.tap(find.text('Details').last);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(reminderSwitch).value, isTrue);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(
            'Windows reminders couldn’t be started. Check Windows Settings > System > Notifications, then try again.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your reminder preference is on, but Windows delivery is not active.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('synthetic private platform detail'),
        findsNothing,
      );
      expect(await tester.runAsync(() => store.setting('reminders')), 'true');
      expect(gateway.initializations, 1);

      await tester.tap(find.text('Retry Windows reminders'));
      await settleDatabase(tester);
      expect(gateway.initializations, 2);
      expect(await tester.runAsync(() => store.setting('reminders')), 'true');
    },
  );

  testWidgets('testDisableServices keeps reminder controls unavailable', (
    tester,
  ) async {
    final (store, _) = await fixture(tester);
    final gateway = FakeWidgetReminderGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: GardenScreen(
          store: store,
          reminderGateway: gateway,
          testDisableServices: true,
        ),
      ),
    );
    await settleDatabase(tester);
    await tester.tap(find.byTooltip('Settings and privacy'));
    await settleDatabase(tester);

    expect(find.text('Gentle Windows reminders'), findsNothing);
    expect(gateway.action, isNull);
    expect(await tester.runAsync(() => store.setting('reminders')), isNull);
  });

  testWidgets('failed check-in neither celebrates nor withdraws its reminder', (
    tester,
  ) async {
    final path = File(
      'garden-checkin-failure-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    ).absolute.path;
    final store = (await tester.runAsync(
      () => GardenStore.open(path, 'checkin-failure'),
    ))!;
    addTearDown(() async {
      await tester.runAsync(store.close);
      await databaseFactoryFfi.deleteDatabase(path);
    });
    final h = (await tester.runAsync(
      () => store.plant(
        aspiration: 'Calm',
        anchor: 'coffee',
        behavior: 'breathe',
        celebration: 'smile',
        species: 'Fern',
      ),
    ))!;
    await tester.runAsync(() async {
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute(
        "CREATE TRIGGER reject_checkin BEFORE INSERT ON checkins "
        "BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END",
      );
      await store.setSetting('reminders', 'true');
      await store.setSetting('ignored:${h.id}', '4');
    });
    final gateway = FakeWidgetReminderGateway();
    await tester.binding.setSurfaceSize(const Size(1100, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: GardenScreen(
          store: store,
          reminderGateway: gateway,
          configLoader: (_) async =>
              const RemoteConfigResult(RemoteConfig.defaults),
        ),
      ),
    );
    await settleDatabase(tester);
    gateway.cancellations.clear();
    await tester.ensureVisible(find.text('Did it'));
    await tester.tap(find.text('Did it'));
    await settleDatabase(tester);

    expect(find.text('Something needs your attention.'), findsOneWidget);
    expect(find.textContaining('That tiny step counts!'), findsNothing);
    expect(await tester.runAsync(() => store.setting('ignored:${h.id}')), '4');
    expect(
      gateway.cancellations,
      isNot(contains(DesktopReminders.notificationId(store.account, h.id))),
    );
    expect((await tester.runAsync(store.habits))!.single.practiceCount, 0);
  });

  testWidgets(
    'notification positive check-in shows saved personal celebration in app',
    (tester) async {
      final (store, h) = await fixture(tester);
      await tester.runAsync(() async {
        await store.setSetting('reminders', 'true');
        await store.setSetting(
          'reminderLog',
          jsonEncode([
            {
              'habitId': h.id,
              'day': localDate(DateTime.now()),
              'notificationId': '12345678-1234-4234-8234-123456789abc',
              'handled': <String>[],
            },
          ]),
        );
      });
      final gateway = FakeWidgetReminderGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            reminderGateway: gateway,
            configLoader: (_) async =>
                const RemoteConfigResult(RemoteConfig.defaults),
          ),
        ),
      );
      await settleDatabase(tester);
      expect(gateway.action, isNotNull);

      await tester.runAsync(
        () => gateway.action!(
          jsonEncode({
            'account': store.account,
            'habitId': h.id,
            'day': localDate(DateTime.now()),
            'notificationId': '12345678-1234-4234-8234-123456789abc',
            'action': 'did',
          }),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        (await tester.runAsync(store.habits))!.single.today,
        CheckInResult.did,
        reason: 'the attributed notification callback must commit its check-in',
      );
      expect(find.text('Something needs your attention.'), findsNothing);
      expect(
        tester.widget<GardenMoment>(find.byType(GardenMoment)).completion,
        isNotNull,
      );
      expect(
        find.text('Now smile.'),
        findsOneWidget,
      );
      expect(gateway.requests, isEmpty, reason: 'acknowledgement stays in-app');
    },
  );

  testWidgets('graduation is presented as a milestone, not permanent proof', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'graduation-copy'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.binding.setSurfaceSize(const Size(1100, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final habit = (await tester.runAsync(
      () => store.plant(
        aspiration: 'Focus',
        anchor: 'coffee',
        behavior: 'write one word',
        celebration: 'smile',
        species: 'Fern',
      ),
    ))!;
    final now = DateTime.now();
    await tester.runAsync(() async {
      for (var day = 27; day >= 0; day--) {
        await store.checkIn(
          habit.id,
          CheckInResult.did,
          now: now.subtract(Duration(days: day)),
        );
      }
      await store.reflect(habit.id, [
        6,
        6,
        6,
        6,
      ], now: now.subtract(const Duration(days: 14)));
    });
    await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
    await settleDatabase(tester);
    await tester.tap(find.byTooltip('More for Focus'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Check naturalness'));
    await tester.tap(find.text('Check naturalness'));
    await settleDatabase(tester);
    for (var i = 0; i < 4; i++) {
      tester.widget<Slider>(find.byType(Slider).at(i)).onChanged!(6);
      await tester.pump();
    }
    await tester.tap(find.text('Save reflection'));
    await settleDatabase(tester);

    const milestone =
        'Your recent practice and reflections met the graduation criteria. '
        'This is a milestone; keep adapting your habit whenever it suits you.';
    expect(find.text(milestone), findsOneWidget);
    expect(
      find.text(
        'This one is part of you now. Welcome to your evergreen Grove!',
      ),
      findsNothing,
    );
    expect(find.textContaining('Graduation milestone · Focus'), findsOneWidget);
    expect(find.text('Evergreen Grove'), findsNothing);
    expect((await tester.runAsync(store.habits))!.single.status, 'graduated');
  });
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
      await tester.tap(find.text('App & support'));
      await tester.pumpAndSettle();
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

  for (final scenario in ['none', 'preview', 'error', 'checking']) {
    testWidgets(
      'manual update check shows $scenario without launching installers',
      (tester) async {
        final (store, _) = await fixture(tester);
        final pending = Completer<void>();
        final updates = FakeUpdates(
          scenario == 'preview'
              ? UpdateInfo(
                  '0.2.0-preview',
                  Uri.parse(
                    'https://github.com/Sampath-K/budlark/releases/tag/v0.2.0-preview',
                  ),
                  true,
                )
              : null,
          failure: scenario == 'error'
              ? StateError('Release service unavailable')
              : null,
          pending: scenario == 'checking' ? pending.future : null,
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
        await tester.tap(find.text('App & support'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Check for updates'));
        await tester.tap(find.text('Check for updates'));
        if (scenario == 'checking') {
          await tester.pump();
          expect(find.text('Checking GitHub Releases…'), findsOneWidget);
          pending.complete();
        }
        await tester.pumpAndSettle();
        expect(updates.checks, 1);
        expect(
          find.textContaining(UpdateService.bundledVersion),
          findsOneWidget,
        );
        if (scenario == 'none' || scenario == 'checking') {
          expect(find.text('No newer published release found'), findsOneWidget);
          expect(find.text('Open release page'), findsNothing);
        } else if (scenario == 'error') {
          expect(
            find.text('Couldn’t check for updates. Please try again.'),
            findsOneWidget,
          );
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
        // A layout check must stay on one synthetic day across CI midnight.
        final now = DateTime(2026, 10, 19, 12);
        DateTime clock() => now;
        final (store, _) = await fixture(tester, clock: clock);
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
            home: GardenScreen(store: store, clock: clock),
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
    await tester.tap(find.byTooltip('More for Calm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Naturalness available'), findsOneWidget);
    await tester.ensureVisible(find.text('Weekly reflection / Recipe Doctor'));
    await tester.tap(find.text('Weekly reflection / Recipe Doctor'));
    await settleDatabase(tester);
    expect(find.text('A minute for your recipe'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.text('Keep my recipe'));
    await settleDatabase(tester);
    expect(await tester.runAsync(() => store.setting('weeklyLast')), isNotNull);
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
    expect(find.text('Rate Budlark'), findsNothing);
    await tester.ensureVisible(find.text('Did it'));
    await tester.tap(find.text('Did it'));
    await settleDatabase(tester);
    expect((await tester.runAsync(store.habits))!.single.today, CheckInResult.did);
    await tester.pump(const Duration(seconds: 6));
    await settleDatabase(tester);
    expect(find.text('Rate Budlark'), findsOneWidget);
    await tester.tap(find.text('Snooze 120 days'));
    await settleDatabase(tester);
    expect(find.text('Rate Budlark'), findsNothing);
    await tester.ensureVisible(find.text('Did more'));
    await tester.tap(find.text('Did more'));
    await settleDatabase(tester);
    await tester.pump(const Duration(seconds: 6));
    await settleDatabase(tester);
    expect(find.text('Rate Budlark'), findsNothing);
    await tester.tap(find.byTooltip('Help us grow'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('5 of 5 stars'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send feedback'));
    await settleDatabase(tester);
    expect((await tester.runAsync(store.voice))!.single['rating'], 5);
    expect((await tester.runAsync(store.voice))!.single['body'], '');
  });
}
