import 'package:bloomstep/features/garden/reminder_observation_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'new reminder observation choice is unchecked independently of existing analytics consent',
    (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderObservationControls(
              analyticsEnabled: true,
              optedIn: false,
              onChanged: changes.add,
            ),
          ),
        ),
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(changes, isEmpty);
      expect(find.textContaining('Disclosure version 1'), findsOneWidget);
      expect(find.textContaining('not Windows permission'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      expect(changes, [true]);
    },
  );

  testWidgets(
    'analytics off cannot imply new consent even if a stale local flag was true',
    (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderObservationControls(
              analyticsEnabled: false,
              optedIn: true,
              onChanged: changes.add,
            ),
          ),
        ),
      );
      final choice = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(choice.value, isFalse);
      expect(choice.onChanged, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      expect(changes, isEmpty);
      expect(
        find.textContaining('Enable product event counts'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'current explicit choice can be revoked without forcing another prompt or collecting on build',
    (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderObservationControls(
              analyticsEnabled: true,
              optedIn: true,
              onChanged: changes.add,
            ),
          ),
        ),
      );
      expect(changes, isEmpty);
      await tester.tap(find.byType(CheckboxListTile));
      expect(changes, [false]);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
