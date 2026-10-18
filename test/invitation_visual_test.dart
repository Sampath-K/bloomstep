import 'dart:async';
import 'dart:convert';

import 'package:bloomstep/app/theme.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/invitation_dialog.dart';
import 'package:bloomstep/services/invitation_service.dart';
import 'package:bloomstep/services/experience_experiments.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/visual_capture.dart';
import 'invitation_widget_test.dart'
    show waitInvitation, syntheticInvitationFrame;

class _SyntheticCandidate implements ExperienceAssignmentProvider {
  @override
  String get id => 'synthetic_candidate';
  @override
  ExperienceArm? evaluate(ExperienceConfig config, String subject) =>
      ExperienceArm.candidate;
}

void main() {
  testWidgets(
    'real invitation uses replaceable rendered-only consented copy seam',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final now = DateTime.utc(2026, 10, 15);
      final store = (await tester.runAsync(
        () => GardenStore.open(
          ':memory:',
          'synthetic-dialog-study',
          clock: () => now,
        ),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.runAsync(() => store.setSetting('analytics', 'true'));
      final experiments = ExperienceExperiments(
        store,
        config: ExperienceConfig.synthetic(
          ExperienceSurface.invitationHeading,
          startAt: now,
        ),
        provider: _SyntheticCandidate(),
        clock: () => now,
      );
      var requests = 0;
      final service = InvitationService(
        store,
        tokenProvider: () async => 'synthetic',
        origin: 'https://synthetic.example',
        clock: () => now,
        client: MockClient((request) async {
          requests++;
          final body = jsonDecode(request.body) as Map;
          return http.Response(
            jsonEncode({
              'invitationId': body['requestId'],
              'token': base64Url
                  .encode(List<int>.filled(32, 0))
                  .replaceAll('=', ''),
              'channel': body['channel'],
              'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
              'recipeCard': null,
            }),
            200,
          );
        }),
      );
      final key = GlobalKey();
      await loadVisualFonts(tester);
      await tester.pumpWidget(
        syntheticInvitationFrame(
          key,
          InvitationDialog(
            store: store,
            service: service,
            experiments: experiments,
            hasRecipes: false,
            reducedMotion: true,
            chooseCard: () async => null,
          ),
        ),
      );
      await waitInvitation(tester, find.text('Share a small beginning'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await captureVisual(tester, key, 'invite-SYNTHETIC-candidate');
      Future<List<String>> outcomes() async =>
          ((await store.export())['events'] as List)
              .cast<Map>()
              .where((event) => event['name'] == 'experience_observation')
              .map(
                (event) =>
                    (jsonDecode(event['properties'] as String)
                            as Map)['experienceOutcome']
                        as String,
              )
              .toList();
      expect(await tester.runAsync(outcomes), ['rendered']);
      expect(requests, 0);
      await tester.tap(find.text('Copy link'));
      await waitInvitation(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is FilledButton &&
              widget.key == const ValueKey('invite-copy') &&
              widget.onPressed != null,
        ),
      );
      expect(await tester.runAsync(outcomes), ['rendered', 'task_completed']);
      expect(requests, 1);
      await tester.runAsync(() => store.setSetting('analytics', 'false'));
      await tester.pumpAndSettle();
      expect(find.text('A little growth, together'), findsOneWidget);
      expect(await tester.runAsync(outcomes), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final variant in [
    (name: 'desktop', size: const Size(1100, 1000), scale: 1.0, dark: false),
    (name: 'large', size: const Size(420, 820), scale: 2.0, dark: false),
    (name: 'small', size: const Size(640, 480), scale: 1.0, dark: false),
    (name: 'dark', size: const Size(1100, 1000), scale: 1.0, dark: true),
  ]) {
    testWidgets('invitation rendered states ${variant.name}', (tester) async {
      await tester.binding.setSurfaceSize(variant.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadVisualFonts(tester);
      final semantics = tester.ensureSemantics();
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'synthetic-invite-${variant.name}'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      String? copied;
      var clipboardFails = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (clipboardFails) {
              throw PlatformException(code: 'synthetic_clipboard_failure');
            }
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final key = GlobalKey();
      var failing = true;
      var requests = 0;
      Completer<http.Response>? pending;
      final token = base64Url
          .encode(List<int>.generate(32, (i) => i))
          .replaceAll('=', '');
      final service = InvitationService(
        store,
        tokenProvider: () async => 'synthetic-not-a-credential',
        origin: 'https://synthetic.example',
        client: MockClient((request) async {
          requests++;
          if (pending != null) return pending.future;
          if (failing) return http.Response('{}', 503);
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
              'recipeCard': null,
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: variant.dark
                ? BloomstepTheme.dark()
                : BloomstepTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(variant.scale),
                disableAnimations: true,
              ),
              child: Column(
                children: [
                  const Material(
                    child: Text('SYNTHETIC UI - mock server, no sending'),
                  ),
                  Expanded(child: child!),
                ],
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    autofocus: true,
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => InvitationDialog(
                        service: service,
                        store: store,
                        hasRecipes: false,
                        chooseCard: () async => throw StateError(
                          'Empty garden must not open picker',
                        ),
                      ),
                    ),
                    child: const Text('Open synthetic invite'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open synthetic invite'));
      await tester.pumpAndSettle();
      await captureVisual(tester, key, 'invite-${variant.name}-ready');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(requests, 0);
      expect(find.text('Copy link').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Include a recipe? Optional'));
      await tester.tap(find.text('Include a recipe? Optional'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text(
          'Plant a habit first to share a recipe. You can still invite with a link.',
        ),
      );
      await captureVisual(tester, key, 'invite-${variant.name}-empty-recipe');
      await tester.tap(find.text('Include a recipe? Optional'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Copy link'));
      await tester.tap(find.text('Copy link'));
      await waitInvitation(
        tester,
        find.text(
          invitationErrorMessage(
            const InvitationFailure(
              InvitationFailureKind.backend,
              InvitationPhase.creation,
              httpStatus: 503,
            ),
            includeSupportCode: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text(
          invitationErrorMessage(
            const InvitationFailure(
              InvitationFailureKind.backend,
              InvitationPhase.creation,
              httpStatus: 503,
            ),
            includeSupportCode: false,
          ),
        ),
      );
      await captureVisual(tester, key, 'invite-${variant.name}-failure');
      expect(find.text('Link copied'), findsNothing);
      failing = false;
      await tester.ensureVisible(find.text('More ways to invite'));
      await tester.tap(find.text('More ways to invite'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show QR'));
      await captureVisual(tester, key, 'invite-${variant.name}-methods');
      await tester.tap(find.text('Show QR'));
      await waitInvitation(tester, find.text('Your QR is ready'));
      await waitInvitation(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is FilledButton &&
              widget.key == const ValueKey('invite-copy') &&
              widget.onPressed != null,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Your QR is ready'));
      await captureVisual(tester, key, 'invite-${variant.name}-qr');
      expect(
        find.bySemanticsLabel('Server invitation QR code'),
        findsOneWidget,
      );
      expect(find.text('Link copied'), findsNothing);
      await tester.ensureVisible(find.text('Privacy and link details'));
      await tester.tap(find.text('Privacy and link details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SelectableText));
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        'https://synthetic.example/?invite=$token&channel=qr',
      );
      await captureVisual(tester, key, 'invite-${variant.name}-details');
      await tester.ensureVisible(find.text('Copy link'));
      await tester.tap(find.text('Copy link'));
      await waitInvitation(tester, find.text('Link copied'));
      await waitInvitation(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is FilledButton &&
              widget.key == const ValueKey('invite-copy') &&
              widget.onPressed != null,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Link copied'));
      await captureVisual(tester, key, 'invite-${variant.name}-copied');
      expect(copied, 'https://synthetic.example/?invite=$token&channel=link');
      final createdRequests = requests;
      await waitInvitation(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is FilledButton &&
              widget.key == const ValueKey('invite-copy') &&
              widget.onPressed != null,
        ),
      );
      await tester.ensureVisible(find.text('Copy link'));
      await tester.tap(find.text('Copy link'));
      await waitInvitation(
        tester,
        find.textContaining('Cached existing invitation'),
      );
      await tester.pumpAndSettle();
      expect(requests, createdRequests);
      await waitInvitation(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is FilledButton &&
              widget.key == const ValueKey('invite-copy') &&
              widget.onPressed != null,
        ),
      );
      clipboardFails = true;
      await tester.tap(find.text('Copy link'));
      await waitInvitation(
        tester,
        find.text(
          invitationErrorMessage(
            StateError('synthetic clipboard'),
            phase: InvitationPhase.handoff,
            includeSupportCode: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Link copied'), findsNothing);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        'invite-handoff-unknown',
      );
      expect(find.text('Copy support info'), findsOneWidget);
      expect(find.textContaining('https://synthetic.example/'), findsNothing);
      expect(requests, createdRequests);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(InvitationDialog), findsNothing);
      // Escape restores focus to the invoker; Enter opens it again.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(InvitationDialog), findsOneWidget);
      pending = Completer<http.Response>();
      await tester.ensureVisible(find.text('More ways to invite'));
      await tester.tap(find.text('More ways to invite'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Email invite'));
      await tester.tap(find.text('Email invite'));
      await waitInvitation(tester, find.text('Preparing your invitation'));
      await tester.pump(const Duration(milliseconds: 100));
      await captureVisual(tester, key, 'invite-${variant.name}-working');
      final before = requests;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(requests, before);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      pending.complete(http.Response('{}', 503));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InvitationDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }
}
