import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GardenStore store;
  setUp(() async {
    store = await GardenStore.open(':memory:', 'account-a');
  });
  tearDown(() => store.close());

  Future<Habit> plant() => store.plant(
    aspiration: 'Calm',
    anchor: 'pour my coffee',
    behavior: 'take one slow breath',
    celebration: 'smile',
    species: 'Cosmos',
  );

  test(
    'recipes are validated and persisted with a practiced celebration',
    () async {
      expect(await store.habits(), isEmpty);
      final habit = await plant();
      expect((await store.habits()).single.id, habit.id);
      expect(habit.stage, GrowthStage.seed);
      await expectLater(
        store.plant(
          aspiration: '',
          anchor: '',
          behavior: '',
          celebration: '',
          species: 'Cosmos',
        ),
        throwsArgumentError,
      );
    },
  );

  test('local date deduplication, edits and undo are append-only', () async {
    final habit = await plant();
    final day = DateTime(2026, 10, 4, 23, 59);
    await store.checkIn(habit.id, CheckInResult.did, now: day);
    await store.checkIn(habit.id, CheckInResult.did, now: day);
    expect(await store.eventCount(), 1);
    await store.checkIn(habit.id, CheckInResult.didMore, now: day);
    expect(await store.eventCount(), 2);
    expect((await store.habits()).single.practiceCount, 1);
    await store.undo(habit.id, now: day);
    expect((await store.habits()).single.practiceCount, 0);
    expect(await store.eventCount(), 3);
    await store.checkIn(
      habit.id,
      CheckInResult.did,
      now: day.add(const Duration(minutes: 2)),
    );
    expect((await store.habits()).single.practiceCount, 1);
  });

  test('growth never shrinks after an undo or rest day', () async {
    final habit = await plant();
    for (var i = 1; i <= 3; i++) {
      await store.checkIn(
        habit.id,
        CheckInResult.did,
        now: DateTime(2026, 10, i),
      );
    }
    expect((await store.habits()).single.stage, GrowthStage.sprout);
    await store.undo(habit.id, now: DateTime(2026, 10, 3));
    await store.checkIn(
      habit.id,
      CheckInResult.notToday,
      reason: 'forgot',
      now: DateTime(2026, 10, 4),
    );
    expect((await store.habits()).single.stage, GrowthStage.sprout);
  });

  test('accounts cannot read or mutate each other', () async {
    final habit = await plant();
    await store.switchAccount('account-b');
    expect(await store.habits(), isEmpty);
    await expectLater(
      store.checkIn(habit.id, CheckInResult.did),
      throwsStateError,
    );
    await store.switchAccount('account-a');
    expect((await store.habits()).single.id, habit.id);
  });

  test('export and deletion cover all private local records', () async {
    final habit = await plant();
    await store.checkIn(habit.id, CheckInResult.did);
    await store.submitVoice('Idea', 'Private feedback', rating: null);
    expect((await store.export())['habits'], hasLength(1));
    await store.deleteLocalAccount();
    expect((await store.export())['habits'], isEmpty);
    expect(await store.eventCount(), 0);
    expect(await store.voice(), isEmpty);
  });
}
