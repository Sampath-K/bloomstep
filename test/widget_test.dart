import 'package:bloomstep/app/bloomstep_app.dart';
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unconfigured release is sign-in gated without fake login', (
    tester,
  ) async {
    await tester.pumpWidget(const BloomstepApp());
    await tester.pumpAndSettle();
    expect(find.text('Bloomstep'), findsOneWidget);
    expect(
      find.textContaining('sign-in is not yet configured'),
      findsOneWidget,
    );
    expect(find.text('Plant a habit'), findsNothing);
  });

  testWidgets('plant, celebrate, edit today and undo through the real UI', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'test-only-account'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => store.setSetting('analytics', 'true'));
    await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
    Future<void> waitForReady(
      Finder finder, {
      Future<bool> Function()? databaseReady,
      bool celebrationClosed = false,
    }) async {
      final deadline = Stopwatch()..start();
      while (deadline.elapsed < const Duration(seconds: 10)) {
        // SQLite uses real asynchronous work, outside the widget fake clock.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        final matches = finder.evaluate().toList();
        final enabled =
            matches.isNotEmpty &&
            matches.every((element) {
              final widget = element.widget;
              ButtonStyleButton? button = widget is ButtonStyleButton
                  ? widget
                  : null;
              if (button == null) {
                element.visitAncestorElements((ancestor) {
                  if (ancestor.widget is ButtonStyleButton) {
                    button = ancestor.widget as ButtonStyleButton;
                    return false;
                  }
                  return true;
                });
              }
              return button == null || button?.onPressed != null;
            });
        if (enabled &&
            (!celebrationClosed || find.byType(SnackBar).evaluate().isEmpty) &&
            (databaseReady == null ||
                (await tester.runAsync(databaseReady) ?? false))) {
          return;
        }
      }
      fail('UI/database readiness timed out after 10 seconds: $finder');
    }

    await waitForReady(find.text('Plant a habit'));
    await tester.tap(find.text('Plant a habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Calm'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I practiced my celebration'));
    await tester.tap(find.text('I practiced my celebration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plant this seed'));
    await waitForReady(
      find.text('Did it'),
      databaseReady: () async => (await store.habits()).length == 1,
    );
    expect((await tester.runAsync(store.habits))!.length, 1);
    final planted =
        ((await tester.runAsync(store.syncPayload))!['events'] as List);
    expect(
      planted.where((r) => r['name'] == 'celebration_practiced'),
      hasLength(1),
    );
    expect(
      planted.singleWhere((r) => r['name'] == 'recipe_created')['properties'],
      containsPair('templateCategory', 'calm'),
    );
    await tester.tap(find.text('Did it'));
    await waitForReady(
      find.text('Undo today'),
      databaseReady: () async =>
          (await store.habits()).single.practiceCount == 1,
    );
    expect((await tester.runAsync(store.habits))!.single.practiceCount, 1);
    expect(find.textContaining('relax my shoulders'), findsWidgets);
    await waitForReady(find.text('Undo today'), celebrationClosed: true);
    await tester.ensureVisible(find.text('Undo today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo today'));
    await waitForReady(
      find.text('Did it'),
      databaseReady: () async =>
          (await store.habits()).single.practiceCount == 0,
    );
    expect((await tester.runAsync(store.habits))!.single.practiceCount, 0);
    final recorded =
        ((await tester.runAsync(store.syncPayload))!['events'] as List);
    expect(recorded.where((r) => r['name'] == 'first_checkin'), hasLength(1));
    expect(recorded.where((r) => r['name'] == 'checkin'), hasLength(2));
  });
}
