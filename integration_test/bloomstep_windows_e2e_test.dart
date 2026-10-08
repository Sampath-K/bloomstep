import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/services/sync_service.dart';

import 'support/local_test_api.dart';
import 'support/test_only_app.dart';

DateTime syntheticJourneyStart(DateTime runStartedAt) {
  final utc = runStartedAt.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
  ).subtract(const Duration(days: 31));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'synthetic sign-in, real desktop UI, production sync handlers, isolation, export, restart and cleanup',
    (tester) async {
      final secret = Platform.environment['BLOOMSTEP_TEST_AUTH_SECRET'];
      expect(TestOnlyAuthGate.validTestSecret(secret), isTrue);
      final runRoot = await Directory.systemTemp.createTemp('bloomstep-it-');
      var testNow = syntheticJourneyStart(DateTime.now());
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
                expect(cleanupVerified, isTrue);
                expect(apiProcessStopped, isTrue);
                expect(profileClosed, isTrue);
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

      final captureBoundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureBoundary,
          child: TestOnlyBloomstepApp(
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

      await _plant(tester, captureBoundary: captureBoundary);
      await _waitFor(
        tester,
        find.text('Did it'),
        ready: () async => (await activeStore!.habits()).length == 1,
      );
      var recipes = await activeStore!.habits();
      final firstRecipe = recipes.single;
      expect(firstRecipe.behavior, 'take one slow breath');
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
      await _waitFor(tester, find.text('Rest days belong in a garden.'));
      expect(find.text('Rest days belong in a garden.'), findsOneWidget);
      await tester.tap(find.text('No reason needed'));
      await _waitFor(
        tester,
        find.text('Undo today'),
        ready: () async =>
            (await activeStore!.habits()).single.today ==
            CheckInResult.notToday,
      );
      expect(
        (await activeStore!.habits()).single.today,
        CheckInResult.notToday,
      );
      await tester.ensureVisible(find.text('Undo today'));
      await tester.tap(find.text('Undo today'));
      await _waitFor(
        tester,
        find.text('Did it'),
        ready: () async => (await activeStore!.habits()).single.today == null,
      );

      // Undo makes timestamps monotonic even when the synthetic clock is frozen.
      testNow = testNow.add(const Duration(seconds: 1));
      await tester.ensureVisible(find.byTooltip('Edit recipe'));
      await tester.tap(find.byTooltip('Edit recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Adjust your recipe'), findsOneWidget);
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
      await _waitFor(
        tester,
        find.text('Did it'),
        ready: () async =>
            (await activeStore!.habits()).single.behavior ==
            'take one easy breath',
      );
      await syncService().sync();
      final editedReadback = await readRemoteGarden(
        'synthetic-a-edit-readback.sqlite',
      );
      expect(
        (editedReadback['habits'] as List).single,
        containsPair('behavior', 'take one easy breath'),
      );
      expect((await activeStore!.syncPayload())['habits'], isEmpty);

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
      await _naturalnessReflection(tester, activeStore!);
      expect((await activeStore!.habits()).single.status, 'active');
      expect(find.textContaining('Naturalness available '), findsOneWidget);

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
      await _naturalnessReflection(tester, activeStore!);
      await _waitFor(
        tester,
        find.text('Weekly reflection / Recipe Doctor'),
        ready: () async =>
            (await activeStore!.habits()).single.status == 'graduated',
      );

      await tester.ensureVisible(
        find.text('Weekly reflection / Recipe Doctor'),
      );
      await tester.tap(find.text('Weekly reflection / Recipe Doctor'));
      await _waitFor(tester, find.text('A minute for your recipe'));
      expect(find.text('A minute for your recipe'), findsOneWidget);
      await tester.tap(find.text('Keep my recipe'));
      await _waitFor(
        tester,
        find.text('Weekly reflection / Recipe Doctor'),
        ready: () async => await activeStore!.setting('weeklyLast') != null,
      );
      await syncService().sync();

      await tester.tap(find.byTooltip('Help us grow'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Synthetic API acceptance feedback',
      );
      await tester.tap(find.text('Save feedback'));
      await _waitFor(
        tester,
        find.text('My feedback'),
        ready: () async => (await activeStore!.voice()).any(
          (row) => row['body'] == 'Synthetic API acceptance feedback',
        ),
      );
      expect(find.text('My feedback'), findsOneWidget);
      expect(
        (await activeStore!.voice()).single['body'],
        'Synthetic API acceptance feedback',
      );
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      await syncService().sync();
      final feedbackReadback = await readRemoteGarden(
        'synthetic-a-feedback-readback.sqlite',
      );
      expect(
        (feedbackReadback['voice'] as List).single,
        containsPair('body', 'Synthetic API acceptance feedback'),
      );
      expect(
        (feedbackReadback['voice'] as List).single,
        containsPair('id', (await activeStore!.voice()).single['id']),
      );
      expect((await activeStore!.syncPayload())['voice'], isEmpty);

      await tester.tap(find.byTooltip('Settings and privacy'));
      await _waitFor(tester, find.text('Export my data (JSON)'));
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
      await _waitFor(tester, find.text('My feedback'));
      expect(find.text('My feedback'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete this feedback'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this feedback?'), findsOneWidget);
      await tester.tap(find.text('Delete feedback'));
      await _waitFor(
        tester,
        find.text('Plant a habit'),
        ready: () async =>
            (await activeStore!.voice()).isEmpty &&
            find.text('My feedback').evaluate().isEmpty,
      );
      expect(await activeStore!.voice(), isEmpty);
      await syncService().sync();

      await tester.ensureVisible(find.byTooltip('Delete this recipe'));
      await tester.tap(find.byTooltip('Delete this recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this recipe?'), findsOneWidget);
      await tester.tap(find.text('Delete recipe'));
      await _waitFor(
        tester,
        find.text('Plant a habit'),
        ready: () async => (await activeStore!.habits()).isEmpty,
      );
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
        expect((await deletionReadback.export())['checkins'], isEmpty);
        expect((await deletionReadback.export())['reflections'], isEmpty);
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
      await _waitFor(
        tester,
        find.text('Plant a habit'),
        ready: () async => (await activeStore!.habits()).isEmpty,
      );
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
        'recipeReadbackVerified': true,
        'editedRecipeReadbackVerified': true,
        'checkinReadbackVerified': true,
        'feedbackReadbackVerified': true,
        'acknowledgedOutboxEmptyVerified': true,
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
  String? behavior,
  GlobalKey? captureBoundary,
}) async {
  await tester.tap(find.text('Plant a habit'));
  await tester.pumpAndSettle();
  if (captureBoundary != null) {
    await _captureBuilderFrame(tester, captureBoundary, 'picker-1-anchor');
  }
  await tester.ensureVisible(find.text('pour my morning drink'));
  await tester.tap(find.text('pour my morning drink'));
  await tester.pumpAndSettle();
  if (captureBoundary != null) {
    await _captureBuilderFrame(tester, captureBoundary, 'picker-2-action');
  }
  if (behavior == null) {
    await tester.ensureVisible(find.text('take one slow breath'));
    await tester.tap(find.text('take one slow breath'));
  } else {
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'I will...'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'I will...'),
      behavior,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a celebration'));
  }
  await tester.pumpAndSettle();
  if (captureBoundary != null) {
    await _captureBuilderFrame(tester, captureBoundary, 'picker-3-celebration');
  }
  await tester.ensureVisible(find.text('relax my shoulders and smile'));
  await tester.tap(find.text('relax my shoulders and smile'));
  await tester.pumpAndSettle();
  if (behavior != null) {
    await tester.ensureVisible(find.text('I practiced my celebration'));
    await tester.tap(find.text('I practiced my celebration'));
    await tester.pumpAndSettle();
  }
  if (captureBoundary != null) {
    await _captureBuilderFrame(
      tester,
      captureBoundary,
      'picker-complete-optional-practice-off',
    );
  }
  await tester.tap(find.text('Plant this seed'));
  await _waitFor(tester, find.text('See my seed'));
  if (captureBoundary != null) {
    await _captureBuilderFrame(tester, captureBoundary, 'planted-next-step');
  }
  await tester.tap(find.text('See my seed'));
  await tester.pumpAndSettle();
}

