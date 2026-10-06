import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';

import '../integration_test/support/test_only_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('test auth accepts only 256-bit hexadecimal keys', () {
    final key = List.filled(64, 'a').join();
    expect(TestOnlyAuthGate.validTestSecret(key), isTrue);
    expect(TestOnlyAuthGate.validTestSecret(key.substring(1)), isFalse);
    expect(TestOnlyAuthGate.validTestSecret('${key.substring(1)}g'), isFalse);
    expect(TestOnlyAuthGate.validTestSecret(null), isFalse);
  });

  testWidgets('test auth fails closed for a missing key and email-like names', (
    tester,
  ) async {
    final runRoot = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bloomstep-it-'),
    ))!;
    addTearDown(() => tester.runAsync(() => runRoot.delete(recursive: true)));
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
    expect((await tester.runAsync(() => runRoot.list().toList()))!, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets(
    'test auth rejects wrong keys and real-account-shaped usernames',
    (tester) async {
      final random = Random.secure();
      final expected = List.generate(
        64,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      final runRoot = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bloomstep-it-'),
      ))!;
      addTearDown(() => tester.runAsync(() => runRoot.delete(recursive: true)));
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
      expect((await tester.runAsync(() => runRoot.list().toList()))!, isEmpty);

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
      expect((await tester.runAsync(() => runRoot.list().toList()))!, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
