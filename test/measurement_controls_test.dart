import 'dart:convert';

import 'package:budlark/core/garden_store.dart';
import 'package:budlark/features/garden/measurement_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> finishAction(WidgetTester tester) async {
    final timer = Stopwatch()..start();
    do {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    } while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
        timer.elapsed < const Duration(seconds: 10));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
  }

  String receipt() {
    final time = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 1))
        .toIso8601String();
    return jsonEncode({
      'schemaVersion': 1,
      'source': 'website',
      'consentedAt': time,
      'events': [
        {
          'id': '00000000-0000-4000-8000-000000000001',
          'name': 'landing_view',
          'ts': time,
        },
      ],
    });
  }

  Future<GardenStore> mount(
    WidgetTester tester, {
    required bool consent,
    String? text,
    Object? pickerError,
  }) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'synthetic-controls'),
    ))!;
    final stableReceipt = text ?? receipt();
    addTearDown(() => tester.runAsync(store.close));
    if (consent) {
      await tester.runAsync(() => store.setSetting('analytics', 'true'));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeasurementControls(
            store: store,
            analytics: consent,
            pickReceipt: () async {
              if (pickerError != null) throw pickerError;
              return stableReceipt;
            },
          ),
        ),
      ),
    );
    return store;
  }

  testWidgets(
    'account consent is independent of source receipt and defaults off',
    (tester) async {
      final store = await mount(tester, consent: false);
      await tester.tap(find.text('Link my exported website receipt'));
      await tester.pumpAndSettle();
      expect(find.text('Link to this account'), findsNothing);
      expect((await tester.runAsync(store.export))!['events'], isEmpty);
      expect(
        find.text('Enable account product-event consent first.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'actual link disclosure/cancel/retry keeps original events idempotent',
    (tester) async {
      final store = await mount(tester, consent: true);
      await tester.tap(find.text('Link my exported website receipt'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.textContaining('currently signed-in'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(store.export))!['events'] as List,
        hasLength(1),
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Link my exported website receipt'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('Link to this account'));
        await finishAction(tester);
      }
      expect(
        (await tester.runAsync(store.export))!['events'] as List,
        hasLength(2),
      );
      expect(find.textContaining('Already linked'), findsOneWidget);
    },
  );
  testWidgets('consent removed during confirmation surfaces a failure', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final store = await mount(tester, consent: true);
    await tester.tap(find.text('Link my exported website receipt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() => store.setSetting('analytics', 'false'));
    await tester.tap(find.text('Link to this account'));
    await finishAction(tester);
    const failure =
        'Couldn’t link this receipt. Check that it is valid and current, and that account product-event consent is on, then try again.';
    expect(find.text(failure), findsOneWidget);
    expect(find.textContaining('Receipt action failed:'), findsNothing);
    expect(
      tester.getSemantics(find.text(failure)).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect((await tester.runAsync(store.export))!['events'], isEmpty);
    semantics.dispose();
  });
  testWidgets('invalid receipt surfaces a privacy-safe failure', (
    tester,
  ) async {
    await mount(
      tester,
      consent: true,
      text: '{"email":"private_error_receipt_content"}',
    );
    await tester.tap(find.text('Link my exported website receipt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn’t link this receipt.'), findsOneWidget);
    expect(find.textContaining('private_error_receipt_content'), findsNothing);
  });
  testWidgets('picker exceptions show safe failure, not success or details', (
    tester,
  ) async {
    await mount(
      tester,
      consent: true,
      pickerError: StateError('private_picker_path_and_token'),
    );
    await tester.tap(find.text('Link my exported website receipt'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Couldn’t link this receipt. Check that it is valid and current, and that account product-event consent is on, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('private_picker_path_and_token'), findsNothing);
    expect(find.textContaining('observations linked'), findsNothing);
    expect(find.text('Link to this account'), findsNothing);
  });
}
