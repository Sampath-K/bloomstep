import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('seven unanswered requests explain pause and let user reset it', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'pause-ui'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    final h = (await tester.runAsync(
      () => store.plant(
        aspiration: 'Calm',
        anchor: 'coffee',
        behavior: 'breathe',
        celebration: 'smile',
        species: 'Fern',
      ),
    ))!;
    await tester.runAsync(() => store.setSetting('ignored:${h.id}', '7'));
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
    }

    await settle();
    expect(find.textContaining('Reminders are paused'), findsOneWidget);
    expect(find.text('Resume gentle reminders'), findsOneWidget);
    await tester.ensureVisible(find.text('Resume gentle reminders'));
    await tester.tap(find.text('Resume gentle reminders'));
    await settle();
    expect(await tester.runAsync(() => store.setting('ignored:${h.id}')), '0');
    expect(find.textContaining('Reminders are paused'), findsNothing);
    expect(await tester.runAsync(() => store.setting('reminders')), isNull);
  });
}
