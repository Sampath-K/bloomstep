import 'dart:io';

import 'package:bloomstep/app/update_status.dart';
import 'package:bloomstep/services/automatic_updates.dart';
import 'package:bloomstep/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class NoUpdate extends UpdateService {
  @override
  Future<UpdateInfo?> check({
    String currentVersion = UpdateService.bundledVersion,
  }) async => null;
}

void main() {
  testWidgets(
    'settings are usable before sign-in and on a pushed garden route',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bloomstep-ui-update-'),
      ))!;
      final updates = AutomaticUpdates(
        preferences: File('${directory.path}\\preferences.json'),
        discovery: NoUpdate(),
      );
      final key = GlobalKey<NavigatorState>();
      try {
        await tester.runAsync(updates.start);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: key,
            builder: (_, child) => UpdateStatus(
              navigatorKey: key,
              controller: updates,
              child: child!,
            ),
            home: const Scaffold(body: Text('Sign in')),
          ),
        );
        await tester.runAsync(() => updates.start());
        await tester.pump();
        await tester.tap(find.text('Update settings'));
        await tester.pumpAndSettle();
        expect(find.text('Automatic updates'), findsOneWidget);
        expect(find.textContaining('Offline, disabled'), findsOneWidget);
        await tester.runAsync(() => updates.setEnabled(false));
        await tester.pump();
        expect(find.textContaining('Automatic checks disabled.'), findsWidgets);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Garden')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Update settings'), findsOneWidget);
        await tester.tap(find.text('Update settings'));
        await tester.pumpAndSettle();
        expect(find.text('Automatic updates'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );
}
