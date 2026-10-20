import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Explicitly enters the production More disclosure for advanced-flow tests.
Future<void> openGardenMore(WidgetTester tester) async {
  final more = find.byKey(const ValueKey('garden-more'));
  if (more.evaluate().isEmpty) return;
  if (ModalRoute.of(tester.element(more))?.isCurrent != true) return;
  if (tester.widget<TextButton>(more).onPressed == null) return;
  await tester.ensureVisible(more);
  await tester.tap(more);
  await tester.pumpAndSettle();
}
