import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/features/garden/invitation_dialog.dart';
import 'package:bloomstep/services/invitation_intent.dart';
import 'package:bloomstep/services/invitation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloomstep/features/garden/plant_art.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bloomstep/app/theme.dart';

import 'support/visual_capture.dart';

Widget syntheticInvitationFrame(GlobalKey key, Widget home) => RepaintBoundary(
  key: key,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: BloomstepTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: Column(
        children: [
          const Material(
            child: Text('SYNTHETIC UI - mock invitation service, no sending'),
          ),
          Expanded(child: child!),
        ],
      ),
    ),
    home: home,
  ),
);

Future<void> waitInvitation(WidgetTester tester, Finder finder) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Invitation readiness timed out: $finder');
}

Future<void> waitInvitationCondition(
  WidgetTester tester,
  bool Function() ready,
) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 10)) {
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Invitation operation timed out.');
}

void main() {
  final token = base64Url
      .encode(List<int>.generate(32, (i) => i))
      .replaceAll('=', '');
  testWidgets('service rejection and native handoff failure show distinct safe retry errors', (tester) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'synthetic-failure-ui'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    var status = 503;
    var requests = 0;
    final service = InvitationService(
      store,
      tokenProvider: () async => 'synthetic',
      origin: 'https://approved.example',
      client: MockClient((request) async {
        requests++;
        final body = jsonDecode(request.body) as Map;
        return http.Response(status == 200 ? jsonEncode({
          'invitationId': body['requestId'],
          'token': token,
          'channel': body['channel'],
          'recipeCard': body['recipeCard'],
          'expiresAt': DateTime.now().toUtc()
              .add(const Duration(days: 7)).toIso8601String(),
        }) : 'private server details', status);
      }),
    );
    const bridge = MethodChannel('bloomstep/native_share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (_) async {
          throw PlatformException(code: 'private', message: 'private platform details');
        });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, null));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      TextButton(onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => InvitationDialog(
          store: store, service: service, hasRecipes: false,
          chooseCard: () async => null,
        ),
      ), child: const Text('Open invitation')),
    )));
    await tester.tap(find.text('Open invitation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    final backendError = invitationErrorMessage(const InvitationFailure(
      InvitationFailureKind.backend, InvitationPhase.creation, httpStatus: 503,
    ));
    await waitInvitation(tester, find.text(backendError));
    expect(requests, 1);
    expect(find.textContaining('private'), findsNothing);
    status = 200;
    await tester.ensureVisible(find.text('More ways to invite'));
    await tester.tap(find.text('More ways to invite'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Windows share'));
    await tester.tap(find.text('Windows share'));
    final handoffError = invitationErrorMessage(
      StateError('ignored'), phase: InvitationPhase.handoff,
    );
    await waitInvitation(tester, find.text(handoffError));
    expect(find.text('Windows share panel requested'), findsNothing);
    expect(requests, 2);
    await tester.ensureVisible(find.text('Windows share'));
    await tester.tap(find.text('Windows share'));
    await waitInvitation(tester, find.text(handoffError));
    expect(requests, 2, reason: 'Retry reuses the server receipt after handoff failure.');
    expect(find.textContaining('private platform'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('visual invitation contract: quiet, private and dismissible', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'synthetic-visual-invite'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    var requests = 0;
    final service = InvitationService(
      store,
      tokenProvider: () async => 'synthetic',
      origin: 'https://approved.example',
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 503);
      }),
    );
    await loadVisualFonts(tester);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      syntheticInvitationFrame(
        boundary,
        GardenScreen(store: store, invitationService: service),
      ),
    );
    await waitInvitation(tester, find.text('Plant a habit'));
    await tester.tap(find.byTooltip('Invite a friend'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.byType(PlantArt)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: dialog, matching: find.byType(FilledButton)),
      findsOneWidget,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('Copy link')))
          .style
          .fontFamily,
      'Segoe UI',
      reason: 'Primary-action emphasis must preserve the application typeface.',
    );
    expect(
      find.text(
        'Anyone with the link can open it. No one is contacted automatically.',
      ),
      findsOneWidget,
    );
    expect(find.text('Email invite').hitTestable(), findsNothing);
    await tester.ensureVisible(find.text('Privacy and link details'));
    await tester.tap(find.text('Privacy and link details'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Optional analytics is off by default; when enabled, Budlark records '
        'invitation creation and the sharing method. Recipe cards show only '
        'the fields you approve—not your name, email, or practice history.',
      ),
      findsOneWidget,
    );
    expect(requests, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'sharing creates distinct attributed codes only on gestures and native invokes real bridge',
    (tester) async {
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'invite-share-ui'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.binding.setSurfaceSize(const Size(1100, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <Map>[];
      final nativeCalls = <MethodCall>[];
      const channel = MethodChannel('bloomstep/native_share');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeCalls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = InvitationService(
        store,
        tokenProvider: () async => 'ciam',
        origin: 'https://approved.example/api',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          requests.add(body);
          expect(body.keys.toSet(), {'requestId', 'channel'});
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
      await loadVisualFonts(tester);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        syntheticInvitationFrame(
          boundary,
          GardenScreen(store: store, invitationService: service),
        ),
      );
      await waitInvitation(tester, find.text('Plant a habit'));
      await tester.tap(find.byTooltip('Invite a friend'));
      await waitInvitation(tester, find.text('More ways to invite'));
      expect(requests, isEmpty);
      expect(nativeCalls, isEmpty);
      await tester.tap(find.text('More ways to invite'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show QR'));
      await waitInvitation(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Server invitation QR code',
        ),
      );
      expect(requests.single['channel'], 'qr');
      expect(nativeCalls, isEmpty);
      await waitInvitation(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is FilledButton &&
              widget.key == const ValueKey('invite-copy') &&
              widget.onPressed != null,
        ),
      );
      await tester.tap(find.text('Windows share'));
      final watch = Stopwatch()..start();
      while (nativeCalls.isEmpty &&
          watch.elapsed < const Duration(seconds: 10)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(requests.last['channel'], 'native');
      expect(nativeCalls.single.method, 'share');
      expect(Uri.parse(nativeCalls.single.arguments['url']).queryParameters, {
        'invite': token,
        'channel': 'native',
      });
      expect((await tester.runAsync(store.habits))!, isEmpty);
      await waitInvitation(
        tester,
        find.byWidgetPredicate(
          (widget) =>
              widget is FilledButton &&
              widget.key == const ValueKey('invite-copy') &&
              widget.onPressed != null,
        ),
      );
      await tester.pump();
      await captureVisual(tester, boundary, 'invite-native-requested');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    },
  );

  testWidgets(
    'persisted invitation asks before redeem, decline never requests',
    (tester) async {
      final directory = Directory(
        'invitation-ui-${DateTime.now().microsecondsSinceEpoch}',
      );
      final inbox = InvitationInbox(directory.path);
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'invite-ui'),
      ))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          await store.close();
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        inbox.dispose();
      });
      var requests = 0;
      final service = InvitationService(
        store,
        tokenProvider: () async => 'ciam',
        origin: 'https://approved.example',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      await tester.runAsync(
        () => inbox.save(InvitationIntent(token, 'native')),
      );
      await loadVisualFonts(tester);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        syntheticInvitationFrame(
          boundary,
          GardenScreen(
            store: store,
            invitationInbox: inbox,
            invitationService: service,
          ),
        ),
      );
      await waitInvitation(tester, find.text('Decline invitation'));
      await tester.pumpAndSettle();
      await captureVisual(tester, boundary, 'incoming-invitation');
      expect(requests, 0);
      await tester.ensureVisible(find.text('Decline invitation'));
      await tester.tap(find.text('Decline invitation'));
      for (
        var i = 0;
        i < 10 && find.text('Decline invitation').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Accept invitation'), findsNothing);
      expect(await tester.runAsync(inbox.read), isNull);
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'accept sends no channel override, shows server cosmetic and requires card confirmation',
    (tester) async {
      final directory = Directory(
        'invitation-accept-ui-${DateTime.now().microsecondsSinceEpoch}',
      );
      final inbox = InvitationInbox(directory.path);
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'invite-accept-ui'),
      ))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          await store.close();
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        inbox.dispose();
      });
      await tester.binding.setSurfaceSize(const Size(1100, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now().toUtc();
      final card = {
        'explicitChoice': true,
        'templateCategory': 'calm',
        'aspiration': 'Calm',
        'anchor': 'tea',
        'behavior': 'breathe',
        'celebration': 'smile',
        'species': 'Fern',
      };
      var redeemed = 0;
      var statusRequests = 0;
      final service = InvitationService(
        store,
        tokenProvider: () async => 'ciam',
        origin: 'https://approved.example',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/redeem')) {
            redeemed++;
            expect((jsonDecode(request.body) as Map).keys.toSet(), {
              'requestId',
              'token',
            });
            return http.Response(
              jsonEncode({
                'invitationId': '11111111-1111-4111-8111-111111111111',
                'channel': 'email',
                'acceptedAt': now.toIso8601String(),
                'expiresAt': now
                    .add(const Duration(days: 30))
                    .toIso8601String(),
                'recipeCard': card,
                'status': 'accepted',
              }),
              200,
            );
          }
          statusRequests++;
          return http.Response(
            jsonEncode({
              'invitations': [
                {
                  'invitationId': '22222222-2222-4222-8222-222222222222',
                  'direction': 'outgoing',
                  'channel': 'link',
                  'acceptedAt': null,
                  'expiresAt': now
                      .add(const Duration(days: 30))
                      .toIso8601String(),
                  'status': 'created',
                },
              ],
              'rewards': [
                {
                  'id': 'a' * 64,
                  'cosmetic': 'rare_flower',
                  'grantedAt': now.toIso8601String(),
                },
              ],
              'definition': 'Cosmetic only.',
            }),
            200,
          );
        }),
      );
      await tester.runAsync(() => inbox.save(InvitationIntent(token, 'link')));
      await loadVisualFonts(tester);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        syntheticInvitationFrame(
          boundary,
          GardenScreen(
            store: store,
            invitationInbox: inbox,
            invitationService: service,
          ),
        ),
      );
      await waitInvitation(tester, find.text('Accept invitation'));
      expect(redeemed, 0);
      await tester.tap(find.text('Accept invitation'));
      await waitInvitation(
        tester,
        find.text('Rare flower — server-granted cosmetic'),
      );
      expect(redeemed, 1);
      expect((await tester.runAsync(store.habits))!, isEmpty);
      expect(find.text('Refresh invitation status'), findsOneWidget);
      expect(find.text('Refresh invitation receipts'), findsNothing);
      expect(find.text('Invitation status'), findsOneWidget);
      expect(find.text('Private invitation receipts'), findsNothing);
      expect(statusRequests, 1);
      await tester.tap(find.text('Refresh invitation status'));
      await waitInvitationCondition(tester, () => statusRequests == 2);
      expect(statusRequests, 2);
      await tester.pumpAndSettle();
      await captureVisual(tester, boundary, 'incoming-accepted-cosmetic');
      await tester.tap(find.text('Review shared recipe before planting'));
      await waitInvitation(tester, find.text('Open recipe builder'));
      expect(find.textContaining('After I tea'), findsOneWidget);
      await tester.pumpAndSettle();
      await captureVisual(tester, boundary, 'incoming-recipe-review');
      await tester.tap(find.text('Open recipe builder'));
      await waitInvitation(tester, find.text('Save recipe'));
      expect(find.text('tea'), findsOneWidget);
      expect((await tester.runAsync(store.habits))!, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