Future<void> _captureBuilderFrame(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final directory = Platform.environment['BLOOMSTEP_TEST_SCREENSHOTS_DIR'];
  if (directory == null) return;
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      await Directory(directory).create(recursive: true);
      final file = File(p.join(directory, '$name.png'));
      if (await file.exists()) {
        throw StateError('Refusing to replace a previous rendered frame.');
      }
      await file.writeAsBytes(bytes);
      await File(p.join(directory, 'frames.jsonl')).writeAsString(
        '${jsonEncode({'sourceRevision': Platform.environment['BLOOMSTEP_SOURCE_REVISION'], 'kind': 'compiled-Windows-Flutter-rendered-frame-synthetic-only', 'file': '$name.png', 'sha256': sha256.convert(bytes).toString(), 'width': image.width, 'height': image.height, 'customerAcceptance': false, 'nativeWindowOrDpiProof': false})}\n',
        mode: FileMode.append,
      );
    } finally {
      image.dispose();
    }
  });
}

Future<void> _naturalnessReflection(
  WidgetTester tester,
  GardenStore store,
) async {
  final previous = ((await store.export())['reflections'] as List).length;
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
  await _waitFor(
    tester,
    find.text('Weekly reflection / Recipe Doctor'),
    ready: () async =>
        ((await store.export())['reflections'] as List).length == previous + 1,
  );
}

Future<void> _advanceClock(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('test-advance-clock')));
  await _waitFor(tester, find.text('Did it'));
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
  var modelReady = false;
  var gardenIdle = false;
  var actionReady = false;
  while (timer.elapsed < duration) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    modelReady = ready == null || await tester.runAsync(ready) == true;
    if (finder.evaluate().isNotEmpty && modelReady) {
      // SQLite may finish before _load has rebuilt and re-enabled UI actions.
      final plantButtons = tester.widgetList<FilledButton>(
        find.widgetWithText(FilledButton, 'Plant a habit', skipOffstage: false),
      );
      gardenIdle = plantButtons.every((button) => button.enabled);
      final actions = tester.widgetList<ButtonStyleButton>(
        find.ancestor(
          of: finder,
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        ),
      );
      actionReady = actions.every((button) => button.enabled);
      if (gardenIdle && actionReady) return;
    }
  }
  fail(
    'The desktop UI did not reach $finder '
    '(matches: ${finder.evaluate().length}, '
    'modelReady: $modelReady, gardenIdle: $gardenIdle, '
    'actionReady: $actionReady).',
  );
}
