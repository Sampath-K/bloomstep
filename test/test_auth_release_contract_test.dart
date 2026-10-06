import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:bloomstep/services/sync_service.dart';

import '../integration_test/support/test_only_app.dart';

const _testBuild = bool.fromEnvironment('BLOOMSTEP_TEST_BUILD');

void main() {
  if (_testBuild) {
    test(
      'production auth boundary tests run only without the test-build define',
      () {},
      skip: 'Run this file in the separate production-mode CI step.',
    );
    return;
  }

  testWidgets('normal builds cannot activate synthetic sign-in', (
    tester,
  ) async {
    final key = List.filled(64, 'a').join();
    expect(TestOnlyAuthGate.enabled, isFalse);
    expect(
      TestOnlyAuthGate.authenticate(
        expectedSecret: key,
        username: 'synthetic-a',
        suppliedSecret: key,
      ),
      isNull,
    );

    final root = await Directory.systemTemp.createTemp('bloomstep-it-');
    addTearDown(() => root.delete(recursive: true));
    await tester.pumpWidget(
      TestOnlyBloomstepApp(runRoot: root, expectedSecret: key),
    );
    expect(
      find.text('Test build is locked. No garden was opened.'),
      findsOneWidget,
    );
    expect(find.byKey(TestOnlyAuthGate.usernameFieldKey), findsNothing);
    expect(await root.list().toList(), isEmpty);
  });

  test('normal builds reject injected clocks and test API origins', () async {
    final root = await Directory.systemTemp.createTemp('bloomstep-it-');
    addTearDown(() => root.delete(recursive: true));
    await expectLater(
      GardenStore.open(
        p.join(root.path, 'clock.sqlite'),
        'synthetic-owner',
        clock: DateTime.now,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await root.list().toList(), isEmpty);

    final store = await GardenStore.open(
      p.join(root.path, 'store.sqlite'),
      'synthetic-owner',
    );
    try {
      expect(
        () => SyncService(
          IdentityService(),
          store,
          testApiOrigin: Uri.parse('http://127.0.0.1:12345'),
        ),
        throwsStateError,
      );
    } finally {
      await store.close();
    }
  });
}
