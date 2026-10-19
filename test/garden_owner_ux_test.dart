import 'package:budlark/app/theme.dart';
import 'package:budlark/features/garden/garden_screen.dart';
import 'package:budlark/features/garden/profile_section.dart';
import 'package:budlark/services/identity.dart';
import 'package:budlark/services/anonymous_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'garden_learning_test.dart' show fixture, settleDatabase;
import 'support/visual_capture.dart';

void main() {
  for (final guest in [false, true]) {
    for (final accepted in [false, true]) {
      testWidgets('anonymous feedback ${accepted ? "receipt" : "queue"} is honest, guest=$guest', (tester) async {
        final (store, _) = await fixture(tester);
        final directory = await Directory.systemTemp.createTemp('feedback-ui-');
        addTearDown(() => directory.delete(recursive: true));
        var requests = 0;
        final feedback = AnonymousFeedback(
          directory.path,
          origin: 'https://api.example.invalid/api',
          client: MockClient((request) async {
            requests++;
            expect(request.headers.keys.map((key) => key.toLowerCase()), isNot(contains('authorization')));
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            expect(payload.keys.toSet(), {'consent', 'deviceId', 'requestId', 'text'});
            expect(payload['consent'], isTrue);
            return accepted
                ? http.Response(jsonEncode({
                    'status': 'received',
                    'receiptId': '11111111-1111-4111-8111-111111111111',
                    'receivedAt': DateTime.now().toUtc().toIso8601String(),
                  }), 201)
                : http.Response('', 503);
          }),
        );
        await tester.pumpWidget(MaterialApp(
          home: GardenScreen(
            store: store,
            deviceGuest: guest,
            testDisableServices: true,
            anonymousFeedback: feedback,
          ),
        ));
        await settleDatabase(tester);
        await tester.tap(find.byTooltip('Help us grow'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Synthetic feedback only');
        await tester.tap(find.widgetWithText(FilledButton, 'Send feedback'));
        await settleDatabase(tester);
        expect(requests, 1);
        expect(find.text('Received by the team.'), accepted ? findsOneWidget : findsNothing);
        expect(await tester.runAsync(feedback.pendingCount), accepted ? 0 : 1);
        if (!accepted) {
          expect(find.textContaining('Saved on this device — not received.'), findsOneWidget);
        }
        await tester.tap(find.widgetWithText(TextButton, accepted ? 'Done' : 'Close'));
        await tester.pumpAndSettle();
      });
    }
  }
  for (final signedIn in [false, true]) {
    testWidgets('main window exposes ${signedIn ? "profile" : "sign-in"}', (
      tester,
    ) async {
      final (store, _) = await fixture(tester);
      var actions = 0;
      await tester.pumpWidget(MaterialApp(
        home: GardenScreen(
          store: store,
          testDisableServices: true,
          profileSummaryBuilder: (_, __) => ProfileSection(
            signedIn: signedIn,
            configured: true,
            busy: false,
            compactSummary: true,
            profile: signedIn
                ? const IdentityProfile(displayName: 'Alex Rivera')
                : null,
            onSignIn: () async { actions++; },
            onSignOut: () async { actions++; },
            onManage: () { actions++; },
          ),
        ),
      ));
      await settleDatabase(tester);
      expect(find.text(signedIn ? 'Alex Rivera' : 'Not signed in'), findsOneWidget);
      expect(find.text("Your account doesn't include a name."), findsNothing);
      final card = find.byTooltip('Profile and account');
      expect(tester.getCenter(card).dx, greaterThan(tester.view.physicalSize.width / 2));
      await tester.tap(card);
      expect(actions, 1);
      expect(tester.takeException(), isNull);
    });
  }
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
        find.textContaining('Turning off stops future sharing and clears unsent counts'),
        findsNothing,
      );
      await tester.tap(find.text('What these counts include'));
      await tester.pumpAndSettle();
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

  testWidgets('device feedback accepts text without sign-in', (tester) async {
    final (store, _) = await fixture(tester);
    var transportCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GardenScreen(
          store: store,
          deviceGuest: true,
          testDisableServices: true,
          feedbackSender: (_) async {
            transportCalls++;
            return true;
          },
        ),
      ),
    );
    await settleDatabase(tester);
    await tester.tap(find.byTooltip('Help us grow'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Signed-out feedback');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Send feedback'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send feedback'));
    await settleDatabase(tester);
    expect(
      find.text('Saved on this device — not sent to the team.'),
      findsOneWidget,
    );
    expect(find.text('Received by the team.'), findsNothing);
    expect(find.text('Retry sending'), findsNothing);
    expect(transportCalls, 0);
    final rows = await store.voice();
    expect(rows, hasLength(1));
    expect(rows.single['body'], 'Signed-out feedback');
    expect(rows.single['status'], isNot('received'));
  });

  testWidgets('feedback controller survives the closing route transition', (
    tester,
  ) async {
    final (store, _) = await fixture(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: GardenScreen(store: store, testDisableServices: true),
      ),
    );
    await settleDatabase(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Help us grow'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Your feedback');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.enterText(field, 'Unsent synthetic feedback');
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Send feedback'), findsNothing);
    }
  });
}
import 'dart:convert';
import 'dart:io';
