import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/core/rules.dart';
import 'package:bloomstep/core/weekly_garden_story.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Habit> plant(GardenStore store, String aspiration) => store.plant(
  aspiration: aspiration,
  anchor: 'make coffee',
  behavior: 'take one breath',
  celebration: 'smile',
  species: 'Fern',
);

void main() {
  test(
    'UTC clocks use the same local day for check-ins and habit state',
    () async {
      for (final hour in [0, 23]) {
        final localNow = DateTime(2026, 10, 5, hour, 30);
        final store = await GardenStore.open(
          ':memory:',
          'story-utc-$hour',
          clock: () => localNow.toUtc(),
        );
        addTearDown(store.close);
        final habit = await plant(store, 'Calm');

        await store.checkIn(habit.id, CheckInResult.didMore);

        final current = (await store.habits()).single;
        expect(current.today, CheckInResult.didMore);
        expect(current.recentPractice, 1);
        expect((await store.weeklyGardenStory()).practiceDays, 1);
        expect(
          ((await store.export())['checkins'] as List).single,
          containsPair('day', localDate(localNow)),
        );
      }
    },
  );

  test('empty recap uses Monday through today in the local calendar', () async {
    final store = await GardenStore.open(':memory:', 'story-empty');
    addTearDown(store.close);

    final story = await store.weeklyGardenStory(now: DateTime(2026, 10, 7, 18));

    expect(story, isA<WeeklyGardenStory>());
    expect(story.weekStart, '2026-10-05');
    expect(story.through, '2026-10-07');
    expect(story.habits, isEmpty);
    expect(story.practiceDays, 0);
    expect(story.evergreenCount, 0);
  });

  test(
    'recap counts effective practice days and prioritizes this week reasons',
    () async {
      final store = await GardenStore.open(':memory:', 'story-practice');
      addTearDown(store.close);
      final habit = await plant(store, 'Calm');
      final mondayLocal = DateTime(2026, 10, 5, 0, 5);

      await store.checkIn(
        habit.id,
        CheckInResult.did,
        now: DateTime(2026, 10, 4, 12),
      );
      await store.checkIn(
        habit.id,
        CheckInResult.did,
        now: mondayLocal.toUtc(),
      );
      await store.checkIn(
        habit.id,
        CheckInResult.didMore,
        now: mondayLocal.add(const Duration(minutes: 2)).toUtc(),
      );
      await store.checkIn(
        habit.id,
        CheckInResult.notToday,
        reason: 'too hard',
        now: DateTime(2026, 10, 6, 9),
      );
      await store.checkIn(
        habit.id,
        CheckInResult.notToday,
        reason: 'anchor',
        now: DateTime(2026, 10, 7, 9),
      );
      await store.checkIn(
        habit.id,
        CheckInResult.notToday,
        reason: 'motivation',
        now: DateTime(2026, 9, 30, 9),
      );

      final story = await store.weeklyGardenStory(
        now: DateTime(2026, 10, 7, 18),
      );
      final entry = story.habits.single;

      expect(story.weekStart, '2026-10-05');
      expect(story.through, '2026-10-07');
      expect(story.practiceDays, 1);
      expect(entry.practiceDays, 1);
      expect(entry.suggestion, recipeDoctor('too hard'));
      expect(entry.stage, GrowthStage.seed);
      expect(entry.isEvergreen, isFalse);
    },
  );

  test('graduated habits remain in the evergreen Grove in recap', () async {
    final store = await GardenStore.open(':memory:', 'story-grove');
    addTearDown(store.close);
    final habit = await plant(store, 'Learning');
    final firstPractice = DateTime(2026, 9, 1);
    for (var day = 0; day < 17; day++) {
      await store.checkIn(
        habit.id,
        CheckInResult.did,
        now: firstPractice.add(Duration(days: day)),
      );
    }
    await store.reflect(habit.id, [6, 6, 6, 6], now: DateTime(2026, 9, 14));
    await store.reflect(habit.id, [6, 6, 6, 6], now: DateTime(2026, 9, 28));

    final story = await store.weeklyGardenStory(now: DateTime(2026, 9, 28, 12));

    expect(story.evergreenCount, 1);
    expect(story.habits.single.isEvergreen, isTrue);
    expect(story.habits.single.stage, GrowthStage.bloom);
    expect(story.habits.single.suggestion, contains('Keep what feels easy'));
  });

  test(
    'seen state stays local to the owner and is not synced or tracked',
    () async {
      final store = await GardenStore.open(':memory:', 'story-owner');
      addTearDown(store.close);
      final habit = await plant(store, 'Focus');
      final monday = DateTime(2026, 10, 5, 10);
      final eventsBefore = await store.eventCount();

      expect(await store.weeklyGardenStoryDue(now: monday), isTrue);
      await store.markWeeklyGardenStorySeen(habit.id, now: monday);
      expect(await store.setting('weeklyGardenStorySeenWeek'), '2026-10-05');
      expect(await store.weeklyGardenStoryDue(now: monday), isFalse);
      expect(
        await store.weeklyGardenStoryDue(now: DateTime(2026, 10, 11, 23)),
        isFalse,
      );
      expect(
        await store.weeklyGardenStoryDue(now: DateTime(2026, 10, 12)),
        isTrue,
      );
      expect(await store.eventCount(), eventsBefore);
      expect(
        ((await store.syncPayload())['settings'] as List).any(
          (row) => (row as Map)['key'] == 'weeklyGardenStorySeenWeek',
        ),
        isFalse,
      );

      await store.switchAccount('story-other-owner');
      expect((await store.weeklyGardenStory(now: monday)).habits, isEmpty);
      expect(await store.setting('weeklyGardenStorySeenWeek'), isNull);
      expect(await store.weeklyGardenStoryDue(now: monday), isTrue);
    },
  );

  test(
    'export contains the computed recap without adding an owner identifier',
    () async {
      final store = await GardenStore.open(':memory:', 'story-export-owner');
      addTearDown(store.close);
      final habit = await plant(store, 'Connection');
      await store.checkIn(habit.id, CheckInResult.did, now: DateTime.now());

      final exported = await store.export();
      final story = exported['weeklyGardenStory']! as Map<String, Object?>;
      final entries = story['habits']! as List;
      final entry = entries.single as Map<String, Object?>;

      expect(story['practiceDays'], 1);
      expect(entry['aspiration'], 'Connection');
      expect(entry.containsKey('account'), isFalse);
      expect(entry.containsKey('email'), isFalse);
      expect(entry.containsKey('token'), isFalse);
      expect(entry.containsKey('id'), isFalse);
    },
  );
}
