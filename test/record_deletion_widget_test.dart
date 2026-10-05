import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final remove = find.byTooltip('Delete this recipe').first;
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.textContaining('Deletion cannot be undone'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect((await tester.runAsync(store.habits))!, hasLength(2));
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete recipe'));
      await _settle(tester);
      expect((await tester.runAsync(store.habits))!.single.id, before.last.id);
      final export = (await tester.runAsync(store.export))!;
      expect((export['deletions'] as List).single['recordId'], before.first.id);
      expect(find.byTooltip('Delete this recipe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'private feedback deletion requires confirmation and preserves other feedback',
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
      final before = (await tester.runAsync(store.voice))!;
      final removed = before.first['id'];
      final preserved = before.last;
      await tester.pumpWidget(MaterialApp(home: GardenScreen(store: store)));
      await _settle(tester);
      await tester.tap(find.byTooltip('Help us grow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      await tester.tap(find.byTooltip('Delete this feedback').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('private replies'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect((await tester.runAsync(store.voice))!, hasLength(2));
      await tester.tap(find.byTooltip('Delete this feedback').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete feedback'));
      await _settle(tester);
      final remaining = (await tester.runAsync(store.voice))!.single;
      expect(remaining['id'], preserved['id']);
      expect(remaining['body'], preserved['body']);
      expect(
        ((await tester.runAsync(store.export))!['deletions'] as List)
            .single['recordId'],
        removed,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
