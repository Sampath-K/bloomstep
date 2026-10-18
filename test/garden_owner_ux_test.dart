import 'package:budlark/app/theme.dart';
import 'package:budlark/features/garden/garden_screen.dart';
import 'package:budlark/features/garden/profile_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'garden_learning_test.dart' show fixture, settleDatabase;
import 'support/visual_capture.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('owner garden surfaces render in ${dark ? "dark" : "light"}', (
      tester,
    ) async {
      final (store, _) = await fixture(tester);
      final boundary = GlobalKey();
      var received = false;
      final submittedIds = <String>[];
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: dark ? BudlarkTheme.dark() : BudlarkTheme.light(),
            home: GardenScreen(
              store: store,
              testDisableServices: true,
              feedbackSender: (id) async {
                submittedIds.add(id);
                return received;
              },
              profileBuilder: (signOut, manage) => ProfileSection(
                signedIn: true,
                configured: true,
                busy: false,
                onSignIn: () async {},
                onSignOut: signOut,
                onManage: manage,
                onCopyDeviceGarden: () async {},
                onSwitchGarden: () async {},
                onClearSavedSignIn: () async {},
              ),
            ),
          ),
        ),
      );
      await settleDatabase(tester);
      expect(find.text('Signed-in account'), findsNothing);
      expect(find.text('Sync now'), findsNothing);
      final actions = ['Did it', 'Did more', 'Not today'];
      for (final action in actions) {
        expect(find.widgetWithText(OutlinedButton, action), findsOneWidget);
      }
      final widths = actions
          .map(
            (action) => tester
                .getSize(find.widgetWithText(OutlinedButton, action))
                .width,
          )
          .toSet();
      expect(widths, hasLength(1));
      await captureVisual(
        tester,
        boundary,
        'owner-garden-${dark ? "dark" : "light"}',
      );
      await tester.tap(find.byTooltip('More for Calm'));
      await tester.pumpAndSettle();
      for (final label in [
        'Edit recipe',
        'Delete this recipe',
        'Weekly reflection / Recipe Doctor',
        'Check naturalness',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await captureVisual(
        tester,
        boundary,
        'owner-more-${dark ? "dark" : "light"}',
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings and privacy'));
      await settleDatabase(tester);
      for (final group in [
        'Profile & account',
        'Reminders',
        'Privacy & measurement',
        'Garden & data',
        'App & support',
      ]) {
        expect(find.text(group), findsOneWidget);
      }
      expect(find.text('Share product event counts'), findsNothing);
      await captureVisual(
        tester,
        boundary,
        'owner-settings-${dark ? "dark" : "light"}',
      );
      await tester.tap(find.text('Profile & account'));
      await tester.pumpAndSettle();
      expect(find.text('Signed-in account'), findsOneWidget);
      expect(find.text('Copy device habits to this account'), findsOneWidget);
      expect(find.text('View device garden'), findsOneWidget);
      expect(find.text('Clear saved sign-in'), findsOneWidget);
      await tester.tap(find.text('Profile & account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy & measurement'));
      await tester.pumpAndSettle();
      final counts = find.widgetWithText(
        SwitchListTile,
        'Share product event counts',
      );
      expect(tester.widget<SwitchListTile>(counts).value, isFalse);
      expect(
        find.textContaining(
          'Turning off stops future sharing and clears unsent counts',
        ),
        findsOneWidget,
      );
      await captureVisual(
        tester,
        boundary,
        'owner-privacy-${dark ? "dark" : "light"}',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Help us grow'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.byTooltip('5 of 5 stars'), findsOneWidget);
      await tester.tap(find.byTooltip('5 of 5 stars'));
      await tester.enterText(find.byType(TextField), 'A helpful tiny step');
      await captureVisual(
        tester,
        boundary,
        'owner-feedback-${dark ? "dark" : "light"}',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send feedback'));
      await settleDatabase(tester);
      expect(
        find.text('Not sent — retry when you are connected.'),
        findsOneWidget,
      );
      expect(find.text('Received by the team.'), findsNothing);
      received = true;
      await tester.tap(find.text('Retry sending'));
      await settleDatabase(tester);
      expect(submittedIds, hasLength(2));
      expect(submittedIds.toSet(), hasLength(1));
      expect(find.text('Received by the team.'), findsOneWidget);
      await captureVisual(
        tester,
        boundary,
        'owner-feedback-received-${dark ? "dark" : "light"}',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('My feedback'), findsNothing);
    });
  }

  testWidgets('device feedback clearly cannot send', (tester) async {
    final (store, _) = await fixture(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: GardenScreen(
          store: store,
          deviceGuest: true,
          testDisableServices: true,
        ),
      ),
    );
    await settleDatabase(tester);
    await tester.tap(find.byTooltip('Help us grow'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This device garden cannot send feedback.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Send feedback'),
          )
          .onPressed,
      isNull,
    );
  });
}
