import 'dart:io';

import 'package:budlark/app/budlark_app.dart';
import 'package:budlark/core/garden_store.dart';
import 'package:budlark/features/garden/recipe_builder.dart';
import 'package:budlark/services/identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _WelcomeIdentity extends IdentityService {
  bool active = false;
  int attempts = 0;
  @override
  bool get configured => true;
  @override
  bool get hasValidSession => active;
  @override
  IdentityProfile? get profile => null;
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
      Future<void> waitFor(Finder finder) async {
        for (var attempt = 0; attempt < 500; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('Timed out waiting for $finder');
      }

      await tester.binding.setSurfaceSize(const Size(1100, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sign-in-first-'),
      ))!;
      addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
      final identity = _WelcomeIdentity();
      await tester.pumpWidget(MaterialApp(
        home: HabitHome(
          testIdentity: identity,
          testOpenStore: (account) =>
              GardenStore.open(p.join(directory.path, '$account.sqlite'), account),
        ),
      ));
      await waitFor(find.byWidgetPredicate(
        (widget) => widget is FilledButton && widget.onPressed != null,
      ));
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
        await waitFor(find.byType(RecipeBuilder));
        expect(find.text('Sign in to grow'), findsNothing);
        expect(identity.attempts, 0);
      } else {
        await tester.tap(find.text('Sign in to grow'));
        await waitFor(find.byType(RecipeBuilder));
        expect(identity.attempts, 1);
        expect(find.text('Sign in to grow'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
    });
  }
}
