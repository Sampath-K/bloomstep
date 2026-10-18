import 'package:budlark/core/garden_store.dart';
import 'package:budlark/features/garden/experience_copy.dart';
import 'package:budlark/services/experience_experiments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineResolver implements ExperienceResolver {
  @override
  final ValueNotifier<int> changes = ValueNotifier(0);
  @override
  Duration get remainingEnrollment => Duration.zero;
  @override
  Future<void> followup() async {}
  @override
  Future<ExperienceAssignment> resolve(ExperienceSurface surface) async =>
      throw StateError('Synthetic offline provider configuration');
  @override
  Future<bool> rendered(ExperienceAssignment assignment) async =>
      throw StateError('Must not expose unresolved copy');
  @override
  Future<bool> outcome(
    ExperienceAssignment assignment,
    ExperienceOutcome outcome,
  ) async => false;
}

void main() {
  testWidgets(
    'replacement resolver failure surfaces error and leaves semantic control without exposure',
    (tester) async {
      final resolver = _OfflineResolver();
      addTearDown(resolver.changes.dispose);
      ExperienceAssignment? observed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExperienceCopy(
              experiments: resolver,
              surface: ExperienceSurface.invitationHeading,
              onAssignment: (value) => observed = value,
              builder: (context, copy) =>
                  Semantics(header: true, child: Text(copy)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
      expect(find.text('A little growth, together'), findsOneWidget);
      expect(observed, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
