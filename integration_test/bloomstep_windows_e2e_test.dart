import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/services/sync_service.dart';

import 'support/local_test_api.dart';
import 'support/test_only_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'synthetic sign-in, real desktop UI, production sync handlers, isolation, export, restart and cleanup',
    (tester) async {
      final secret = Platform.environment['BLOOMSTEP_TEST_AUTH_SECRET'];
      expect(TestOnlyAuthGate.validTestSecret(secret), isTrue);
      final runRoot = await Directory.systemTemp.createTemp('bloomstep-it-');
      final today = DateTime.now();
      var testNow = DateTime(
        today.year,
        today.month,
        today.day,
        12,
      ).subtract(const Duration(days: 31));
      DateTime testClock() => testNow;
      final evidencePath = Platform.environment['BLOOMSTEP_TEST_EVIDENCE_PATH'];
      Map<String, Object?>? completedEvidence;
      if (evidencePath != null && await File(evidencePath).exists()) {
        throw StateError(
          'Refusing to overwrite a previous test evidence file.',
        );
      }
      LocalTestApi? api;
      SyntheticTestSession? activeSession;
      GardenStore? activeStore;
      var cleanupVerified = false;
      var apiProcessStopped = false;
      var profileClosed = false;
      addTearDown(() async {
        try {
          await api?.close();
          apiProcessStopped = api != null;
        } finally {
          try {
            await activeStore?.close();
          } finally {
            try {
              await activeSession?.signOut();
              profileClosed = true;
            } finally {
              try {
                await runRoot.delete(recursive: true);
                cleanupVerified = !await runRoot.exists();
              } finally {
                if (completedEvidence != null && evidencePath != null) {
                  completedEvidence['cleanupVerified'] = cleanupVerified;
                  completedEvidence['apiProcessStopped'] = apiProcessStopped;
                  completedEvidence['profileClosed'] = profileClosed;
                  completedEvidence['secretPersisted'] = false;
                  await File(evidencePath)
                      .writeAsString(jsonEncode(completedEvidence));
                }
                await tester.binding.setSurfaceSize(null);
              }
            }
          }
        }
      });
      final testApi = await LocalTestApi.start(
        runRoot: runRoot,
        secret: secret!,
      );
      api = testApi;
      await tester.binding.setSurfaceSize(const Size(1200, 1000));

      await tester.pumpWidget(
        TestOnlyBloomstepApp(
          runRoot: runRoot,
          expectedSecret: secret,
          clock: testClock,
          onAdvanceClock: () {
            testNow = testNow.add(const Duration(days: 1));
          },
          onAuthenticated: (session, store) {
            activeSession = session;
            activeStore = store;
          },
          onSessionClosed: (_, _) {
            activeSession = null;
            activeStore = null;
          },
        ),
      );
      await tester.pumpAndSettle();
      await _signIn(
        tester,
        username: 'synthetic-a',
        secret: 'wrong-key',
        expectFailure: true,
      );
      expect(await runRoot.list().toList(), hasLength(1));
      expect(
        await File(p.join(runRoot.path, 'synthetic-a.sqlite')).exists(),
        isFalse,
      );

      await _signIn(tester, username: 'synthetic-a', secret: secret);
      await _waitFor(tester, find.text('Plant a habit'));
      expect(activeSession?.account, hasLength(64));
      expect(activeStore, isNotNull);
      final firstAccount = activeStore!.account;
      expect(await activeStore!.setting('analytics'), isNull);
      expect(await activeStore!.reminderObservationOptedIn(), isFalse);
      expect(
        ((await activeStore!.syncPayload())['events'] as List).where((event) {
          final name = (event as Map)['name'].toString();
          return name.startsWith('signin_') ||
              name.startsWith('windows_reminder_preference_');
        }),
        isEmpty,
      );
      SyncService syncService() => SyncService(
        activeSession!,
        activeStore!,
        testApiOrigin: testApi.origin,
      );
      Future<Map<String, Object?>> readRemoteGarden(String filename) async {
        final readback = await GardenStore.open(
          p.join(runRoot.path, filename),
          activeStore!.account,
        );
        try {
          await SyncService(
            activeSession!,
            readback,
            testApiOrigin: testApi.origin,
          ).sync();
          expect((await readback.syncPayload()).values, everyElement(isEmpty));
          return await readback.export();
        } finally {
          await readback.close();
        }
      }

      expect(
        () => SyncService(
          activeSession!,
          activeStore!,
          testApiOrigin: Uri.parse('http://example.test'),
        ),
        throwsArgumentError,
      );

      await _plant(tester);
      await _waitFor(
        tester,
        find.text('Did it'),
        ready: () async => (await activeStore!.habits()).length == 1,
      );
      var recipes = await activeStore!.habits();
      final firstRecipe = recipes.single;
      expect(firstRecipe.behavior, contains('relax my shoulders'));
      await syncService().sync();
      expect((await activeStore!.habits()).single.id, firstRecipe.id);
      expect((await activeStore!.syncPayload())['habits'], isEmpty);
      final plantedReadback = await readRemoteGarden(
        'synthetic-a-plant-readback.sqlite',
      );
      expect(
        (plantedReadback['habits'] as List).single,
        containsPair('id', firstRecipe.id),
      );
      expect(
        (plantedReadback['habits'] as List).single,
        containsPair('behavior', firstRecipe.behavior),
      );

      await tester.ensureVisible(find.text('Did more'));
      await tester.tap(find.text('Did more'));
      await _waitFor(
        tester,
        find.text('Undo today'),
        ready: () async =>
            (await activeStore!.habits()).single.today == CheckInResult.didMore,
      );
      await syncService().sync();
      final didMoreCheckins = (await activeStore!.export())['checkins'] as List;
      expect(
        didMoreCheckins.any(
          (checkin) => (checkin as Map)['result'] == 'didMore',
        ),
        isTrue,
      );
      expect((await activeStore!.syncPayload())['checkins'], isEmpty);
      final practiceReadback = await readRemoteGarden(
        'synthetic-a-practice-readback.sqlite',
      );
      expect(practiceReadback['checkins'], didMoreCheckins);
      await _dismissCelebration(tester);
      await tester.ensureVisible(find.text('Undo today'));
      await tester.tap(find.text('Undo today'));
      await _waitFor(
        tester,
        find.text('Did more'),
        ready: () async =>
            (await activeStore!.habits()).single.practiceCount == 0,
      );
      await syncService().sync();

      await tester.ensureVisible(find.text('Not today'));
      await tester.tap(find.text('Not today'));
      await tester.pumpAndSettle();
      expect(find.text('Rest days belong in a garden.'), findsOneWidget);
      await tester.tap(find.text('No reason needed'));
      await tester.pumpAndSettle();
      expect(
        (await activeStore!.habits()).single.today,
        CheckInResult.notToday,
      );
      await tester.ensureVisible(find.text('Undo today'));
      await tester.tap(find.text('Undo today'));
      await _waitFor(
        tester,
        find.text('Did it'),
        ready: () async =>
            (await activeStore!.habits()).single.practiceCount == 0,
      );

      await tester.ensureVisible(find.byTooltip('Edit recipe'));
      await tester.tap(find.byTooltip('Edit recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Adjust your recipe'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'I will...'),
        'take one easy breath',
      );
      await tester.ensureVisible(find.text('I practiced my celebration'));
      await tester.tap(find.text('I practiced my celebration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save recipe'));
      await _waitFor(
        tester,
        find.text('Did it'),
        ready: () async =>
            (await activeStore!.habits()).single.behavior ==
            'take one easy breath',
      );

      for (var day = 1; day <= 17; day++) {
        await _advanceClock(tester);
        await tester.ensureVisible(find.text('Did it'));
        await tester.tap(find.text('Did it'));
        await _waitFor(
          tester,
          find.text('Undo today'),
          ready: () async =>
              (await activeStore!.habits()).single.practiceCount == day,
        );
        await _dismissCelebration(tester);
      }
      await tester.ensureVisible(find.text('Check naturalness'));
      await _naturalnessReflection(tester);
      expect((await activeStore!.habits()).single.status, 'active');

      for (var day = 18; day <= 31; day++) {
        await _advanceClock(tester);
        await tester.ensureVisible(find.text('Did it'));
        await tester.tap(find.text('Did it'));
        await _waitFor(
          tester,
          find.text('Undo today'),
          ready: () async =>
              (await activeStore!.habits()).single.practiceCount == day,
        );
        await _dismissCelebration(tester);
      }
      await tester.ensureVisible(find.text('Check naturalness'));
      await _naturalnessReflection(tester);
      await _waitFor(
        tester,
        find.text('Check naturalness'),
        ready: () async =>
            (await activeStore!.habits()).single.status == 'graduated',
      );

      await tester.ensureVisible(
        find.text('Weekly reflection / Recipe Doctor'),
      );
      await tester.tap(find.text('Weekly reflection / Recipe Doctor'));
      await tester.pumpAndSettle();
      expect(find.text('A minute for your recipe'), findsOneWidget);
      await tester.tap(find.text('Keep my recipe'));
      await tester.pumpAndSettle();
      await _waitFor(
        tester,
        find.text('Did it'),
        ready: () async => (await activeStore!.syncPayload())['events'] != null,
      );
      await syncService().sync();

      await tester.tap(find.byTooltip('Help us grow'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Synthetic API acceptance feedback',
      );
      await tester.tap(find.text('Save feedback'));
      await tester.pumpAndSettle();
      expect(find.text('My feedback'), findsOneWidget);
      expect(
        (await activeStore!.voice()).single['body'],
        'Synthetic API acceptance feedback',
      );
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      await syncService().sync();

      await tester.tap(find.byTooltip('Settings and privacy'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Export my data (JSON)'));
      await tester.tap(find.text('Export my data (JSON)'));
      await _waitFor(
        tester,
        find.textContaining('Local export saved.'),
        duration: const Duration(seconds: 8),
      );
      final export = File(p.join(runRoot.path, 'synthetic-a-export.json'));
      expect(await export.exists(), isTrue);
      final exported = await export.readAsString();
      expect(exported, isNot(contains(secret)));
      expect(exported, contains('Synthetic API acceptance feedback'));
      expect(exported, contains(firstRecipe.id));
      expect(tester.takeException(), isNull);
      await _dismissCelebration(tester);
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();

      final firstVoice = (await activeStore!.voice()).single;
      await tester.tap(find.byTooltip('Help us grow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('My feedback'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete this feedback'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this feedback?'), findsOneWidget);
      await tester.tap(find.text('Delete feedback'));
      await tester.pumpAndSettle();
      expect(await activeStore!.voice(), isEmpty);
      await syncService().sync();

      await tester.ensureVisible(find.byTooltip('Delete this recipe'));
      await tester.tap(find.byTooltip('Delete this recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this recipe?'), findsOneWidget);
      await tester.tap(find.text('Delete recipe'));
      await tester.pumpAndSettle();
      expect(await activeStore!.habits(), isEmpty);
      await syncService().sync();

      final deletionReadback = await GardenStore.open(
        p.join(runRoot.path, 'synthetic-a-deletion-readback.sqlite'),
        firstAccount,
      );
      try {
        await SyncService(
          activeSession!,
          deletionReadback,
          testApiOrigin: testApi.origin,
        ).sync();
        expect(await deletionReadback.habits(), isEmpty);
        expect(await deletionReadback.voice(), isEmpty);
        expect((await activeStore!.syncPayload())['deletions'], isEmpty);
        expect((await deletionReadback.syncPayload())['deletions'], isEmpty);
        final tombstones =
            (await deletionReadback.export())['deletions'] as List;
        expect(
          tombstones.any(
            (row) =>
                (row as Map)['type'] == 'habits' &&
                row['recordId'] == firstRecipe.id,
          ),
          isTrue,
        );
        expect(
          tombstones.any(
            (row) =>
                (row as Map)['type'] == 'voice' &&
                row['recordId'] == firstVoice['id'],
          ),
          isTrue,
        );
      } finally {
        await deletionReadback.close();
      }

      await tester.tap(find.text('Close test profile'));
      await tester.pumpAndSettle();
      await _waitFor(tester, find.text('Continue to test garden'));
      await _signIn(tester, username: 'synthetic-a', secret: secret);
      await _waitFor(tester, find.text('Plant a habit'));
      recipes = await activeStore!.habits();
      expect(recipes, isEmpty);
      final reopened = await GardenStore.open(
        p.join(runRoot.path, 'synthetic-a-readback.sqlite'),
        firstAccount,
      );
      try {
        await SyncService(
          activeSession!,
          reopened,
          testApiOrigin: testApi.origin,
        ).sync();
        expect(await reopened.habits(), isEmpty);
        expect(await reopened.voice(), isEmpty);
        expect(
          ((await reopened.export())['deletions'] as List).length,
          greaterThanOrEqualTo(2),
        );
        expect((await reopened.syncPayload())['deletions'], isEmpty);
      } finally {
        await reopened.close();
      }

      await tester.tap(find.text('Close test profile'));
      await tester.pumpAndSettle();
      await _waitFor(tester, find.text('Continue to test garden'));
      await _signIn(tester, username: 'synthetic-b', secret: secret);
      await _waitFor(tester, find.text('Plant a habit'));
      await _plant(tester, behavior: 'write one synthetic word');
      await _waitFor(
        tester,
        find.text('Did it'),
        ready: () async => (await activeStore!.habits()).length == 1,
      );
      await syncService().sync();
      final secondAccount = activeStore!.account;
      expect(secondAccount, isNot(firstAccount));
      expect(
        (await activeStore!.habits()).single.behavior,
        'write one synthetic word',
      );
      expect((await activeStore!.voice()).isEmpty, isTrue);

      final secondHabitId = (await activeStore!.habits()).single.id;
      await tester.ensureVisible(find.byTooltip('Delete this recipe'));
      await tester.tap(find.byTooltip('Delete this recipe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete recipe'));
      await tester.pumpAndSettle();
      expect(await activeStore!.habits(), isEmpty);
      await syncService().sync();
      final secondReadback = await GardenStore.open(
        p.join(runRoot.path, 'synthetic-b-readback.sqlite'),
        secondAccount,
      );
      try {
        await SyncService(
          activeSession!,
          secondReadback,
          testApiOrigin: testApi.origin,
        ).sync();
        expect(await secondReadback.habits(), isEmpty);
        expect(
          ((await secondReadback.export())['deletions'] as List).any(
            (row) =>
                (row as Map)['recordId'] == secondHabitId &&
                row['type'] == 'habits',
          ),
          isTrue,
        );
        expect((await activeStore!.syncPayload())['deletions'], isEmpty);
        expect((await secondReadback.syncPayload())['deletions'], isEmpty);
      } finally {
        await secondReadback.close();
      }

      await tester.tap(find.text('Close test profile'));
      await tester.pumpAndSettle();
      await _waitFor(tester, find.text('Continue to test garden'));
      await _signIn(tester, username: 'synthetic-a', secret: secret);
      await _waitFor(tester, find.text('Plant a habit'));
      expect(await activeStore!.habits(), isEmpty);

      final serverDatabase = await File(p.join(runRoot.path, 'server.json'))
          .readAsString();
      expect(serverDatabase, isNot(contains(secret)));
      expect(serverDatabase, contains(firstAccount));
      expect(serverDatabase, contains(secondAccount));
      expect(serverDatabase, contains(firstRecipe.id));
      expect(serverDatabase, contains(firstVoice['id']));
      expect(serverDatabase, contains(secondHabitId));
      expect(
        serverDatabase,
        isNot(contains('Synthetic API acceptance feedback')),
      );
      await for (final entity in runRoot.list(recursive: true)) {
        if (entity is File) {
          final contents = utf8.decode(
            await entity.readAsBytes(),
            allowMalformed: true,
          );
          expect(contents, isNot(contains(secret)));
          expect(contents, isNot(contains('eyJhbGci')));
        }
      }
      expect(tester.takeException(), isNull);
      completedEvidence = {
        'schemaVersion': 1,
        'testOutcome': 'passed',
        'apiOrigin': testApi.origin.toString(),
        'databaseFile': 'server.json',
        'ownerPartitionHashes': [firstAccount, secondAccount],
        'createdRecipeIds': [firstRecipe.id, secondHabitId],
        'createdFeedbackIds': [firstVoice['id']],
        'deletionReadbackVerified': true,
        'restartReadbackVerified': true,
        'uiJourney': [
          'wrong test key rejected before profile creation',
          'synthetic profile sign-in',
          'plant and edit recipe',
          'did-more, rest, did-it and undo',
          'weekly reflection and deterministic Recipe Doctor',
          'two naturalness reflections and graduation',
          'feedback create, export and delete',
          'recipe delete and remote tombstone readback',
          'app-profile close/reopen and second-owner isolation',
        ],
        'backend': 'production createHandlers with a disposable file-backed Cosmos-compatible test adapter',
        'authEventPersisted': false,
        'providerFederationObserved': false,
        'azureCosmosObserved': false,
        'windowsNotificationDeliveryObserved': false,
        'accessibilityEvaluationObserved': false,
      };
    },
  );
}

Future<void> _signIn(
  WidgetTester tester, {
  required String username,
  required String secret,
  bool expectFailure = false,
}) async {
  await tester.enterText(
    find.byKey(TestOnlyAuthGate.usernameFieldKey),
    username,
  );
  await tester.enterText(find.byKey(TestOnlyAuthGate.secretFieldKey), secret);
  await tester.tap(find.text('Continue to test garden'));
  await tester.pumpAndSettle();
  if (expectFailure) {
    expect(
      find.text('Test sign-in failed. No garden was opened.'),
      findsOneWidget,
    );
    expect(find.byType(GardenScreen), findsNothing);
  }
}

Future<void> _plant(
  WidgetTester tester, {
  String behavior = 'relax my shoulders',
}) async {
  await tester.tap(find.text('Plant a habit'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ActionChip, 'Calm'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'I will...'),
    behavior,
  );
  await tester.ensureVisible(find.text('I practiced my celebration'));
  await tester.tap(find.text('I practiced my celebration'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Plant this seed'));
}

Future<void> _naturalnessReflection(WidgetTester tester) async {
  await tester.tap(find.text('Check naturalness'));
  await tester.pumpAndSettle();
  expect(find.text('How natural does this feel?'), findsOneWidget);
  final sliders = find.byType(Slider);
  expect(sliders, findsNWidgets(4));
  for (var i = 0; i < 4; i++) {
    await tester.drag(sliders.at(i), const Offset(500, 0));
    await tester.pumpAndSettle();
  }
  expect(
    tester.widgetList<Slider>(sliders).every((slider) => slider.value == 7),
    isTrue,
  );
  await tester.ensureVisible(find.text('Save reflection'));
  await tester.tap(find.text('Save reflection'));
  await tester.pumpAndSettle();
}

Future<void> _advanceClock(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('test-advance-clock')));
  await tester.pumpAndSettle();
}

Future<void> _dismissCelebration(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Future<bool> Function()? ready,
  Duration duration = const Duration(seconds: 10),
}) async {
  final timer = Stopwatch()..start();
  while (timer.elapsed < duration) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty &&
        (ready == null || await tester.runAsync(ready) == true)) {
      return;
    }
  }
  fail('The desktop UI did not reach the expected state.');
}
