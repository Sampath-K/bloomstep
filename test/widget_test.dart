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
    await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
    Future<void> settleDatabase() async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
    }

    await settleDatabase();
    await tester.tap(find.text('Plant a habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Calm'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('I practiced my celebration'));
    await tester.tap(find.text('I practiced my celebration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plant this seed'));
    await settleDatabase();
    expect((await tester.runAsync(store.habits))!.length, 1);
    await tester.tap(find.text('Did it'));
    await settleDatabase();
    expect((await tester.runAsync(store.habits))!.single.practiceCount, 1);
    expect(find.textContaining('relax my shoulders'), findsWidgets);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Undo today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo today'));
    await settleDatabase();
    expect((await tester.runAsync(store.habits))!.single.practiceCount, 0);
  });
}
