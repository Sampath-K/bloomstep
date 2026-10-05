import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'legacy version relabeling repairs v5 without erasing the deletion ledger',
    () async {
      final dir = await Directory.systemTemp.createTemp('bloomstep-schema-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}garden.sqlite';
      var store = await GardenStore.open(path, 'synthetic-owner');
      final habit = await store.plant(
        aspiration: 'Synthetic schema fixture',
        anchor: 'After a synthetic event',
        behavior: 'One synthetic step',
        celebration: 'Synthetic smile',
        species: 'Fern',
      );
      await store.deleteRecord('habits', habit.id);
      final before = await store.export();
      await store.close();

      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 4),
      );
      expect(await legacy.getVersion(), 4);
      await legacy.insert('habits', {
        'id': habit.id,
        'account': 'synthetic-owner',
        'aspiration': 'Synthetic stale copy',
        'anchor': 'Synthetic',
        'behavior': 'Synthetic',
        'celebration': 'Synthetic',
        'species': 'Fern',
        'stage': 0,
        'status': 'active',
        'updated': '2026-10-05T00:00:00.000Z',
      });
      await legacy.close();

      store = await GardenStore.open(path, 'synthetic-owner');
      addTearDown(store.close);
      expect((await store.export())['deletions'], before['deletions']);
      expect((await store.export())['habits'], isEmpty);
    },
  );

  test(
    'current client refuses a future schema and leaves records intact',
    () async {
      final dir = await Directory.systemTemp.createTemp('bloomstep-future-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}garden.sqlite';
      final store = await GardenStore.open(path, 'synthetic-owner');
      final habit = await store.plant(
        aspiration: 'Synthetic future fixture',
        anchor: 'After a synthetic event',
        behavior: 'One synthetic step',
        celebration: 'Synthetic smile',
        species: 'Fern',
      );
      await store.close();
      var raw = await databaseFactoryFfi.openDatabase(path);
      await raw.execute('PRAGMA user_version = 6');
      await raw.close();

      GardenStore? unexpected;
      try {
        await expectLater(
          GardenStore.open(path, 'synthetic-owner').then((value) {
            unexpected = value;
            return value;
          }),
          throwsA(anyOf(isA<DatabaseException>(), isA<StateError>())),
        );
      } finally {
        await unexpected?.close();
      }
      raw = await databaseFactoryFfi.openDatabase(path);
      addTearDown(raw.close);
      expect(await raw.getVersion(), 6);
      expect((await raw.query('habits')).single['id'], habit.id);
      expect((await raw.query('habits')).single['account'], 'synthetic-owner');
    },
  );

  test(
    'malformed existing deletion table is rejected without a migration',
    () async {
      final dir = await Directory.systemTemp.createTemp('bloomstep-shape-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}garden.sqlite';
      final store = await GardenStore.open(path, 'synthetic-owner');
      await store.close();
      var raw = await databaseFactoryFfi.openDatabase(path);
      await raw.execute('DROP TABLE deletions');
      await raw.execute('CREATE TABLE deletions (id TEXT)');
      await raw.execute('PRAGMA user_version = 4');
      await raw.close();
      await expectLater(
        GardenStore.open(path, 'synthetic-owner'),
        throwsA(anyOf(isA<DatabaseException>(), isA<StateError>())),
      );
      raw = await databaseFactoryFfi.openDatabase(path);
      addTearDown(raw.close);
      expect(await raw.getVersion(), 4);
      expect(await raw.rawQuery('PRAGMA table_info(deletions)'), hasLength(1));
    },
  );

  test(
    'relabel recovery rejects missing canonical request uniqueness',
    () async {
      final dir = await Directory.systemTemp.createTemp('bloomstep-keys-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}garden.sqlite';
      final store = await GardenStore.open(path, 'synthetic-owner');
      await store.close();
      var raw = await databaseFactoryFfi.openDatabase(path);
      await raw.execute('DROP TABLE deletions');
      await raw.execute(
        'CREATE TABLE deletions (id TEXT NOT NULL, account TEXT NOT NULL, '
        'type TEXT NOT NULL, recordId TEXT NOT NULL, ts TEXT NOT NULL, '
        'PRIMARY KEY(account,type,recordId))',
      );
      await raw.execute('PRAGMA user_version = 4');
      await raw.close();
      await expectLater(
        GardenStore.open(path, 'synthetic-owner'),
        throwsA(anyOf(isA<DatabaseException>(), isA<StateError>())),
      );
      raw = await databaseFactoryFfi.openDatabase(path);
      addTearDown(raw.close);
      expect(await raw.getVersion(), 4);
      expect(await raw.rawQuery('PRAGMA table_info(deletions)'), hasLength(5));
    },
  );
}
