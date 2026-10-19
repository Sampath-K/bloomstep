import 'dart:ui';

import 'package:budlark/core/garden_store.dart';
import 'package:budlark/core/models.dart';
import 'package:budlark/features/garden/garden_moment.dart';
import 'package:budlark/features/garden/garden_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('durable completion uses a finite native wall-clock moment',
      (tester) async {
    final store = await GardenStore.open(':memory:', 'native-calm-moment');
    addTearDown(store.close);
    await store.plant(
      aspiration: 'Calm',
      anchor: 'coffee',
      behavior: 'breathe',
      celebration: 'smile',
      species: 'Fern',
    );
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => timings.addAll(frames);
    binding.addTimingsCallback(collect);
    addTearDown(() => binding.removeTimingsCallback(collect));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: false),
        child: child!,
      ),
      home: GardenScreen(store: store, testDisableServices: true),
    ));
    Future<void> waitUntil(bool Function() ready) async {
      final deadline = Stopwatch()..start();
      while (!ready() && deadline.elapsed < const Duration(seconds: 5)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump();
      }
      expect(ready(), isTrue);
    }
    await waitUntil(() => find.text('I did it').evaluate().isNotEmpty);
    timings.clear();
    await tester.tap(find.text('I did it'));
    await waitUntil(() =>
        tester.widget<GardenMoment>(find.byType(GardenMoment)).completion !=
        null);
    final elapsed = Stopwatch()..start();
    double progress() => (tester
        .widget<AnimatedBuilder>(
          find.descendant(
            of: find.byType(GardenMoment),
            matching: find.byType(AnimatedBuilder),
          ),
        )
        .animation as Animation<double>).value;
    await waitUntil(() => progress() == 1);
    elapsed.stop();
    expect(elapsed.elapsedMilliseconds, inInclusiveRange(700, 1800));
    expect((await store.habits()).single.today, CheckInResult.did);
    await waitUntil(() =>
        !tester.widget<GardenMoment>(find.byType(GardenMoment)).animate);
    expect(tester.widget<GardenMoment>(find.byType(GardenMoment)).animate,
        isFalse);
    binding.reportData = {
      'completionWallMilliseconds': elapsed.elapsedMilliseconds,
      'frameTimingStatus': timings.isEmpty ? 'unknown' : 'measured',
      'frameCount': timings.length,
      if (timings.isNotEmpty)
        'maxBuildMicroseconds': timings
            .map((frame) => frame.buildDuration.inMicroseconds)
            .reduce((a, b) => a > b ? a : b),
      if (timings.isNotEmpty)
        'maxRasterMicroseconds': timings
            .map((frame) => frame.rasterDuration.inMicroseconds)
            .reduce((a, b) => a > b ? a : b),
    };
    expect(tester.takeException(), isNull);
  });
}
