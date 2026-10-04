import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/services/invitation_intent.dart';
import 'package:bloomstep/services/invitation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

void main() {
  final token = base64Url
      .encode(List<int>.generate(32, (i) => i))
      .replaceAll('=', '');
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
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(store: store, invitationService: service),
        ),
      );
      await waitInvitation(tester, find.text('Plant a habit'));
      await tester.tap(find.byTooltip('Invite a friend'));
      await waitInvitation(tester, find.text('Show QR'));
      expect(requests, isEmpty);
      expect(nativeCalls, isEmpty);
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
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            invitationInbox: inbox,
            invitationService: service,
          ),
        ),
      );
      await waitInvitation(tester, find.text('Decline invitation'));
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
          return http.Response(
            jsonEncode({
              'invitations': [],
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
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
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
      await tester.tap(find.text('Review shared recipe before planting'));
      await waitInvitation(tester, find.text('Open recipe builder'));
      expect(find.textContaining('After I tea'), findsOneWidget);
      await tester.tap(find.text('Open recipe builder'));
      await waitInvitation(tester, find.text('Save recipe'));
      expect(find.text('tea'), findsOneWidget);
      expect((await tester.runAsync(store.habits))!, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
