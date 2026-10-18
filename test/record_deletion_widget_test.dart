import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dialog_copy_contract.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'recipe deletion is accessible, cancelable and limited to the selected recipe',
    (tester) async {
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'delete-ui'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await store.setSetting('reducedMotion', 'true');
        for (final anchor in [
          'First synthetic anchor',
          'Preserved synthetic anchor',
        ]) {
          await store.plant(
            aspiration: 'Synthetic',
            anchor: anchor,
            behavior: 'step',
            celebration: 'smile',
            species: 'Fern',
          );
        }
      });
      final before = (await tester.runAsync(store.habits))!;
      await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
      await _settle(tester);
      final remove = find.byTooltip('More for Synthetic').first;
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete this recipe'));
      await tester.pumpAndSettle();
      expect(find.text('Delete recipe?'), findsOneWidget);
      expect(
        find.text('This also deletes its check-ins and reflections.'),
        findsOneWidget,
      );
      expectConciseDialogCopy(
        'This also deletes its check-ins and reflections.',
      );
      expect(find.textContaining('event records'), findsNothing);
      expect(find.textContaining('ID-only'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect((await tester.runAsync(store.habits))!, hasLength(2));
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete this recipe'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _settle(tester);
      expect((await tester.runAsync(store.habits))!.single.id, before.last.id);
      final export = (await tester.runAsync(store.export))!;
      expect((export['deletions'] as List).single['recordId'], before.first.id);
      expect(find.byTooltip('More for Synthetic'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'general feedback does not expose a feedback history or deletion list',
    (tester) async {
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'delete-voice-ui'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await store.submitVoice('Idea', 'Synthetic keep');
        await store.submitVoice('Bug', 'Synthetic remove');
      });
      await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
      await _settle(tester);
      await tester.tap(find.byTooltip('Help us grow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await _settle(tester);
      expect(find.text('My feedback'), findsNothing);
      expect(find.byTooltip('Delete this feedback'), findsNothing);
      expect((await tester.runAsync(store.voice))!, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
