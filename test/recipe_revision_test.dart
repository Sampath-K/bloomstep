import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  for (final field in ['anchor', 'behavior']) {
    test('$field replacement resets eligibility, not history or growth', () async {
      var now = DateTime.utc(2026, 9, 1);
      final store = await GardenStore.open(
        ':memory:',
        'owner',
        clock: () => now,
      );
      final replica = await GardenStore.open(
        ':memory:',
        'owner',
        clock: () => now,
      );
      addTearDown(store.close);
      addTearDown(replica.close);
      final h = await store.plant(
        aspiration: 'Calm',
        anchor: 'pour coffee',
        behavior: 'one breath',
        celebration: 'smile',
        species: 'Fern',
      );
      for (var i = 0; i < 28; i++) {
        now = DateTime.utc(2026, 9, i + 1);
        await store.checkIn(h.id, CheckInResult.did);
      }
      await store.reflect(h.id, [6, 6, 6, 6], now: DateTime.utc(2026, 9, 14));
      await store.reflect(h.id, [6, 6, 6, 6]);
      final original = (await store.habits()).single;
      expect(original.status, 'graduated');
      final stale = await store.syncPayload();
      await store.edit(
        original,
        anchor: field == 'anchor' ? 'close laptop' : original.anchor,
        behavior: field == 'behavior' ? 'read one sentence' : original.behavior,
        celebration: original.celebration,
      );
      final revised = (await store.habits()).single;
      expect(revised.recipeRevision, isNotEmpty);
      expect(revised.status, 'active');
      expect(revised.stage, original.stage);
      expect(revised.practiceCount, 28);
      expect(revised.recentPractice, 0);
      expect(revised.today, isNull);
      expect(await store.naturalnessAvailableAt(h.id), isNull);
      await store.reflect(h.id, [7, 7, 7, 7]);
      expect((await store.habits()).single.status, 'active');
      final exported = await store.export();
      expect(exported['checkins'], hasLength(28));
      expect(exported['reflections'], hasLength(3));
      final payload = await store.syncPayload();
      await replica.mergeSync(Map<String, dynamic>.from(payload));
      await replica.mergeSync(Map<String, dynamic>.from(stale));
      expect(
        (await replica.habits()).single.recipeRevision,
        revised.recipeRevision,
      );
      expect((await replica.habits()).single.status, 'active');
      expect((await replica.habits()).single.recentPractice, 0);
      expect(await replica.naturalnessAvailableAt(h.id), isNotNull);
      // Re-recording the same result on the edit day belongs to the new recipe.
      await store.checkIn(h.id, CheckInResult.did);
      expect((await store.export())['checkins'], hasLength(29));
      expect((await store.habits()).single.recentPractice, 1);
      for (var i = 1; i <= 16; i++) {
        now = now.add(const Duration(days: 1));
        await store.checkIn(h.id, CheckInResult.did);
      }
      await store.reflect(h.id, [7, 7, 7, 7]);
      expect((await store.habits()).single.status, 'graduated');
    });
  }

  test(
    'case, whitespace and celebration refinements retain eligibility',
    () async {
      final now = DateTime.utc(2026, 9, 1);
      final store = await GardenStore.open(
        ':memory:',
        'owner',
        clock: () => now,
      );
      addTearDown(store.close);
      final h = await store.plant(
        aspiration: 'Calm',
        anchor: 'pour coffee',
        behavior: 'one breath',
        celebration: 'smile',
        species: 'Fern',
      );
      await store.checkIn(h.id, CheckInResult.did);
      await store.reflect(h.id, [6, 6, 6, 6]);
      await store.edit(
        h,
        anchor: '  POUR \n coffee ',
        behavior: ' ONE  BREATH ',
        celebration: 'quiet nod',
      );
      final refined = (await store.habits()).single;
      expect(refined.recipeRevision, '');
      expect(refined.recentPractice, 1);
      expect(await store.naturalnessAvailableAt(h.id), isNotNull);
    },
  );

  test('v5 evidence migrates and revision survives reopen', () async {
    final directory = await Directory.current.createTemp('recipe-revision-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/garden.sqlite';
    var store = await GardenStore.open(path, 'owner');
    final h = await store.plant(
      aspiration: 'Calm',
      anchor: 'pour coffee',
      behavior: 'one breath',
      celebration: 'smile',
      species: 'Fern',
    );
    await store.checkIn(h.id, CheckInResult.did);
    await store.reflect(h.id, [6, 6, 6, 6]);
    await store.close();
    final db = await databaseFactoryFfi.openDatabase(path);
    for (final table in ['habits', 'checkins', 'reflections']) {
      await db.execute('ALTER TABLE $table DROP COLUMN recipeRevision');
    }
    await db.execute('PRAGMA user_version = 5');
    await db.close();
    store = await GardenStore.open(path, 'owner');
    expect((await store.habits()).single.recentPractice, 1);
    await store.edit(
      h,
      anchor: 'close laptop',
      behavior: h.behavior,
      celebration: h.celebration,
    );
    final revision = (await store.habits()).single.recipeRevision;
    await store.close();
    store = await GardenStore.open(path, 'owner');
    addTearDown(store.close);
    expect((await store.habits()).single.recipeRevision, revision);
    expect((await store.habits()).single.recentPractice, 0);
    expect((await store.export())['reflections'], hasLength(1));
  });
}
