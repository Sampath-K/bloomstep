import 'dart:convert';
import 'dart:async';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/services/invitation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late GardenStore store;
  final now = DateTime.utc(2026, 10, 4);
  final token = base64Url
      .encode(List<int>.generate(32, (i) => i))
      .replaceAll('=', '');
  setUp(() async => store = await GardenStore.open(':memory:', 'invite-a'));
  tearDown(() => store.close());
  InvitationService service(MockClient client) => InvitationService(
    store,
    tokenProvider: () async => 'real-ciam-token',
    client: client,
    origin: 'https://approved.example/api',
    clock: () => now,
  );

  test('create persists identical retry IDs, custom auth and offline existing links', () async {
    final requests = <Map<String, dynamic>>[];
    var fail = true;
    final api = service(
      MockClient((request) async {
        expect(request.url.path, '/api/invitations');
        expect(
          request.headers['X-Bloomstep-Authorization'],
          'Bearer real-ciam-token',
        );
        expect(request.headers.containsKey('Authorization'), isFalse);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        expect(body.keys.toSet(), {'requestId', 'channel'});
        if (fail) return http.Response('{"error":"Offline"}', 503);
        return http.Response(
          jsonEncode({
            'invitationId': body['requestId'],
            'token': token,
            'channel': body['channel'],
            'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
            'recipeCard': null,
          }),
          200,
        );
      }),
    );
    await expectLater(api.create('link'), throwsStateError);
    fail = false;
    final created = await api.create('link');
    expect(requests[0], requests[1]);
    expect(created.cached, isFalse);
    fail = true;
    final cached = await api.create('link');
    expect(cached.cached, isTrue);
    expect(requests, hasLength(2));
    expect(api.webUri(cached).queryParameters, {
      'invite': token,
      'channel': 'link',
    });
    await expectLater(api.create('email'), throwsStateError);
    expect((await store.syncPayload())['settings'], isEmpty);
    final exported = await store.export();
    expect(jsonEncode(exported), isNot(contains(token)));
    expect(exported['invitationReceipts'], isNotNull);
  });

  test('redeem uses server attribution and emits acceptance only once after response', () async {
    await store.setSetting('analytics', 'true');
    final requests = <Object>[];
    final api = service(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        requests.add(body);
        expect(body.keys.toSet(), {'requestId', 'token'});
        return http.Response(
          jsonEncode({
            'invitationId': '11111111-1111-4111-8111-111111111111',
            'channel': 'email',
            'acceptedAt': now.toIso8601String(),
            'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
            'recipeCard': null,
            'status': 'accepted',
          }),
          200,
        );
      }),
    );
    expect((await api.redeem(token)).channel, 'email');
    await api.redeem(token);
    expect(requests[0], requests[1]);
    final events = (await store.syncPayload())['events'] as List;
    expect(events.where((r) => r['name'] == 'invite_accepted'), hasLength(1));
    expect(
      events.singleWhere(
        (r) => r['name'] == 'invite_accepted',
      )['properties']['channel'],
      'email',
    );
    expect((await store.export())['invitationReceipts'], isNotNull);
  });

  test('rewards are server status only; account switch/deletion erases private cache', () async {
    final api = service(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'invitations': [],
            'rewards': [
              {
                'id': 'a' * 64,
                'cosmetic': 'rare_flower',
                'grantedAt': now.toIso8601String(),
              },
            ],
            'definition': 'Cosmetic only; first positive practice.',
          }),
          200,
        ),
      ),
    );
    final status = await api.refreshStatus();
    expect(status.rewards, hasLength(1));
    expect((await api.cachedStatus())!.rewards, hasLength(1));
    await store.switchAccount('invite-b');
    expect(await api.cachedStatus(), isNull);
    await store.switchAccount('invite-a');
    await store.deleteLocalAccount();
    expect(await api.cachedStatus(), isNull);
  });

  test('failed acceptance is persisted across disk reopen; only HTTP200 can observe acceptance', () async {
    final path = 'invite-retry-${DateTime.now().microsecondsSinceEpoch}.db';
    var disk = await GardenStore.open(path, 'durable-invite');
    final payloads = <Map>[];
    var online = false;
    final client = MockClient((request) async {
      payloads.add(jsonDecode(request.body) as Map);
      if (!online) return http.Response('', 500);
      return http.Response(
        jsonEncode({
          'invitationId': '11111111-1111-4111-8111-111111111111',
          'channel': 'qr',
          'acceptedAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
          'recipeCard': null,
          'status': 'accepted',
        }),
        200,
      );
    });
    InvitationService api() => InvitationService(
      disk,
      client: client,
      tokenProvider: () async => 'ciam',
      clock: () => now,
      origin: 'https://approved.example',
    );
    try {
      await expectLater(api().redeem(token), throwsStateError);
      expect(
        ((await disk.syncPayload())['events'] as List).where(
          (r) => r['name'] == 'invite_accepted',
        ),
        isEmpty,
      );
      await disk.close();
      disk = await GardenStore.open(path, 'durable-invite');
      online = true;
      final receipt = await api().redeem(token);
      expect(receipt.channel, 'qr');
      expect(payloads[0], payloads[1]);
      expect(
        ((await disk.syncPayload())['events'] as List).where(
          (r) => r['name'] == 'invite_accepted',
        ),
        isEmpty,
      );
      expect((await disk.export())['invitationReceipts'], isNotNull);
    } finally {
      await disk.close();
      await databaseFactoryFfi.deleteDatabase(path);
    }
  });

  test(
    'recipe snapshots are explicit immutable and independent of JSON key order',
    () async {
      final card = <String, dynamic>{
        'explicitChoice': true,
        'templateCategory': 'calm',
        'aspiration': 'Calm',
        'anchor': 'tea',
        'behavior': 'breathe',
        'celebration': 'smile',
        'species': 'Fern',
      };
      final entered = Completer<void>();
      final release = Completer<void>();
      final api = service(
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          entered.complete();
          await release.future;
          expect(body['recipeCard']['anchor'], 'tea');
          final reverse = Map<String, dynamic>.fromEntries(
            (body['recipeCard'] as Map<String, dynamic>).entries
                .toList()
                .reversed,
          );
          return http.Response(
            jsonEncode({
              'invitationId': body['requestId'],
              'token': token,
              'channel': 'link',
              'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
              'recipeCard': reverse,
            }),
            200,
          );
        }),
      );
      final creating = api.create('link', recipeCard: card);
      await entered.future;
      card['anchor'] = 'private changed text';
      release.complete();
      expect((await creating).recipeCard!['anchor'], 'tea');
    },
  );

  test('expiry never returns an expired cached link and status export is private typed data', () async {
    var date = now;
    var requests = 0;
    final api = InvitationService(
      store,
      tokenProvider: () async => 'ciam',
      origin: 'https://approved.example',
      clock: () => date,
      client: MockClient((request) async {
        requests++;
        if (request.url.path.endsWith('/status')) {
          expect(request.url.queryParameters, {'export': 'true'});
          return http.Response(
            jsonEncode({
              'invitations': [],
              'rewards': [],
              'definition': 'Cosmetic only.',
              'sharedRecipes': [],
            }),
            200,
          );
        }
        if (requests > 1) return http.Response('', 503);
        final body = jsonDecode(request.body) as Map;
        return http.Response(
          jsonEncode({
            'invitationId': body['requestId'],
            'token': token,
            'channel': 'link',
            'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
            'recipeCard': null,
          }),
          200,
        );
      }),
    );
    await api.create('link');
    date = now.add(const Duration(days: 7));
    await expectLater(api.create('link'), throwsStateError);
    expect(requests, 2);
    final exported = await api.refreshStatus(export: true);
    expect(exported.json['sharedRecipes'], isEmpty);
    expect(await store.setting('rare_flower'), isNull);
    await store.setSetting('invitationState', '{}');
    await expectLater(api.cachedStatus(), throwsFormatException);
  });

  test(
    'malformed rewards and oversized responses cannot grant a cosmetic',
    () async {
      for (final response in [
        http.Response('x' * 65537, 200),
        http.Response(
          jsonEncode({
            'invitations': [],
            'rewards': [
              {
                'id': 'a' * 64,
                'cosmetic': 'rare_flower',
                'grantedAt': now.toIso8601String(),
                'account': 'other',
              },
            ],
            'definition': 'Invalid private field',
          }),
          200,
        ),
      ]) {
        final api = service(MockClient((_) async => response));
        await expectLater(api.refreshStatus(), throwsFormatException);
        expect(await api.cachedStatus(), isNull);
      }
    },
  );

  test(
    'unsafe tokens, cards, responses and account changes fail closed',
    () async {
      var called = false;
      final api = service(
        MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(api.redeem('A' * 42 + 'B'), throwsFormatException);
      await expectLater(
        api.create('link', recipeCard: {'explicitChoice': false}),
        throwsFormatException,
      );
      expect(called, isFalse);
      await expectLater(api.create('link'), throwsFormatException);
      final switched = service(
        MockClient((_) async {
          await store.switchAccount('invite-b');
          return http.Response('{}', 200);
        }),
      );
      await expectLater(switched.refreshStatus(), throwsStateError);
      expect(await store.setting('invitationState'), isNull);
    },
  );
}
