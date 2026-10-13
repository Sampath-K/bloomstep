import 'package:bloomstep/app/session_boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile rebuild immediately rejects an invalid session', (
    tester,
  ) async {
    var valid = true;
    var expirations = 0;
    Widget app() => MaterialApp(
      home: SessionBoundary(
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        isValid: () => valid,
        onExpired: (_) async => expirations++,
        child: const Text('Private test garden'),
      ),
    );
    await tester.pumpWidget(app());
    valid = false;
    await tester.pumpWidget(app());
    expect(find.text('Private test garden'), findsNothing);
    expect(expirations, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed session clock checkpoint hides data and reports the failure',
    (tester) async {
      var expirations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionBoundary(
            expiresAt: DateTime.now().add(const Duration(days: 30)),
            isValid: () => true,
            onCheckpoint: () async =>
                throw StateError('test clock storage failure'),
            onExpired: (_) async {
              expirations++;
            },
            child: const Text('Private test garden'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Private test garden'), findsNothing);
      expect(find.textContaining('test clock storage failure'), findsOneWidget);
      expect(expirations, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('expiry hides the garden while credential cleanup is pending', (
    tester,
  ) async {
    var valid = true;
    var expirations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SessionBoundary(
          expiresAt: DateTime.now().add(const Duration(seconds: 2)),
          isValid: () => valid,
          onExpired: (_) async {
            expirations++;
          },
          child: const Text('Private test garden'),
        ),
      ),
    );
    valid = false;
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Private test garden'), findsNothing);
    expect(find.textContaining('session has ended'), findsOneWidget);
    expect(expirations, 1);
    await tester.pump(const Duration(minutes: 2));
    expect(expirations, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'resume rejects a changed clock without waiting for the deadline',
    (tester) async {
      var valid = true;
      var expirations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionBoundary(
            expiresAt: DateTime.now().add(const Duration(days: 30)),
            isValid: () => valid,
            onExpired: (_) async {
              expirations++;
            },
            child: const Text('Private test garden'),
          ),
        ),
      );
      valid = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Private test garden'), findsNothing);
      expect(expirations, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
