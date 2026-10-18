import 'dart:io';

import 'package:budlark/core/garden_store.dart';
import 'package:budlark/core/growthbook_experience_provider.dart';
import 'package:budlark/services/experience_experiments.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProvider implements ExperienceAssignmentProvider {
  _FakeProvider(this.arm, {this.fail = false});
  final ExperienceArm? arm;
  final bool fail;
  @override
  String get id => 'test-replacement';
  @override
  ExperienceArm? evaluate(ExperienceConfig config, String subject) {
    if (fail) {
      throw const SocketException(
        'Synthetic unavailable configuration transport',
      );
    }
    return arm;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 1);
  final config = ExperienceConfig.synthetic(
    ExperienceSurface.gardenPrompt,
    startAt: now,
  );
  test('official GrowthBook SDK local fixture is deterministic and does not evaluate OFF', () {
    const provider = GrowthBookExperienceProvider();
    expect(provider.evaluate(ExperienceConfig.off, 'subject'), null);
    expect(provider.evaluate(config, ''), null);
    final results = <ExperienceArm>{};
    for (var i = 0; i < 100; i++) {
      final arm = provider.evaluate(config, 'synthetic-consent-unit-$i');
      expect(arm, isNotNull);
      expect(provider.evaluate(config, 'synthetic-consent-unit-$i'), arm);
      results.add(arm!);
    }
    expect(results, {ExperienceArm.control, ExperienceArm.candidate});
  });
  test('swap provider without UI changes; no fallback to competing custom bucketing', () async {
    final store = await GardenStore.open(
      ':memory:',
      'synthetic',
      clock: () => now,
    );
    addTearDown(store.close);
    await store.setSetting('analytics', 'true');
    final service = ExperienceExperiments(
      store,
      config: config,
      provider: _FakeProvider(ExperienceArm.candidate),
      clock: () => now,
    );
    final assignment = await service.resolve(ExperienceSurface.gardenPrompt);
    expect(assignment.arm, ExperienceArm.candidate);
    expect(
      ((await store.syncPayload())['events'] as List).where(
        (row) => (row as Map)['name'] == 'experience_observation',
      ),
      isEmpty,
    );
    expect(await service.rendered(assignment), true);
    final next = ExperienceExperiments(
      store,
      config: config,
      provider: const GrowthBookExperienceProvider(),
      clock: () => now,
    );
    expect((await next.resolve(ExperienceSurface.gardenPrompt)).active, false);
    expect(await next.rendered(assignment), false);
  });
  test('missing provider result stays control; network failure is explicit and cannot expose', () async {
    for (final fail in [false, true]) {
      final store = await GardenStore.open(
        ':memory:',
        'synthetic',
        clock: () => now,
      );
      try {
        await store.setSetting('analytics', 'true');
        final service = ExperienceExperiments(
          store,
          config: config,
          provider: _FakeProvider(null, fail: fail),
          clock: () => now,
        );
        if (fail) {
          await expectLater(
            service.resolve(ExperienceSurface.gardenPrompt),
            throwsA(isA<SocketException>()),
          );
        } else {
          expect(
            (await service.resolve(ExperienceSurface.gardenPrompt)).active,
            false,
          );
        }
        expect(
          ((await store.syncPayload())['events'] as List).where(
            (row) => (row as Map)['name'] == 'experience_observation',
          ),
          isEmpty,
        );
      } finally {
        await store.close();
      }
    }
  });
}
