import 'dart:convert';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:bloomstep/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Habit> plant(GardenStore store) => store.plant(
  aspiration: 'PRIVATE aspiration',
  anchor: 'PRIVATE anchor',
  behavior: 'PRIVATE behavior',
  celebration: 'PRIVATE celebration',
  species: 'Fern',
);

Future<List<Map>> events(GardenStore store) async =>
    ((await store.syncPayload())['events'] as List).cast<Map>();

class TelemetryIdentity extends IdentityService {
  TelemetryIdentity() {
    account = 'wire';
  }
  @override
  Future<String> accessToken() async => 'test-token';
}

void main() {
  test(
    'first checkin milestone requires observed practice, not a rest or undo',
    () async {
      final store = await GardenStore.open(':memory:', 'first-positive');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      final h = await plant(store);
      await store.checkIn(h.id, CheckInResult.notToday);
      await store.undo(h.id);
      expect(
        (await events(store)).where((r) => r['name'] == 'first_checkin'),
        isEmpty,
      );
      await store.checkIn(h.id, CheckInResult.did);
      expect(
        (await events(store)).where((r) => r['name'] == 'first_checkin'),
        hasLength(1),
      );
      await store.undo(h.id);
      await store.checkIn(h.id, CheckInResult.didMore);
      expect(
        (await events(store)).where((r) => r['name'] == 'first_checkin'),
        hasLength(1),
      );
    },
  );

  test(
    'sync sends structured properties and server acknowledgment clears queue',
    () async {
      final store = await GardenStore.open(':memory:', 'wire');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      await store.track(
        'checkin',
        properties: {'localDay': '2026-10-04', 'result': 'did'},
      );
      var sent = false;
      final client = MockClient((request) async {
        final acknowledged = <String>[];
        if (request.method == 'POST') {
          sent = true;
          final payload = jsonDecode(request.body) as Map;
          final rows = payload['events'] as List;
          expect(rows.every((r) => r['properties'] is Map), isTrue);
          final check = rows.singleWhere((r) => r['name'] == 'checkin');
          expect(check['properties'], {
            'localDay': '2026-10-04',
            'result': 'did',
          });
          acknowledged.addAll(rows.map((r) => r['id'] as String));
        }
        return http.Response(
          jsonEncode({
            'habits': [],
            'checkins': [],
            'reflections': [],
            'voice': [],
            'settings': [],
            'acknowledgedEvents': acknowledged,
          }),
          200,
        );
      });
      addTearDown(client.close);
      await SyncService(TelemetryIdentity(), store, client: client).sync();
      expect(sent, isTrue);
      expect(await events(store), isEmpty);
      expect((await store.export())['events'], isEmpty);
    },
  );

  test(
    'observed learning and voice events carry only constrained metadata',
    () async {
      final store = await GardenStore.open(':memory:', 'loops');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      await store.setSetting('analytics', 'true');
      final h = await store.plant(
        aspiration: 'PRIVATE aspiration',
        anchor: 'PRIVATE anchor',
        behavior: 'PRIVATE behavior',
        celebration: 'PRIVATE celebration',
        species: 'Fern',
        templateCategory: 'calm',
        celebrationPracticed: true,
      );
      final start = DateTime(2026, 9, 1);
      await store.recordInteraction(now: start);
      await Future.wait([
        store.recordInteraction(
          now: start.add(const Duration(days: 4)),
          positiveReturn: true,
        ),
        store.recordInteraction(
          now: start.add(const Duration(days: 4)),
          positiveReturn: true,
        ),
      ]);
      for (var i = 0; i < 28; i++) {
        await store.checkIn(
          h.id,
          CheckInResult.did,
          now: start.add(Duration(days: i)),
        );
      }
      await store.completeWeeklyReflection(
        h.id,
        now: start.add(const Duration(days: 7)),
      );
      await store.reflect(h.id, [
        6,
        6,
        6,
        6,
      ], now: start.add(const Duration(days: 13)));
      await store.reflect(h.id, [
        6,
        6,
        6,
        6,
      ], now: start.add(const Duration(days: 27)));
      await store.reflect(h.id, [
        6,
        6,
        6,
        6,
      ], now: start.add(const Duration(days: 41)));
      await store.submitVoice('Rating', 'PRIVATE feedback', rating: 4);
      await store.track('share_initiated', properties: {'channel': 'link'});
      final wire = await events(store);
      expect(wire.where((r) => r['name'] == 'analytics_consent'), hasLength(1));
      expect(wire.where((r) => r['name'] == 'comeback'), hasLength(1));
      expect(
        wire.where((r) => r['name'] == 'celebration_practiced'),
        hasLength(1),
      );
      expect(
        wire.where((r) => r['name'] == 'automaticity_score'),
        hasLength(3),
      );
      expect(wire.where((r) => r['name'] == 'habit_graduated'), hasLength(1));
      expect(
        wire.singleWhere((r) => r['name'] == 'rated')['properties'],
        containsPair('rating', 4),
      );
      expect(
        wire.singleWhere((r) => r['name'] == 'recipe_created')['properties'],
        containsPair('templateCategory', 'calm'),
      );
      expect(wire.where((r) => r['name'] == 'experiment_exposure'), isEmpty);
      expect(jsonEncode(wire), isNot(contains('PRIVATE')));
      await store.switchAccount('other');
      expect(await events(store), isEmpty);
      await expectLater(
        store.track('automaticity_score', properties: {'score': double.nan}),
        throwsArgumentError,
      );
      await expectLater(
        store.track('automaticity_score', properties: {'score': 8}),
        throwsArgumentError,
      );
      await expectLater(
        store.track('rated', properties: {'rating': 2.5}),
        throwsArgumentError,
      );
      await expectLater(
        store.track(
          'recipe_created',
          properties: {'templateCategory': 'PRIVATE aspiration'},
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'strict metadata is validated even without consent; no private text',
    () async {
      final store = await GardenStore.open(':memory:', 'private-account');
      addTearDown(store.close);
      for (final props in [
        {'body': 'PRIVATE feedback'},
        {'habitId': 'not-a-uuid'},
        {'result': 'unknown'},
        {'localDay': '2026-02-30'},
        {'account': 'private-account'},
        {'result': null},
      ]) {
        await expectLater(
          store.track('checkin', properties: props),
          throwsArgumentError,
        );
      }
      await expectLater(store.track('not_registered'), throwsArgumentError);
      await store.track('checkin', properties: {'result': 'did'});
      expect(await events(store), isEmpty);
      await store.setSetting('analytics', 'true');
      final h = await plant(store);
      final now = DateTime(2026, 10, 4);
      await store.checkIn(h.id, CheckInResult.did, now: now);
      await store.submitVoice('Idea', 'PRIVATE feedback');
      final wire = await events(store);
      expect(jsonEncode(wire), isNot(contains('PRIVATE')));
      expect(jsonEncode(wire), isNot(contains('private-account')));
      final checkin = wire.singleWhere((r) => r['name'] == 'checkin');
      expect(checkin['properties'], containsPair('habitId', h.id));
      expect(checkin['properties'], containsPair('result', 'did'));
      expect(checkin['properties'], containsPair('localDay', '2026-10-04'));
      expect(
        wire.every(
          (r) => r.keys.every(
            (key) => ['id', 'name', 'ts', 'properties'].contains(key),
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'idempotent journal no-op emits no duplicate checkin or first checkin',
    () async {
      final store = await GardenStore.open(':memory:', 'no-op');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      final h = await plant(store);
      final date = DateTime.now();
      await store.checkIn(h.id, CheckInResult.did, now: date);
      final first = await events(store);
      await store.checkIn(h.id, CheckInResult.did, now: date);
      expect(await events(store), first);
      await store.checkIn(h.id, CheckInResult.didMore, now: date);
      await store.undo(h.id, now: date);
      await store.undo(h.id, now: date);
      final wire = await events(store);
      expect(wire.where((r) => r['name'] == 'checkin'), hasLength(3));
      expect(wire.where((r) => r['name'] == 'first_checkin'), hasLength(1));
      expect(
        wire.singleWhere(
          (r) =>
              r['name'] == 'checkin' &&
              (r['properties'] as Map)['result'] == 'undo',
        )['properties'],
        containsPair('result', 'undo'),
      );
      expect(await store.eventCount(), 3);
    },
  );

  test('properties survive snapshot acknowledgment and reopen, legacy hashes remain stable', () async {
    final path =
        'telemetry-migrate-${DateTime.now().microsecondsSinceEpoch}.db';
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE events (id TEXT PRIMARY KEY, account TEXT NOT NULL, name TEXT NOT NULL, ts TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE sync_state (account TEXT NOT NULL, tableName TEXT NOT NULL, recordId TEXT NOT NULL, fingerprint TEXT NOT NULL, PRIMARY KEY(account,tableName,recordId))',
          );
          await db.execute(
            'CREATE TABLE settings (account TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, updated TEXT NOT NULL, PRIMARY KEY(account,key))',
          );
          for (final table in ['habits', 'checkins', 'reflections', 'voice']) {
            await db.execute(
              'CREATE TABLE $table (id TEXT PRIMARY KEY, account TEXT NOT NULL)',
            );
          }
        },
      ),
    );
    final legacy = {
      'id': '772d3a02-12e2-4a69-a607-3276d8bdaf64',
      'name': 'checkin',
      'ts': '2026-10-04T00:00:00.000Z',
    };
    final keys = legacy.keys.toList()..sort();
    await db.insert('events', {...legacy, 'account': 'legacy'});
    await db.insert('sync_state', {
      'account': 'legacy',
      'tableName': 'events',
      'recordId': legacy['id'],
      'fingerprint': sha256
          .convert(
            utf8.encode(jsonEncode({for (final key in keys) key: legacy[key]})),
          )
          .toString(),
    });
    await db.close();
    var store = await GardenStore.open(path, 'legacy');
    addTearDown(() async {
      await store.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
    expect(await events(store), isEmpty);
    await store.setSetting('analytics', 'true');
    await store.track(
      'checkin',
      properties: {'result': 'did', 'localDay': '2026-10-04'},
    );
    final reordered = await store.syncPayload();
    for (final row in reordered['events'] as List) {
      final props = row['properties'] as Map;
      row['properties'] = {
        for (final key in props.keys.toList().reversed) key: props[key],
      };
    }
    await store.acknowledgeSync(reordered);
    expect(await events(store), isEmpty);
    await store.track('rated', properties: {'rating': 4});
    final submitted = await store.syncPayload();
    expect(
      (submitted['events'] as List).every((r) => r['properties'] is Map),
      isTrue,
    );
    await store.acknowledgeSync(submitted);
    expect(await events(store), isEmpty);
    await store.close();
    store = await GardenStore.open(path, 'legacy');
    expect(await events(store), isEmpty);
    expect(
      (await store.weeklyGardenStory(now: DateTime(2026, 10, 4))).habits,
      isEmpty,
    );
    final exported = (await store.export())['events'] as List;
    expect(exported, hasLength(4));
    expect(
      exported.firstWhere((r) => r['id'] == legacy['id'])['properties'],
      isNull,
    );
    expect(
      jsonDecode(
        exported.firstWhere(
              (r) => r['id'] != legacy['id'] && r['name'] == 'checkin',
            )['properties']
            as String,
      ),
      containsPair('result', 'did'),
    );
  });

  test(
    'concurrent telemetry and opt-out cannot requeue private events',
    () async {
      final store = await GardenStore.open(':memory:', 'concurrency');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      await Future.wait([
        for (var i = 0; i < 25; i++)
          store.track('checkin', properties: {'result': 'did'}),
        store.setSetting('analytics', 'false'),
        for (var i = 0; i < 25; i++)
          store.track('checkin', properties: {'result': 'didMore'}),
      ]);
      expect((await store.export())['events'], isEmpty);
      expect(await events(store), isEmpty);
    },
  );
}
