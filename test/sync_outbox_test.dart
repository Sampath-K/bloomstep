import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:bloomstep/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Identity extends IdentityService {
  _Identity(String id) {
    account = id;
  }
  @override
  Future<String> accessToken() async => 'test-token';
  @override
  Future<void> signOut() async {
    account = null;
  }
}

Future<void> _plant(GardenStore store) async {
  await store.plant(
    aspiration: 'Calm',
    anchor: 'coffee',
    behavior: 'breathe',
    celebration: 'smile',
    species: 'Fern',
  );
}

Map<String, dynamic> _emptyGarden() => {
  'habits': [],
  'checkins': [],
  'reflections': [],
  'voice': [],
  'settings': [],
  'acknowledgedEvents': [],
};

void main() {
  test(
    'sync surfaces bounded API errors without losing pending records',
    () async {
      final store = await GardenStore.open(':memory:', 'quota');
      addTearDown(store.close);
      await _plant(store);
      for (final status in [429, 409, 503]) {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'Engineering preview quota reached.'}),
            status,
          ),
        );
        try {
          await expectLater(
            SyncService(_Identity('quota'), store, client: client).sync(),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('HTTP $status'),
                  contains('Engineering preview quota reached.'),
                  contains('Local changes remain'),
                ),
              ),
            ),
          );
          expect((await store.syncPayload())['habits'], hasLength(1));
        } finally {
          client.close();
        }
      }
      for (final body in [
        'invalid JSON',
        '{"error":42}',
        jsonEncode({'error': 'x' * 2000}),
      ]) {
        final client = MockClient((_) async => http.Response(body, 503));
        try {
          await expectLater(
            SyncService(_Identity('quota'), store, client: client).sync(),
            throwsA(
              isA<StateError>().having(
                (e) => e.message.length,
                'bounded message',
                lessThan(700),
              ),
            ),
          );
        } finally {
          client.close();
        }
      }
    },
  );

  test(
    'opt-out during garden upload prevents later queued telemetry upload',
    () async {
      final store = await GardenStore.open(':memory:', 'consent-sync');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      await _plant(store);
      var posts = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          final payload = jsonDecode(request.body) as Map;
          expect(payload['events'], isEmpty);
          await store.setSetting('analytics', 'false');
        }
        return http.Response(jsonEncode(_emptyGarden()), 200);
      });
      addTearDown(client.close);
      await SyncService(
        _Identity('consent-sync'),
        store,
        client: client,
      ).sync();
      expect(posts, 1);
      expect((await store.export())['events'], isEmpty);
    },
  );
  test(
    'analytics opt-out clears queued events and their sync metadata',
    () async {
      final store = await GardenStore.open(':memory:', 'consent');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      await store.track('weekly_reflection');
      await store.track('rating_prompted');
      final submitted = await store.syncPayload();
      expect(submitted['events'], hasLength(2));
      await store.acknowledgeSync(submitted);
      await store.setSetting('analytics', 'false');
      expect((await store.export())['events'], isEmpty);
      await store.acknowledgeSync(submitted);
      await store.track('weekly_reflection');
      expect((await store.syncPayload())['events'], isEmpty);
      await store.setSetting('analytics', 'true');
      await store.track('rating_prompted');
      expect((await store.syncPayload())['events'], hasLength(1));
    },
  );

  test(
    'acknowledgments are durable snapshots, not acknowledgments of edits',
    () async {
      final path = 'test-outbox-${DateTime.now().microsecondsSinceEpoch}.db';
      var store = await GardenStore.open(path, 'a');
      addTearDown(() async {
        await store.close();
        await databaseFactoryFfi.deleteDatabase(path);
      });
      await _plant(store);
      await store.setSetting('weeklyLast', '2026-10-04T00:00:00.000Z');
      final submitted = await store.syncPayload();
      final h = (await store.habits()).single;
      await store.edit(
        h,
        anchor: 'tea',
        behavior: h.behavior,
        celebration: h.celebration,
      );
      await store.acknowledgeSync(submitted);
      expect((await store.syncPayload())['habits'], hasLength(1));
      expect((await store.syncPayload())['settings'], isEmpty);
      await store.acknowledgeSync(await store.syncPayload());
      await store.close();
      store = await GardenStore.open(path, 'a');
      expect(
        (await store.syncPayload()).values.every((v) => (v as List).isEmpty),
        isTrue,
      );
      await store.switchAccount('b');
      await _plant(store);
      expect((await store.syncPayload())['habits'], hasLength(1));
      await store.deleteLocalAccount();
      await store.switchAccount('a');
      expect((await store.syncPayload())['habits'], isEmpty);
      await store.deleteLocalAccount();
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(path);
      expect(
        (await db.rawQuery(
          'SELECT count(*) AS n FROM sync_state WHERE account = ?',
          ['a'],
        )).single['n'],
        0,
      );
      await db.close();
      store = await GardenStore.open(path, 'a');
      await _plant(store);
      expect((await store.syncPayload())['habits'], hasLength(1));
    },
  );

  test('partial first sync resumes and steady sync only downloads', () async {
    final path = 'test-partial-${DateTime.now().microsecondsSinceEpoch}.db';
    var store = await GardenStore.open(path, 'partial');
    addTearDown(() async {
      await store.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });

    for (var i = 0; i < 26; i++) {
      await _plant(store);
    }
    final h = (await store.habits()).first;
    await store.checkIn(h.id, CheckInResult.did);
    var fail = true;
    final uploads = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        final payload = jsonDecode(request.body) as Map;
        final table = payload.keys.singleWhere(
          (key) => (payload[key] as List).isNotEmpty,
        );
        uploads.add(table as String);
        if (uploads.length == 2 && fail) {
          return http.Response('unavailable', 503);
        }
      }
      return http.Response(jsonEncode(_emptyGarden()), 200);
    });
    addTearDown(client.close);
    var service = SyncService(_Identity('partial'), store, client: client);
    await expectLater(service.sync(), throwsStateError);
    expect(uploads, ['habits', 'habits']);
    await store.close();
    store = await GardenStore.open(path, 'partial');
    service = SyncService(_Identity('partial'), store, client: client);
    fail = false;
    uploads.clear();
    await service.sync();
    expect(uploads, ['habits', 'checkins']);
    uploads.clear();
    await service.sync();
    expect(uploads, isEmpty);
  });

  test(
    'HTTP success never acknowledges concurrent recipe edits or undo',
    () async {
      final store = await GardenStore.open(':memory:', 'concurrent');
      addTearDown(store.close);
      await _plant(store);
      final h = (await store.habits()).single;
      await store.checkIn(h.id, CheckInResult.did);
      final before = await store.syncPayload();
      var edited = false;
      final client = MockClient((request) async {
        if (!edited && request.method == 'POST') {
          edited = true;
          await store.edit(
            h,
            anchor: 'tea',
            behavior: h.behavior,
            celebration: h.celebration,
          );
          await store.undo(h.id);
        }
        return http.Response(
          jsonEncode({
            ..._emptyGarden(),
            'habits': before['habits'],
            'checkins': before['checkins'],
          }),
          200,
        );
      });
      addTearDown(client.close);
      await SyncService(_Identity('concurrent'), store, client: client).sync();
      final pending = await store.syncPayload();
      expect((pending['habits'] as List).single['anchor'], 'tea');
      expect(pending['checkins'], hasLength(1));
      expect((pending['checkins'] as List).single['result'], isNull);
      expect(await store.eventCount(), 2);
    },
  );

  test(
    'cadence settings synchronize without shortening a claimed cooldown',
    () async {
      final store = await GardenStore.open(':memory:', 'cadence');
      addTearDown(store.close);
      const last = '2026-10-04T00:00:00.000Z';
      await store.setSetting('ratingPromptedAt', last);
      await store.setSetting('weeklyLast', last);
      await store.setSetting('ratingComebacks', '3');
      final payload = await store.syncPayload();
      expect((payload['settings'] as List).map((r) => r['key']), [
        'ratingPromptedAt',
        'weeklyLast',
      ]);
      await store.mergeSync({
        ..._emptyGarden(),
        'settings': [
          {
            'key': 'ratingPromptedAt',
            'value': '2026-10-01T00:00:00.000Z',
            'updated': '2027-01-01T00:00:00.000Z',
          },
        ],
      });
      expect(await store.setting('ratingPromptedAt'), last);
      await expectLater(
        store.mergeSync({
          ..._emptyGarden(),
          'settings': [
            {'key': 'weeklyLast', 'value': 'invalid', 'updated': last},
          ],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'server deletion clears local records and durable acknowledgments',
    () async {
      final store = await GardenStore.open(':memory:', 'deleted');
      addTearDown(store.close);
      await _plant(store);
      await store.acknowledgeSync(await store.syncPayload());
      final identity = _Identity('deleted');
      final client = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.headers['x-confirm-delete'], 'delete-my-garden');
        return http.Response('', 204);
      });
      addTearDown(client.close);
      await SyncService(identity, store, client: client).deleteAccount();
      expect(identity.account, isNull);
      expect(await store.habits(), isEmpty);
      expect(
        (await store.syncPayload()).values.every((v) => (v as List).isEmpty),
        isTrue,
      );
    },
  );

  test(
    'server imports do not echo, journals and feedback remain immutable',
    () async {
      final store = await GardenStore.open(':memory:', 'imports');
      addTearDown(store.close);
      await _plant(store);
      await store.submitVoice('Idea', 'mine');
      final submitted = await store.syncPayload();
      await store.acknowledgeSync(submitted);
      final h = Map<String, Object?>.from(
        (submitted['habits'] as List).single as Map,
      );
      final voice = Map<String, Object?>.from(
        (submitted['voice'] as List).single as Map,
      );
      final remote = {
        ..._emptyGarden(),
        'habits': [h],
        'checkins': [
          {
            'id': 'remote-event',
            'habitId': h['id'],
            'day': '2026-10-04',
            'result': 'did',
            'reason': null,
            'ts': '2026-10-04T00:00:00.000Z',
          },
        ],
        'voice': [
          {...voice, 'status': 'review', 'replies': '["Thank you"]'},
        ],
      };
      await store.mergeSync(remote);
      expect((await store.syncPayload())['checkins'], isEmpty);
      expect((await store.syncPayload())['voice'], isEmpty);
      expect((await store.voice()).single['status'], 'review');
      await store.mergeSync({
        ...remote,
        'checkins': [
          {...(remote['checkins'] as List).single as Map, 'result': 'notToday'},
        ],
      });
      expect((await store.habits()).single.practiceCount, 1);
      expect((await store.syncPayload())['checkins'], hasLength(1));
    },
  );

  test(
    'in-flight account switch or deletion cannot merge or acknowledge',
    () async {
      for (final delete in [false, true]) {
        final store = await GardenStore.open(':memory:', 'old');
        await _plant(store);
        final client = MockClient((request) async {
          if (delete) {
            await store.deleteLocalAccount();
          } else {
            await store.switchAccount('new');
          }
          return http.Response(
            jsonEncode({..._emptyGarden(), 'habits': []}),
            200,
          );
        });
        final service = SyncService(_Identity('old'), store, client: client);
        await expectLater(service.sync(), throwsStateError);
        expect(await store.habits(), isEmpty);
        if (!delete) {
          await store.switchAccount('old');
          expect((await store.syncPayload())['habits'], hasLength(1));
        }
        client.close();
        await store.close();
      }
    },
  );

  test('v1 and v2 databases migrate and reopen without losing pending records', () async {
    for (final version in [1, 2]) {
      final path =
          'test-migration-$version-'
          '${DateTime.now().microsecondsSinceEpoch}.db';
      // Create actual legacy schemas rather than a new-version fixture.
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onCreate: (db, _) async {
            await db.execute(
              "CREATE TABLE habits (id TEXT PRIMARY KEY, account TEXT NOT NULL, aspiration TEXT NOT NULL, anchor TEXT NOT NULL, behavior TEXT NOT NULL, celebration TEXT NOT NULL, species TEXT NOT NULL, stage INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active', updated TEXT NOT NULL)",
            );
            await db.execute(
              'CREATE TABLE checkins (id TEXT PRIMARY KEY, account TEXT NOT NULL, habitId TEXT NOT NULL, day TEXT NOT NULL, result TEXT, reason TEXT, ts TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE reflections (id TEXT PRIMARY KEY, account TEXT NOT NULL, habitId TEXT NOT NULL, items TEXT NOT NULL, score REAL NOT NULL, ts TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE voice (id TEXT PRIMARY KEY, account TEXT NOT NULL, kind TEXT NOT NULL, body TEXT NOT NULL, rating INTEGER, status TEXT NOT NULL, replies TEXT NOT NULL, ts TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE events (id TEXT PRIMARY KEY, account TEXT NOT NULL, name TEXT NOT NULL, ts TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE settings (account TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL'
              "${version == 2 ? ', updated TEXT NOT NULL' : ''}, PRIMARY KEY(account,key))",
            );
          },
        ),
      );
      await db.insert('settings', {
        'account': 'legacy',
        'key': 'reducedMotion',
        'value': 'true',
        if (version == 2) 'updated': '2026-10-01T00:00:00.000Z',
      });
      await db.insert('habits', {
        'id': 'legacy-habit',
        'account': 'legacy',
        'aspiration': 'Calm',
        'anchor': 'coffee',
        'behavior': 'breathe',
        'celebration': 'smile',
        'species': 'Fern',
        'stage': 4,
        'status': 'graduated',
        'updated': '2026-10-01T00:00:00.000Z',
      });
      await db.insert('checkins', {
        'id': 'legacy-checkin',
        'account': 'legacy',
        'habitId': 'legacy-habit',
        'day': '2026-10-01',
        'result': 'did',
        'reason': null,
        'ts': '2026-10-01T00:00:00.000Z',
      });
      await db.insert('reflections', {
        'id': 'legacy-reflection',
        'account': 'legacy',
        'habitId': 'legacy-habit',
        'items': '[6,6,6,6]',
        'score': 6,
        'ts': '2026-10-01T00:00:00.000Z',
      });
      await db.insert('voice', {
        'id': 'legacy-voice',
        'account': 'legacy',
        'kind': 'Idea',
        'body': 'Keep this private',
        'rating': null,
        'status': 'review',
        'replies': '["Received"]',
        'ts': '2026-10-01T00:00:00.000Z',
      });
      await db.insert('events', {
        'id': 'legacy-event',
        'account': 'legacy',
        'name': 'checkin',
        'ts': '2026-10-01T00:00:00.000Z',
      });
      await db.close();
      var store = await GardenStore.open(path, 'legacy');
      expect(await store.setting('reducedMotion'), 'true');
      expect((await store.syncPayload())['settings'], hasLength(1));
      expect(
        (await store.syncPayload()).values.every(
          (v) => (v as List).length == 1,
        ),
        isTrue,
      );
      await store.acknowledgeSync(await store.syncPayload());
      await store.close();
      store = await GardenStore.open(path, 'legacy');
      expect((await store.syncPayload())['settings'], isEmpty);
      expect(
        (await store.syncPayload()).values.every((v) => (v as List).isEmpty),
        isTrue,
      );
      expect((await store.habits()).single.stage.index, 4);
      expect((await store.habits()).single.status, 'graduated');
      expect(await store.eventCount(), 1);
      expect((await store.voice()).single['replies'], '["Received"]');
      expect((await store.export())['reflections'], hasLength(1));
      await store.close();
      await databaseFactoryFfi.deleteDatabase(path);
      expect(File(path).existsSync(), isFalse);
    }
  });
}
