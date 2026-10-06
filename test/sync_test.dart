import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'legacy integer reflection fingerprint converges once across reopen',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bloomstep-fingerprint-',
      );
      final path = p.join(root.path, 'garden.sqlite');
      var store = await GardenStore.open(path, 'reflection-owner');
      addTearDown(() async {
        await store.close();
        await root.delete(recursive: true);
      });
      final habit = await store.plant(
        aspiration: 'Calm',
        anchor: 'coffee',
        behavior: 'one breath',
        celebration: 'smile',
        species: 'Cosmos',
      );
      final received = {
        'id': 'd441aaf0-0e56-4221-b74e-d6c2a3946888',
        'habitId': habit.id,
        'items': '[7,7,7,7]',
        'score': 7,
        'ts': '2026-10-04T12:00:00.000000Z',
      };
      await store.mergeSync({
        'habits': [],
        'checkins': [],
        'reflections': [received],
        'voice': [],
      });
      final keys = received.keys.toList()..sort();
      final legacy = sha256
          .convert(
            utf8.encode(
              jsonEncode({for (final key in keys) key: received[key]}),
            ),
          )
          .toString();
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(path);
      try {
        expect(
          await db.update(
            'sync_state',
            {'fingerprint': legacy},
            where: 'account = ? AND tableName = ? AND recordId = ?',
            whereArgs: ['reflection-owner', 'reflections', received['id']],
          ),
          1,
        );
      } finally {
        await db.close();
      }
      store = await GardenStore.open(path, 'reflection-owner');
      expect((await store.syncPayload())['reflections'], hasLength(1));
      await store.acknowledgeSync({
        'reflections': [received],
      });
      expect((await store.syncPayload())['reflections'], isEmpty);
      await store.close();
      store = await GardenStore.open(path, 'reflection-owner');
      expect((await store.syncPayload())['reflections'], isEmpty);
      expect((await store.export())['reflections'], hasLength(1));
    },
  );

  test(
    'integer server reflection scores stay acknowledged after SQLite import',
    () async {
      final store = await GardenStore.open(':memory:', 'reflection-owner');
      addTearDown(store.close);
      final habit = await store.plant(
        aspiration: 'Calm',
        anchor: 'coffee',
        behavior: 'one breath',
        celebration: 'smile',
        species: 'Cosmos',
      );
      final payload = await store.syncPayload();
      await store.mergeSync({
        'habits': payload['habits'],
        'checkins': [],
        'reflections': [
          {
            'id': 'd441aaf0-0e56-4221-b74e-d6c2a3946888',
            'habitId': habit.id,
            'items': '[7,7,7,7]',
            'score': 7,
            'ts': '2026-10-04T12:00:00.000000Z',
          },
          {
            'id': 'd441aaf0-0e56-4221-b74e-d6c2a3946889',
            'habitId': habit.id,
            'items': '[6,6,6,7]',
            'score': 6.25,
            'ts': '2026-09-20T12:00:00.000000Z',
          },
          {
            'id': 'd441aaf0-0e56-4221-b74e-d6c2a3946890',
            'habitId': habit.id,
            'items': '[7,7,7,7]',
            'score': 7.0,
            'ts': '2026-09-06T12:00:00.000000Z',
          },
          {
            'id': 'd441aaf0-0e56-4221-b74e-d6c2a3946891',
            'habitId': habit.id,
            'items': '[1,1,1,1]',
            'score': 1,
            'ts': '2026-08-23T12:00:00.000000Z',
          },
        ],
        'voice': [],
      });
      final stored = (await store.export())['reflections'] as List;
      expect(stored, hasLength(4));
      expect(stored.map((row) => (row as Map)['score']), [7.0, 6.25, 7.0, 1.0]);
      expect(
        stored.map((row) => (row as Map)['score']),
        everyElement(isA<double>()),
      );
      expect((await store.syncPayload())['reflections'], isEmpty);
      final original = Map<String, Object?>.from(stored.first as Map)
        ..remove('account');
      final different = {...original, 'items': '[6,6,6,6]', 'score': 6};
      await store.mergeSync({
        'habits': [],
        'checkins': [],
        'reflections': [different],
        'voice': [],
      });
      expect((await store.syncPayload())['reflections'], [original]);
      await store.acknowledgeSync({
        'reflections': [different],
      });
      expect((await store.syncPayload())['reflections'], hasLength(1));
      await store.acknowledgeSync({
        'reflections': [
          {...original, 'score': 7},
        ],
      });
      expect((await store.syncPayload())['reflections'], isEmpty);
    },
  );

  test('additive server support receipt sidecar never becomes a native row or unpurged collector', () async {
    final store = await GardenStore.open(
      ':memory:',
      'synthetic-sidecar-compatibility',
    );
    addTearDown(store.close);
    final before = await store.export();
    await store.mergeSync({
      'habits': [],
      'checkins': [],
      'reflections': [],
      'voice': [],
      'settings': [],
      'voiceReceipts': [
        {
          'id': 'd2bb9b7d-481f-4ac5-bfba-808bdf4e2fda',
          'schemaVersion': 1,
          'receivedAt': '2026-09-01T12:00:00.000Z',
          'firstRespondedAt': null,
        },
      ],
    });
    expect(await store.export(), before);
  });

  test(
    'syncs only safe account preferences, never consent or startup opt-in',
    () async {
      final a = await GardenStore.open(':memory:', 'preferences-a');
      final b = await GardenStore.open(':memory:', 'preferences-b');
      addTearDown(a.close);
      addTearDown(b.close);
      await a.setSetting('quietStart', '1200');
      await a.setSetting('analytics', 'true');
      await a.setSetting('reminders', 'true');
      final payload = await a.syncPayload();
      final settings = payload['settings'] as List;
      expect(settings.map((row) => (row as Map)['key']), ['quietStart']);
      await b.mergeSync({...payload, 'acknowledgedEvents': []});
      expect(await b.setting('quietStart'), '1200');
      expect(await b.setting('analytics'), isNull);
      expect(await b.setting('reminders'), isNull);
    },
  );
  test(
    'equal timestamp recipe edits converge and never lose attained stage',
    () async {
      final store = await GardenStore.open(':memory:', 'ties');
      addTearDown(store.close);
      final habit = await store.plant(
        aspiration: 'Calm',
        anchor: 'coffee',
        behavior: 'breathe',
        celebration: 'smile',
        species: 'Fern',
      );
      final raw = Map<String, Object?>.from(
        ((await store.syncPayload())['habits'] as List).single as Map,
      );
      final remote = {...raw, 'anchor': 'zzz', 'stage': 3};
      final data = {
        'habits': [remote],
        'checkins': [],
        'reflections': [],
        'voice': [],
      };
      await store.mergeSync(data);
      expect((await store.habits()).single.anchor, 'zzz');
      expect((await store.habits()).single.id, habit.id);
      await store.mergeSync({
        ...data,
        'habits': [raw],
      });
      expect((await store.habits()).single.anchor, 'zzz');
      expect((await store.habits()).single.stage.index, 3);
    },
  );
  test(
    'remote check-ins union by ID; stale recipes never replace local edits',
    () async {
      final store = await GardenStore.open(':memory:', 'account');
      addTearDown(store.close);
      final habit = await store.plant(
        aspiration: 'Calm',
        anchor: 'coffee',
        behavior: 'one breath',
        celebration: 'smile',
        species: 'Cosmos',
      );
      final local = await store.export();
      final remoteHabit = Map<String, Object?>.from(
        (local['habits'] as List).single as Map,
      )..remove('account');
      await store.edit(
        habit,
        anchor: 'tea',
        behavior: 'one breath',
        celebration: 'smile',
      );
      final event = {
        'id': 'd441aaf0-0e56-4221-b74e-d6c2a3946888',
        'habitId': habit.id,
        'day': '2026-10-04',
        'result': 'did',
        'reason': null,
        'ts': '2026-10-04T12:00:00.000000Z',
      };
      final remote = {
        'habits': [remoteHabit],
        'checkins': [event],
        'reflections': [],
        'voice': [],
        'acknowledgedEvents': [],
      };
      await store.mergeSync(remote);
      await store.mergeSync(remote);
      expect(await store.eventCount(), 1);
      expect((await store.habits()).single.anchor, 'tea');
      expect((await store.habits()).single.practiceCount, 1);
      expect((await store.syncPayload())['habits'], isNotEmpty);
      expect(
        ((await store.syncPayload())['habits'] as List).single,
        isNot(contains('account')),
      );
    },
  );
}
