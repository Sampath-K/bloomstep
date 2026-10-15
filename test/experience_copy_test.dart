import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/experience_copy.dart';
import 'package:bloomstep/services/experience_experiments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'actual visible render records once; withdrawal restores control immediately',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final now = DateTime.utc(2026, 10, 1);
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'a', clock: () => now),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.runAsync(() => store.setSetting('analytics', 'true'));
      final experiments = ExperienceExperiments(
        store,
        config: ExperienceConfig.synthetic(
          ExperienceSurface.invitationHeading,
          startAt: now,
        ),
        clock: () => now,
      );
      ExperienceAssignment? observed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExperienceCopy(
              experiments: experiments,
              surface: ExperienceSurface.invitationHeading,
              onAssignment: (value) => observed = value,
              builder: (context, copy) =>
                  Semantics(header: true, child: Text(copy)),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(observed, isNotNull);
      final saved = (await tester.runAsync(store.export))!;
      expect(
        (saved['events'] as List).where(
          (e) => (e as Map)['name'] == 'experience_observation',
        ),
        hasLength(1),
      );
      await tester.runAsync(() => store.setSetting('analytics', 'false'));
      await tester.pump();
      expect(find.text('A little growth, together'), findsOneWidget);
      expect(observed, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('offstage and disposed copy cannot claim visible exposure', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final now = DateTime.utc(2026, 10, 1);
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'a', clock: () => now),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.runAsync(() => store.setSetting('analytics', 'true'));
    final experiments = ExperienceExperiments(
      store,
      config: ExperienceConfig.synthetic(
        ExperienceSurface.invitationHeading,
        startAt: now,
      ),
      clock: () => now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Offstage(
            child: ExperienceCopy(
              experiments: experiments,
              surface: ExperienceSurface.invitationHeading,
              builder: (context, copy) => Text(copy),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final saved = (await tester.runAsync(store.export))!;
    expect(
      (saved['events'] as List).where(
        (e) => (e as Map)['name'] == 'experience_observation',
      ),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
