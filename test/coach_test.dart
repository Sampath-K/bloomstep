import 'dart:io';

import 'package:bloomstep/core/coach.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

Habit recipe(String id, {int days = 0, String? reason}) => Habit(
  id: id,
  aspiration: 'Calm',
  anchor: 'put my cup away',
  behavior: 'take one breath',
  celebration: 'smile',
  species: 'Fern',
  stage: GrowthStage.seed,
  status: 'active',
  practiceCount: days,
  recentPractice: days,
  lastReason: reason,
);

void main() {
  final start = DateTime(2026, 10, 10, 12);
  test(
    'six hidden action badges, positive practice and nonconsecutive roots',
    () {
      expect(badgeCatalog.length, 6);
      expect(eligibleBadges([], reflected: false), isEmpty);
      expect(eligibleBadges([recipe('a')], reflected: false), ['first-seed']);
      expect(
        eligibleBadges([recipe('a', days: 3), recipe('b')], reflected: true),
        containsAll([
          'first-seed',
          'possibilities',
          'tiny-win',
          'roots',
          'thoughtful',
        ]),
      );
      expect(eligibleBadges([], reflected: false, edited: true), [
        'making-yours',
      ]);
    },
  );
  test('priority and overload protect autonomy', () {
    expect(nextCoach([], weeklyDue: true).rule, CoachRule.firstSeed);
    expect(
      nextCoach([recipe('a', days: 3)], weeklyDue: false).rule,
      CoachRule.anotherSeed,
    );
    expect(
      nextCoach([recipe('a'), recipe('b'), recipe('c')], weeklyDue: false).rule,
      CoachRule.anchor,
    );
    expect(
      nextCoach([recipe('a', reason: 'too hard')], weeklyDue: true).rule,
      CoachRule.friction,
    );
  });
  test('exact day, rolling week, per-rule and clock rollback caps', () {
    var state = CoachState();
    expect(state.canSuggest(CoachRule.firstSeed, start), isTrue);
    state = state.exposed(CoachRule.firstSeed, start);
    expect(
      state.canSuggest(CoachRule.anchor, start.add(const Duration(hours: 1))),
      isFalse,
    );
    expect(
      state.canSuggest(CoachRule.firstSeed, start.add(const Duration(days: 6))),
      isFalse,
    );
    expect(
      state.canSuggest(CoachRule.firstSeed, start.add(const Duration(days: 7))),
      isTrue,
    );
    state = state.exposed(CoachRule.anchor, start.add(const Duration(days: 1)));
    state = state.exposed(
      CoachRule.reflection,
      start.add(const Duration(days: 2)),
    );
    expect(
      state.canSuggest(CoachRule.friction, start.add(const Duration(days: 3))),
      isFalse,
    );
    expect(
      state.canSuggest(CoachRule.friction, start.add(const Duration(days: 7))),
      isTrue,
    );
    expect(
      state.canSuggest(
        CoachRule.friction,
        start.subtract(const Duration(days: 1)),
      ),
      isFalse,
    );
    expect(CoachState.decode(state.encode()).encode(), state.encode());
    expect(() => CoachState.decode('{"version":99}'), throwsFormatException);
  });
  test('local rewards persist once, survive undo and never sync', () async {
    final store = await GardenStore.open(':memory:', 'device-guest');
    addTearDown(store.close);
    await store.refreshCoach();
    final habit = await store.plant(
      aspiration: 'Calm',
      anchor: 'put my cup away',
      behavior: 'breathe',
      celebration: 'smile',
      species: 'Fern',
    );
    expect((await store.refreshCoach()).newBadges.map((b) => b.id), [
      'first-seed',
    ]);
    expect((await store.refreshCoach()).newBadges, isEmpty);
    await store.checkIn(habit.id, CheckInResult.did);
    expect((await store.refreshCoach()).newBadges.map((b) => b.id), [
      'tiny-win',
    ]);
    await store.undo(habit.id);
    expect(
      (await store.refreshCoach()).state.earned.keys,
      contains('tiny-win'),
    );
    final exported = await store.export();
    expect(
      (exported['settings'] as List).any((r) => r['key'] == coachStateKey),
      isTrue,
    );
    final payload = await store.syncPayload();
    expect(payload.toString(), isNot(contains(coachStateKey)));
    await store.switchAccount('other');
    expect((await store.refreshCoach()).state.earned, isEmpty);
    await store.switchAccount('device-guest');
    expect((await store.refreshCoach()).state.earned.length, 2);
    await store.deleteLocalAccount();
    expect(await store.setting(coachStateKey), isNull);
  });
  test(
    'existing garden backfills quietly, repeated concurrent claims are capped',
    () async {
      final store = await GardenStore.open(':memory:', 'synthetic-coach');
      addTearDown(store.close);
      await store.plant(
        aspiration: 'Calm',
        anchor: 'put my cup away',
        behavior: 'breathe',
        celebration: 'smile',
        species: 'Fern',
      );
      final update = await store.refreshCoach();
      expect(update.state.earned.keys, ['first-seed']);
      expect(update.newBadges, isEmpty);
      final claims = await Future.wait([
        store.claimCoachSuggestion(CoachRule.anchor, now: start),
        store.claimCoachSuggestion(CoachRule.anchor, now: start),
      ]);
      expect(claims.where((v) => v).length, 1);
      await store.setCoachPreferences(suggestions: false);
      expect(
        await store.claimCoachSuggestion(
          CoachRule.friction,
          now: start.add(const Duration(days: 8)),
        ),
        isFalse,
      );
    },
  );
  test('adjustment is atomic, meaningful, once-only and no habit reference retained', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-edit');
    addTearDown(store.close);
    final h = await store.plant(
      aspiration: 'Calm',
      anchor: 'put my cup away',
      behavior: 'breathe',
      celebration: 'smile',
      species: 'Fern',
    );
    await store.refreshCoach();
    expect(
      (await store.edit(
        h,
        anchor: h.anchor,
        behavior: h.behavior,
        celebration: h.celebration,
      )).newBadges,
      isEmpty,
    );
    expect(
      (await store.edit(
        h,
        anchor: h.anchor,
        behavior: 'one breath',
        celebration: h.celebration,
      )).newBadges.single.id,
      'making-yours',
    );
    expect(
      (await store.refreshCoach()).state.earned.keys,
      contains('making-yours'),
    );
    await store.deleteRecord('habits', h.id);
    final state = (await store.refreshCoach()).state;
    expect(state.earned.keys, contains('making-yours'));
    expect(state.encode(), isNot(contains(h.id)));
  });
  test(
    'practice days are distinct, didMore is not a bonus, rest does not revoke',
    () async {
      final store = await GardenStore.open(':memory:', 'synthetic-practice');
      addTearDown(store.close);
      await store.refreshCoach();
      final h = await store.plant(
        aspiration: 'Calm',
        anchor: 'put my cup away',
        behavior: 'breathe',
        celebration: 'smile',
        species: 'Fern',
      );
      await store.refreshCoach();
      final date = DateTime.now();
      for (final day in [8, 5, 1]) {
        final at = date.subtract(Duration(days: day));
        await store.checkIn(h.id, CheckInResult.did, now: at);
        await store.checkIn(h.id, CheckInResult.didMore, now: at);
      }
      expect(
        (await store.refreshCoach()).newBadges.map((b) => b.id),
        containsAll(['tiny-win', 'roots']),
      );
      await store.checkIn(
        h.id,
        CheckInResult.notToday,
        now: date.subtract(const Duration(days: 1)),
      );
      expect((await store.refreshCoach()).state.earned.keys, contains('roots'));
      await store.completeWeeklyReflection(h.id);
      expect((await store.refreshCoach()).newBadges.single.id, 'thoughtful');
      await store.setCoachPreferences(reveals: false);
      await store.plant(
        aspiration: 'Focus',
        anchor: 'sit down',
        behavior: 'write one word',
        celebration: 'smile',
        species: 'Fern',
      );
      final quiet = await store.refreshCoach();
      expect(quiet.newBadges, isEmpty);
      expect(quiet.state.earned.keys, contains('possibilities'));
    },
  );
  test(
    'disk reopen preserves earned state, choices and dismissal cadence',
    () async {
      final dir = await Directory.systemTemp.createTemp('bloomstep-coach-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}garden.sqlite';
      var store = await GardenStore.open(path, 'synthetic-reopen');
      await store.refreshCoach();
      await store.plant(
        aspiration: 'Calm',
        anchor: 'put my cup away',
        behavior: 'breathe',
        celebration: 'smile',
        species: 'Fern',
      );
      await store.refreshCoach();
      expect(
        await store.claimCoachSuggestion(CoachRule.anchor, now: start),
        isTrue,
      );
      await store.setCoachPreferences(suggestions: false, reveals: false);
      await store.close();
      store = await GardenStore.open(path, 'synthetic-reopen');
      addTearDown(store.close);
      final restored = await store.refreshCoach();
      expect(restored.state.earned.keys, ['first-seed']);
      expect(restored.newBadges, isEmpty);
      expect(restored.state.suggestions, isFalse);
      expect(restored.state.reveals, isFalse);
      await store.setCoachPreferences(suggestions: true);
      expect(
        await store.claimCoachSuggestion(CoachRule.friction, now: start),
        isFalse,
      );
    },
  );
  test(
    'unsupported persisted state is surfaced, never reset as success',
    () async {
      final store = await GardenStore.open(':memory:', 'synthetic-corrupt');
      addTearDown(store.close);
      await store.setSetting(coachStateKey, '{"version":99}');
      expect(store.refreshCoach(), throwsFormatException);
      expect(
        store.claimCoachSuggestion(CoachRule.anchor),
        throwsFormatException,
      );
      expect(await store.setting(coachStateKey), '{"version":99}');
    },
  );
}
