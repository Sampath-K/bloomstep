import 'package:budlark/app/budlark_app.dart';
import 'package:budlark/core/garden_store.dart';
import 'package:budlark/services/identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'garden_learning_test.dart' show fixture, settleDatabase;

class _WelcomeIdentity extends IdentityService {
  bool active = false;
  int attempts = 0;
  @override
  bool get configured => true;
  @override
  bool get hasValidSession => active;
  @override
  DateTime? get sessionExpiresAt => DateTime.now().add(const Duration(days: 1));
  @override
  Future<bool> restore() async => false;
  @override
  Future<void> signIn() async {
    attempts++;
    active = true;
    account = List.filled(64, 'a').join();
  }
  @override
  Future<void> checkpoint() async {}
  @override
  Future<void> signOut() async {
    active = false;
    account = null;
  }
}

void main() {
  for (final local in [false, true]) {
    testWidgets('first run ${local ? "keeps local-only in Advanced" : "encourages sign-in"}', (tester) async {
      await fixture(tester);
      final identity = _WelcomeIdentity();
      await tester.pumpWidget(MaterialApp(
        home: HabitHome(
          testIdentity: identity,
          testOpenStore: (account) => GardenStore.open(':memory:', account),
        ),
      ));
      await settleDatabase(tester);
      expect(find.text('Sign in to grow'), findsOneWidget);
      expect(find.text('Your garden, synced and safe across devices.'), findsOneWidget);
      expect(find.text('Use a device-only garden'), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? '').join(' ').split(RegExp(r'\s+')).length,
        lessThanOrEqualTo(20),
      );
      if (local) {
        await tester.tap(find.byTooltip('Settings and privacy'));
        await tester.pumpAndSettle();
        expect(find.text('Use a device-only garden'), findsNothing);
        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use a device-only garden'));
        await settleDatabase(tester);
        expect(find.text('Sign in to grow'), findsNothing);
        expect(identity.attempts, 0);
      } else {
        await tester.tap(find.text('Sign in to grow'));
        await settleDatabase(tester);
        expect(identity.attempts, 1);
        expect(find.text('Sign in to grow'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
