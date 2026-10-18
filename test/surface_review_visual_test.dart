import 'dart:convert';

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/services/invitation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/visual_capture.dart';
import 'support/dialog_copy_contract.dart';
import 'garden_learning_test.dart' show FakeUpdates, settleDatabase;
import 'invitation_widget_test.dart' show waitInvitation;

void main() {
  testWidgets('reachable local surfaces rendered with synthetic tasks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await loadVisualFonts(tester);
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'synthetic-surface-review'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.runAsync(() => store.setSetting('reducedMotion', 'true'));
    await tester.runAsync(
      () => store.plant(
        aspiration: 'Synthetic calm',
        anchor: 'put my mug down',
        behavior: 'take one breath',
        celebration: 'smile',
        species: 'Fern',
      ),
    );
    final token = base64Url
        .encode(List<int>.generate(32, (i) => i))
        .replaceAll('=', '');
    final invitations = InvitationService(
      store,
      tokenProvider: () async => 'synthetic',
      origin: 'https://synthetic.example',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        return http.Response(
          jsonEncode({
            'invitationId': body['requestId'],
            'token': token,
            'channel': body['channel'],
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(days: 7))
                .toIso8601String(),
            'recipeCard': body['recipeCard'],
          }),
          200,
        );
      }),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: BloomstepTheme.light(),
          builder: (context, child) => Column(
            children: [
              const Material(
                child: Text('SYNTHETIC UI - disposable garden, mock services'),
              ),
              Expanded(child: child!),
            ],
          ),
          home: GardenScreen(
            store: store,
            invitationService: invitations,
            updateService: FakeUpdates(null),
          ),
        ),
      ),
    );
    await waitInvitation(tester, find.text('Did it'));
    await tester.pumpAndSettle();
    Future<void> capture(String name) =>
        captureVisual(tester, key, 'surface-$name');
    Future<void> tap(String label) async {
      await tester.ensureVisible(find.text(label).last);
      await tester.tap(find.text(label).last);
      await settleDatabase(tester);
    }

    Future<void> escape() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }

    await capture('populated');
    await tap('Did it');
    await capture('checkin-celebration');
    await tester.pump(const Duration(seconds: 6));
    await tap('Undo today');
    await tap('Not today');
    await capture('rest-reason');
    await escape();
    await tester.tap(find.byTooltip('More for Synthetic calm'));
    await tester.pumpAndSettle();
    await tap('Weekly reflection / Recipe Doctor');
    await capture('weekly-reflection');
    await escape();
    await tester.tap(find.byTooltip('More for Synthetic calm'));
    await tester.pumpAndSettle();
    await tap('Check naturalness');
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Starting feels automatic',
      ),
      findsOneWidget,
    );
    await capture('naturalness');
    await escape();
    await tester.tap(find.byTooltip('More for Synthetic calm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit recipe'));
    await tester.pumpAndSettle();
    await capture('edit-recipe');
    await escape();
    await tester.tap(find.byTooltip('More for Synthetic calm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete this recipe'));
    await tester.pumpAndSettle();
    await capture('delete-recipe-confirm');
    await escape();
    expect((await tester.runAsync(store.habits))!.length, 1);
    await tester.tap(find.byTooltip('Help us grow'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Leave out passwords, private account information and sensitive habit details.',
      ),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await capture('feedback-compose');
    await tester.tap(find.byTooltip('5 of 5 stars'));
    await tester.pumpAndSettle();
    await capture('rating-compose');
    await tap('Close');
    await tester.tap(find.byTooltip('Invite a friend'));
    await tester.pumpAndSettle();
    await tap('Include a recipe? Optional');
    await tap('Choose and approve a recipe card');
    await capture('share-recipe-picker');
    await tap('Synthetic calm');
    await capture('share-exact-approval');
    await tap('Share this exact card');
    expect(find.text('Approved recipe included'), findsOneWidget);
    expect(
      find.text(
        'Anyone with the link can open it. No one is contacted automatically.',
      ),
      findsOneWidget,
    );
    await tap('Copy link');
    await waitInvitation(tester, find.text('Link copied'));
    await tester.pumpAndSettle();
    await capture('share-approved-receipt');
    await tap('Remove recipe card');
    expect(find.text('Link copied'), findsNothing);
    expect(
      find.text(
        'Anyone with the link can open it. No one is contacted automatically.',
      ),
      findsOneWidget,
    );
    await escape();
    await tester.tap(find.byTooltip('Settings and privacy'));
    await settleDatabase(tester);
    await tap('Privacy & measurement');
    expect(
      find.textContaining('private account details, sensitive habit details'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Device-only gardens send nothing'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Turning off stops future sharing and clears unsent counts',
      ),
      findsOneWidget,
    );
    await capture('settings-consent');
    await tap('Privacy & measurement');
    await tap('Garden & data');
    await tester.ensureVisible(find.text('Export my data (JSON)'));
    await capture('settings-export');
    await tap('Garden & data');
    await tap('App & support');
    await tap('Check for updates');
    await capture('updates-empty');
    await escape();
    await tap('App & support');
    await tap('Garden & data');
    await tap('Delete local garden');
    const localDeleteDisclosure =
        'This deletes habits, check-ins, and reflections saved on this '
        'device—not your Microsoft or Google account.';
    expect(find.text('Delete local data?'), findsOneWidget);
    expect(find.text(localDeleteDisclosure), findsOneWidget);
    expectConciseDialogCopy(localDeleteDisclosure);
    await capture('delete-local-confirm');
    await escape();
    await tap('Done');
    expect((await tester.runAsync(store.habits))!.length, 1);
    // A third recipe triggers the existing explicit "start small" decision.
    await tester.runAsync(() async {
      for (var i = 0; i < 2; i++) {
        await store.plant(
          aspiration: 'Synthetic extra $i',
          anchor: 'put my mug down',
          behavior: 'take one breath',
          celebration: 'smile',
          species: 'Fern',
        );
      }
    });
    await tester.tap(find.byTooltip('Settings and privacy'));
    await settleDatabase(tester);
    await tap('App & support');
    await tap('Reduced motion');
    await tap('Done');
    await tap('Plant a habit');
    await capture('start-small');
    await escape();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'feedback and destructive disclosures fit 200 percent short windows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadVisualFonts(tester);
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'synthetic-compact-dialogs'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: BloomstepTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: Column(
                children: [
                  const Material(child: Text('SYNTHETIC UI - no live account')),
                  Expanded(child: child!),
                ],
              ),
            ),
            home: GardenScreen(store: store),
          ),
        ),
      );
      await waitInvitation(tester, find.text('Plant a habit'));
      await tester.tap(find.byTooltip('Help us grow'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.text(
          'Sent only when you choose Send feedback. Unsent feedback stays on this device until it can sync.',
        ),
      );
      await captureVisual(tester, key, 'surface-feedback-200percent-short');
      await tester.tap(find.text('Close'));
      await settleDatabase(tester);
      await tester.tap(find.byTooltip('Settings and privacy'));
      await settleDatabase(tester);
      await tester.tap(find.text('Privacy & measurement'));
      await tester.pumpAndSettle();
      expect(find.text('What these counts include'), findsOneWidget);
      await tester.ensureVisible(find.text('What these counts include'));
      await tester.tap(find.text('What these counts include'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Device-only gardens send no counts'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Privacy & measurement'));
      await tester.tap(find.text('Privacy & measurement'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Garden & data'));
      await tester.tap(find.text('Garden & data'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete local garden'));
      await tester.tap(find.text('Delete local garden'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text(
          'This deletes habits, check-ins, and reflections saved on this '
          'device—not your Microsoft or Google account.',
        ),
      );
      await captureVisual(tester, key, 'surface-delete-200percent-short');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
