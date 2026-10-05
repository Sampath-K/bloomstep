import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('local1000-marker cap never silently prunes or deletes content and is per account', () async {
    final dir = await Directory.systemTemp.createTemp('bloomstep-delete-cap-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}cap.sqlite';
    final initial = await GardenStore.open(path, 'owner');
    final h = await initial.plant(
      aspiration: 'Synthetic',
      anchor: 'anchor',
      behavior: 'step',
      celebration: 'smile',
      species: 'Fern',
    );
    await initial.close();
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.transaction((txn) async {
      for (var i = 0; i < 1000; i++) {
        await txn.insert('deletions', {
          'account': 'owner',
          'id': const Uuid().v4(),
          'recordId': const Uuid().v4(),
          'type': 'voice',
          'ts': '2026-10-05T00:00:00.000Z',
        });
      }
    });
    await db.close();
    final store = await GardenStore.open(path, 'owner');
    addTearDown(store.close);
    await expectLater(store.deleteRecord('habits', h.id), throwsStateError);
    expect((await store.habits()).single.id, h.id);
    expect((await store.export())['deletions'], hasLength(1000));
    await store.switchAccount('foreign');
    await store.submitVoice('Idea', 'Synthetic');
    await store.deleteRecord(
      'voice',
      (await store.voice()).single['id'] as String,
    );
    expect((await store.export())['deletions'], hasLength(1));
    await store.switchAccount('owner');
    expect((await store.export())['deletions'], hasLength(1000));
    expect((await store.habits()).single.id, h.id);
  });

  test(
    'independent device deletions converge to the server canonical request ID',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bloomstep-delete-conflict-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final a = await GardenStore.open(
        '${dir.path}${Platform.pathSeparator}a.sqlite',
        'owner',
      );
      final b = await GardenStore.open(
        '${dir.path}${Platform.pathSeparator}b.sqlite',
        'owner',
      );
      addTearDown(a.close);
      addTearDown(b.close);
      final h = await a.plant(
        aspiration: 'Synthetic',
        anchor: 'anchor',
        behavior: 'step',
        celebration: 'smile',
        species: 'Fern',
      );
      await b.mergeSync(await a.syncPayload());
      await a.deleteRecord('habits', h.id);
      await b.deleteRecord('habits', h.id);
      final canonical = await a.syncPayload();
      expect(
        ((await b.syncPayload())['deletions'] as List).single,
        isNot((canonical['deletions'] as List).single),
      );
      await b.mergeSync(canonical);
      expect((await b.syncPayload())['deletions'], isEmpty);
      expect((await b.export())['deletions'], (await a.export())['deletions']);
      await b.mergeSync(canonical);
      expect((await b.syncPayload())['deletions'], isEmpty);
    },
  );

  test(
    'delete vs naturalness write never leaves orphaned private reflections',
    () async {
      final store = await GardenStore.open(':memory:', 'reflect-race');
      addTearDown(store.close);
      final h = await store.plant(
        aspiration: 'Synthetic',
        anchor: 'anchor',
        behavior: 'step',
        celebration: 'smile',
        species: 'Fern',
      );
      Object? reflectionError;
      await Future.wait([
        store.reflect(h.id, [4, 4, 4, 4]).catchError((Object error) {
          reflectionError = error;
        }),
        store.deleteRecord('habits', h.id),
      ]);
      expect(reflectionError, anyOf(isNull, isA<StateError>()));
      expect((await store.export())['habits'], isEmpty);
      expect((await store.export())['reflections'], isEmpty);
    },
  );

  test(
    'malformed remote deletion rolls back markers and preserves owner content',
    () async {
      final store = await GardenStore.open(':memory:', 'invalid-delete');
      addTearDown(store.close);
      final h = await store.plant(
        aspiration: 'Synthetic',
        anchor: 'anchor',
        behavior: 'step',
        celebration: 'smile',
        species: 'Fern',
      );
      for (final fields in [
        {'id': '-' * 36, 'ts': '2026-10-05T00:00:00Z'},
        {'id': h.id, 'ts': 'invalid'},
        {'id': h.id, 'ts': '2026-10-05T00:00:00'},
        {'id': h.id, 'ts': '2026-02-31T00:00:00Z'},
        {'id': h.id, 'ts': '2026-10-05T00:00:00.1234567Z'},
        {'id': h.id, 'ts': '2026-10-05T00:00:00Z', 'body': 'forbidden'},
      ]) {
        await expectLater(
          store.mergeSync({
            'deletions': [
              {'type': 'habits', 'recordId': h.id, ...fields},
            ],
          }),
          throwsFormatException,
        );
        expect((await store.habits()).single.id, h.id);
        expect((await store.export())['deletions'], isEmpty);
      }
    },
  );

  test(
    'owner deletion survives stale merge and purges dependent private rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bloomstep-delete-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final a = await GardenStore.open(
        '${directory.path}${Platform.pathSeparator}a.sqlite',
        'owner',
      );
      final b = await GardenStore.open(
        '${directory.path}${Platform.pathSeparator}b.sqlite',
        'owner',
      );
      addTearDown(a.close);
      addTearDown(b.close);
      final habit = await a.plant(
        aspiration: 'Synthetic deletion test',
        anchor: 'test anchor',
        behavior: 'test step',
        celebration: 'test smile',
        species: 'Fern',
      );
      await a.setSetting('analytics', 'true');
      await a.checkIn(habit.id, CheckInResult.did);
      await a.reflect(habit.id, [4, 4, 4, 4]);
      final stale = await a.syncPayload();
      await b.mergeSync(stale);
      await a.deleteRecord('habits', habit.id);
      await a.track(
        'automaticity_score',
        properties: {
          'habitId': habit.id,
          'score': 4,
          'localDay': localDate(DateTime.now()),
          'platform': 'windows',
        },
      );
      expect(
        ((await a.export())['events'] as List).where(
          (row) =>
              row['properties'] is String &&
              (row['properties'] as String).contains(habit.id),
        ),
        isEmpty,
      );
      final deleted = await a.syncPayload();
      expect((deleted['deletions'] as List), hasLength(1));
      await b.mergeSync({...stale, 'deletions': deleted['deletions']});
      await a.mergeSync(stale);
      expect(await a.habits(), isEmpty);
      expect(await b.habits(), isEmpty);
      expect((await a.export())['checkins'], isEmpty);
      expect((await a.export())['reflections'], isEmpty);
      await expectLater(
        a.checkIn(habit.id, CheckInResult.did),
        throwsStateError,
      );
      await a.deleteRecord('habits', habit.id);
      expect((await a.syncPayload())['deletions'], deleted['deletions']);
      await a.switchAccount('foreign');
      await expectLater(a.deleteRecord('habits', habit.id), throwsStateError);
    },
  );

  test('feedback deletion removes body/replies and retains only minimal stable metadata', () async {
    final store = await GardenStore.open(':memory:', 'owner');
    addTearDown(store.close);
    await store.submitVoice('Idea', 'Synthetic private fixture');
    final record = (await store.voice()).single;
    await store.deleteRecord('voice', record['id'] as String);
    expect(await store.voice(), isEmpty);
    final deletion =
        ((await store.syncPayload())['deletions'] as List).single as Map;
    expect(deletion.keys.toSet(), {'id', 'type', 'recordId', 'ts'});
    expect((await store.export())['voice'], isEmpty);
    await expectLater(
      store.deleteRecord('settings', 'analytics'),
      throwsArgumentError,
    );
  });

  test('v4 migration preserves existing data and deletion survives restart/foreign rows', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp(
      'bloomstep-delete-migration-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}v4.sqlite';
    final initial = await GardenStore.open(path, 'owner');
    final habit = await initial.plant(
      aspiration: 'Synthetic',
      anchor: 'anchor',
      behavior: 'step',
      celebration: 'smile',
      species: 'Fern',
    );
    await initial.close();
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('DROP TABLE deletions');
    await db.setVersion(4);
    await db.close();
    final upgraded = await GardenStore.open(path, 'owner');
    expect((await upgraded.habits()).single.id, habit.id);
    await upgraded.deleteRecord('habits', habit.id);
    final id = ((await upgraded.syncPayload())['deletions'] as List).single;
    await upgraded.close();
    final restarted = await GardenStore.open(path, 'owner');
    addTearDown(restarted.close);
    expect(await restarted.habits(), isEmpty);
    expect(((await restarted.syncPayload())['deletions'] as List).single, id);
    await restarted.switchAccount('foreign');
    expect((await restarted.export())['deletions'], isEmpty);
  });
}
