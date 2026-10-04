import 'package:bloomstep/core/garden_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
