import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/core/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'weekly Recipe Doctor is independent of naturalness and deterministic',
    () async {
      final store = await GardenStore.open(':memory:', 'weekly');
      addTearDown(store.close);
      final h = await store.plant(
        aspiration: 'Calm',
        anchor: 'coffee',
        behavior: 'breathe',
        celebration: 'smile',
        species: 'Fern',
      );
      final date = DateTime.utc(2026, 10, 4);
      await store.reflect(h.id, [6, 6, 6, 6], now: date);
      await store.checkIn(
        h.id,
        CheckInResult.notToday,
        reason: 'too hard',
        now: date.subtract(const Duration(days: 2)),
      );
      await store.checkIn(
        h.id,
        CheckInResult.notToday,
        reason: 'anchor',
        now: date.subtract(const Duration(days: 1)),
      );
      // An older reason must not dominate this week's recommendation.
      await store.checkIn(
        h.id,
        CheckInResult.notToday,
        reason: 'motivation',
        now: date.subtract(const Duration(days: 9)),
      );
      expect(
        await store.weeklyRecommendation(h.id, now: date),
        recipeDoctor('too hard'),
      );
      expect(
        await store.naturalnessAvailableAt(h.id),
        date.add(const Duration(days: 14)),
      );
      expect(await store.weeklyReflectionDue(now: date), isTrue);
      await store.completeWeeklyReflection(h.id, now: date);
      expect(await store.weeklyReflectionDue(now: date), isFalse);
      expect(
        await store.weeklyReflectionDue(now: date.add(const Duration(days: 7))),
        isTrue,
      );
      expect((await store.export())['reflections'], hasLength(1));
      expect((await store.habits()).single.status, 'active');
      expect(await store.setting('weeklyLast'), date.toIso8601String());
    },
  );

  test(
    'rating prompts require positive milestones and honor 120 day cadence',
    () async {
      final store = await GardenStore.open(':memory:', 'ratings');
      addTearDown(store.close);
      final h = await store.plant(
        aspiration: 'Calm',
        anchor: 'coffee',
        behavior: 'breathe',
        celebration: 'smile',
        species: 'Fern',
      );
      final start = DateTime.utc(2026, 1, 1);
      expect(await store.claimRatingPrompt(now: start), isFalse);
      for (var i = 0; i < 30; i++) {
        await store.checkIn(
          h.id,
          CheckInResult.did,
          now: start.add(Duration(days: i)),
        );
      }
      final moment = start.add(const Duration(days: 30));
      expect(await store.claimRatingPrompt(now: moment), isTrue);
      expect(await store.claimRatingPrompt(now: moment), isFalse);
      expect(
        await store.claimRatingPrompt(
          now: moment.add(const Duration(days: 119, hours: 23)),
        ),
        isFalse,
      );
      expect(
        await store.claimRatingPrompt(
          now: moment.add(const Duration(days: 120)),
        ),
        isTrue,
      );
      await store.submitVoice('Rating', '', rating: 4);
      expect((await store.voice()).single['rating'], 4);
      await store.switchAccount('other');
      expect(await store.setting('ratingPromptedAt'), isNull);
      expect(await store.claimRatingPrompt(now: moment), isFalse);
    },
  );

  test('third positive comeback qualifies, but rest days do not', () async {
    final store = await GardenStore.open(':memory:', 'comebacks');
    addTearDown(store.close);
    final h = await store.plant(
      aspiration: 'Calm',
      anchor: 'coffee',
      behavior: 'breathe',
      celebration: 'smile',
      species: 'Fern',
    );
    final date = DateTime.utc(2026, 2, 1);
    await store.recordInteraction(now: date);
    for (var i = 1; i <= 3; i++) {
      final moment = date.add(Duration(days: i * 4));
      await store.checkIn(h.id, CheckInResult.did, now: moment);
      expect(await store.claimRatingPrompt(now: moment), i == 3);
    }
    expect(await store.setting('ratingComebacks'), '3');
    await store.checkIn(
      h.id,
      CheckInResult.notToday,
      now: date.add(const Duration(days: 20)),
    );
    expect(await store.setting('ratingComebacks'), '3');
    expect(
      await store.claimRatingPrompt(
        now: date.add(const Duration(days: 140)),
        positiveMoment: false,
      ),
      isFalse,
    );
  });

  test(
    'real store graduation requires two fortnightly checks and practice',
    () async {
      final store = await GardenStore.open(':memory:', 'learning-test');
      addTearDown(store.close);
      final h = await store.plant(
        aspiration: 'Focus',
        anchor: 'coffee',
        behavior: 'write one word',
        celebration: 'smile',
        species: 'Fern',
      );
      for (var i = 1; i <= 28; i++) {
        await store.checkIn(h.id, CheckInResult.did, now: DateTime(2026, 9, i));
      }
      await store.reflect(h.id, [6, 6, 6, 6], now: DateTime(2026, 9, 14));
      expect((await store.habits()).single.status, 'active');
      await expectLater(
        store.reflect(h.id, [6, 6, 6, 6], now: DateTime(2026, 9, 15)),
        throwsStateError,
      );
      await store.reflect(h.id, [6, 6, 6, 6], now: DateTime(2026, 9, 28));
      expect((await store.habits()).single.status, 'graduated');
      expect((await store.habits()).single.stage, GrowthStage.bloom);
      expect(
        await store.claimRatingPrompt(
          now: DateTime(2026, 9, 28),
          positiveMoment: false,
        ),
        isFalse,
      );
      expect(await store.claimRatingPrompt(now: DateTime(2026, 9, 28)), isTrue);
    },
  );
  test('reconnects stop after two per absence and explain when due', () {
    expect(reconnectDue(2, 0), isFalse);
    expect(reconnectDue(3, 0), isTrue);
    expect(reconnectDue(6, 1), isFalse);
    expect(reconnectDue(7, 1), isTrue);
    expect(reconnectDue(30, 2), isFalse);
  });
}
