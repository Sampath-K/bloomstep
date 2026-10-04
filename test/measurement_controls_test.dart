import 'dart:convert';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/measurement_controls.dart';
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
            pickReceipt: () async => stableReceipt,
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
    final store = await mount(tester, consent: true);
    await tester.tap(find.text('Link my exported website receipt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() => store.setSetting('analytics', 'false'));
    await tester.tap(find.text('Link to this account'));
    await finishAction(tester);
    expect(find.textContaining('Receipt action failed:'), findsOneWidget);
    expect((await tester.runAsync(store.export))!['events'], isEmpty);
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
    expect(
      find.textContaining('Invalid, expired or unsupported'),
      findsOneWidget,
    );
    expect(find.textContaining('private_error_receipt_content'), findsNothing);
  });
}
