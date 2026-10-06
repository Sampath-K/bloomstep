import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';

import '../integration_test/support/test_only_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('test auth fails closed for a missing key and email-like names', (
    tester,
  ) async {
    final runRoot = await Directory.systemTemp.createTemp('bloomstep-it-');
    addTearDown(() => runRoot.delete(recursive: true));
    await tester.pumpWidget(
      TestOnlyBloomstepApp(runRoot: runRoot, expectedSecret: null),
    );
    expect(find.text('Test sign-in is unavailable.'), findsOneWidget);
    expect(find.byKey(TestOnlyAuthGate.usernameFieldKey), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue to test garden'),
          )
          .onPressed,
      isNull,
    );
    expect(await runRoot.list().toList(), isEmpty);
  });

  testWidgets(
    'test auth rejects wrong keys and real-account-shaped usernames',
    (tester) async {
      final random = Random.secure();
      final expected = List.generate(
        64,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      final runRoot = await Directory.systemTemp.createTemp('bloomstep-it-');
      addTearDown(() => runRoot.delete(recursive: true));
      await tester.pumpWidget(
        TestOnlyBloomstepApp(runRoot: runRoot, expectedSecret: expected),
      );
      await tester.enterText(
        find.byKey(TestOnlyAuthGate.usernameFieldKey),
        'person@example.com',
      );
      await tester.enterText(
        find.byKey(TestOnlyAuthGate.secretFieldKey),
        expected,
      );
      await tester.tap(find.text('Continue to test garden'));
      await tester.pumpAndSettle();
      expect(
        find.text('Use a synthetic username, not an email address.'),
        findsOneWidget,
      );
      expect(await runRoot.list().toList(), isEmpty);

      await tester.enterText(
        find.byKey(TestOnlyAuthGate.usernameFieldKey),
        'synthetic-a',
      );
      await tester.enterText(
        find.byKey(TestOnlyAuthGate.secretFieldKey),
        'wrong-secret',
      );
      await tester.tap(find.text('Continue to test garden'));
      await tester.pumpAndSettle();
      expect(
        find.text('Test sign-in failed. No garden was opened.'),
        findsOneWidget,
      );
      expect(find.byType(GardenScreen), findsNothing);
      expect(await runRoot.list().toList(), isEmpty);
    },
  );
}
