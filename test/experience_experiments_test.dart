import 'dart:convert';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/services/experience_experiments.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<Map<String, dynamic>>> observations(GardenStore store) async =>
    ((await store.export())['events'] as List)
        .cast<Map>()
        .where((e) => e['name'] == 'experience_observation')
        .map(
          (e) => jsonDecode(e['properties'] as String) as Map<String, dynamic>,
        )
        .toList();

void main() {
  final start = DateTime.utc(2026, 10, 1);
  late DateTime now;
  late GardenStore store;
  late ExperienceExperiments experiments;
  setUp(() async {
    now = start;
    store = await GardenStore.open(':memory:', 'a', clock: () => now);
    experiments = ExperienceExperiments(
      store,
      config: ExperienceConfig.synthetic(
        ExperienceSurface.gardenPrompt,
        startAt: start,
      ),
      clock: () => now,
    );
  });
  tearDown(() => store.close());

  test(
    'off, guest, expired and absent consent are noncollecting control',
    () async {
      expect(
        (await experiments.resolve(ExperienceSurface.gardenPrompt)).active,
        false,
      );
      expect(await observations(store), isEmpty);
      await store.setSetting('analytics', 'true');
      expect(
        (await ExperienceExperiments(store)
                .resolve(ExperienceSurface.gardenPrompt))
            .active,
        false,
      );
      now = start.add(const Duration(days: 29));
      expect(
        (await experiments.resolve(ExperienceSurface.gardenPrompt)).active,
        false,
      );
      await store.switchAccount('device-guest');
      await store.setSetting('analytics', 'true');
      expect(
        (await experiments.resolve(ExperienceSurface.gardenPrompt)).active,
        false,
      );
      expect(await observations(store), isEmpty);
    },
  );

  test(
    'stable assignment, rendered-only exposure and idempotent outcomes',
    () async {
      await store.setSetting('analytics', 'true');
      final a = await experiments.resolve(ExperienceSurface.gardenPrompt);
      final b = await experiments.resolve(ExperienceSurface.gardenPrompt);
      expect(a.active, true);
      expect(a.cohortId, b.cohortId);
      expect(a.arm, b.arm);
      expect(await observations(store), isEmpty);
      expect(
        await experiments.outcome(a, ExperienceOutcome.taskCompleted),
        false,
      );
      expect(await experiments.rendered(a), true);
      expect(await experiments.rendered(b), true);
      expect(
        await experiments.outcome(a, ExperienceOutcome.taskCompleted),
        true,
      );
      expect(
        await experiments.outcome(a, ExperienceOutcome.taskCompleted),
        true,
      );
      expect((await observations(store)).map((e) => e['experienceOutcome']), [
        'rendered',
        'task_completed',
      ]);
    },
  );

  test(
    'withdrawal purges local scope and outbox; stale handle cannot replay',
    () async {
      await store.setSetting('analytics', 'true');
      final a = await experiments.resolve(ExperienceSurface.gardenPrompt);
      await experiments.rendered(a);
      await store.setSetting('analytics', 'false');
      expect(await observations(store), isEmpty);
      final pending = (await store.syncPayload())['deletions'] as List;
      expect(pending, hasLength(1));
      expect((pending.single as Map)['type'], 'experienceEvents');
      expect((pending.single as Map)['recordId'], a.consentEpoch);
      await store.setSetting('analytics', 'false');
      expect((await store.syncPayload())['deletions'], hasLength(1));
      expect(await experiments.rendered(a), false);
      await store.setSetting('analytics', 'true');
      expect(await experiments.rendered(a), false);
      final b = await experiments.resolve(ExperienceSurface.gardenPrompt);
      expect(b.cohortId, isNot(a.cohortId));
      await store.switchAccount('b');
      expect(await experiments.rendered(b), false);
    },
  );

  test('one study per consent scope, kill, clock regression and stale config fail closed', () async {
    await store.setSetting('analytics', 'true');
    final a = await experiments.resolve(ExperienceSurface.gardenPrompt);
    final other = ExperienceExperiments(
      store,
      config: ExperienceConfig.synthetic(
        ExperienceSurface.invitationHeading,
        startAt: start,
      ),
      clock: () => now,
    );
    expect(
      (await other.resolve(ExperienceSurface.invitationHeading)).active,
      false,
    );
    expect(await ExperienceExperiments(store).rendered(a), false);
    now = start.subtract(const Duration(seconds: 1));
    expect(await experiments.rendered(a), false);
    expect(await observations(store), isEmpty);
  });

  test('practice needs saved effective checkin and mature followup, not share/click', () async {
    await store.setSetting('analytics', 'true');
    final a = await experiments.resolve(ExperienceSurface.gardenPrompt);
    await experiments.rendered(a);
    final habit = await store.plant(
      aspiration: 'private',
      anchor: 'private',
      behavior: 'private',
      celebration: 'private',
      species: 'Fern',
    );
    now = start.add(const Duration(days: 1));
    await store.checkIn(habit.id, CheckInResult.did);
    await store.undo(habit.id);
    expect(
      (await observations(store))
          .any((e) => e['experienceOutcome'] == 'practice'),
      false,
    );
    now = start.add(const Duration(days: 7));
    await experiments.followup();
    final rows = await observations(store);
    expect(rows.map((e) => e['experienceOutcome']), [
      'rendered',
      'task_completed',
      'followup',
    ]);
    expect(jsonEncode(rows), isNot(contains('private')));
    expect(jsonEncode(rows), isNot(contains(habit.id)));
    await experiments.followup();
    expect(await observations(store), hasLength(3));
  });

  test('positive practice after exposure inside window is observed once after restart seam', () async {
    await store.setSetting('analytics', 'true');
    final a = await experiments.resolve(ExperienceSurface.gardenPrompt);
    await experiments.rendered(a);
    final habit = await store.plant(
      aspiration: 'x',
      anchor: 'x',
      behavior: 'x',
      celebration: 'x',
      species: 'Fern',
    );
    now = start.add(const Duration(days: 2));
    await store.checkIn(habit.id, CheckInResult.didMore);
    now = start.add(const Duration(days: 7));
    final recreated = ExperienceExperiments(
      store,
      config: experiments.config,
      clock: () => now,
    );
    await recreated.followup();
    expect((await observations(store)).map((e) => e['experienceOutcome']), [
      'rendered',
      'task_completed',
      'followup',
      'practice',
    ]);
  });

  test(
    'generic track cannot forge observations or arbitrary properties',
    () async {
      await store.setSetting('analytics', 'true');
      await expectLater(
        store.track('experience_observation'),
        throwsArgumentError,
      );
      final a = await experiments.resolve(ExperienceSurface.gardenPrompt);
      await experiments.rendered(a);
      final p = (await observations(store)).single;
      await expectLater(
        store.track('experience_observation', properties: p),
        throwsStateError,
      );
      await expectLater(
        store.track(
          'experience_observation',
          properties: {...p, 'email': 'private'},
        ),
        throwsArgumentError,
      );
    },
  );
}
