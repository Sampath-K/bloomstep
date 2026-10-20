import 'package:budlark/core/garden_store.dart';
import 'package:budlark/features/garden/garden_screen.dart';
import 'package:budlark/services/desktop_reminders.dart';
import 'package:budlark/services/remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/garden_navigation.dart';

class ConfigGateway implements ReminderGateway {
  @override
  Future<void> initialize(Future<void> Function(String) action) async {}
  @override
  Future<void> show(ReminderRequest request) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> showAndFocus() async {}
  @override
  Future<void> shutdown() async {}
}

Future<void> ready(WidgetTester tester, Finder finder) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await openGardenMore(tester);
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 350));
      return;
    }
  }
  fail('Readiness timeout: $finder');
}

Future<void> openConfigStatus(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings and privacy'));
  await ready(tester, find.text('App & support'));
  await tester.ensureVisible(find.text('App & support'));
  await tester.tap(find.text('App & support'));
  await ready(tester, find.text('Your garden is using its usual settings.'));
}

void main() {
  testWidgets('accepted config expiration visibly returns to control', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => GardenStore.open(':memory:', 'config-expiry-ui'),
    ))!;
    addTearDown(() => tester.runAsync(store.close));
    final now = DateTime.now().toUtc();
    final document = <String, dynamic>{
      'schemaVersion': 2,
      'version': 2,
      'issuedAt': now.toIso8601String(),
      'expiresAt': now.add(const Duration(seconds: 2)).toIso8601String(),
      'experiment': {
        'id': 'gentle-reminder-copy-v1',
        'enabled': false,
        'treatmentPercent': 25,
        'control': RemoteConfig.control,
        'treatment': RemoteConfig.treatment,
        'guardrails': RemoteConfig.guardrails,
        'review': null,
      },
    };
    document['checksum'] = RemoteConfig.checksum(document);
    final config = RemoteConfig.parse(document, now: now);
    await tester.pumpWidget(
      MaterialApp(
        home: GardenScreen(
          store: store,
          reminderGateway: ConfigGateway(),
          configLoader: (_) async => RemoteConfigResult(config),
        ),
      ),
    );
    await ready(tester, find.text('Plant a habit'));
    await tester.pump(const Duration(seconds: 3));
    await openConfigStatus(tester);
    expect(
      find.text('Your garden is using its usual settings.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  });

  testWidgets(
    'config warning is explicit; personalization stays device-only and off by default',
    (tester) async {
      final store = (await tester.runAsync(
        () => GardenStore.open(':memory:', 'config-ui'),
      ))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.binding.setSurfaceSize(const Size(1100, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            reminderGateway: ConfigGateway(),
            configLoader: (_) async => const RemoteConfigResult(
              RemoteConfig.defaults,
              warning: 'private configuration parser detail',
            ),
          ),
        ),
      );
      await ready(tester, find.text('Plant a habit'));
      await openConfigStatus(tester);
      expect(
        find.text('Your garden is using its usual settings.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings and privacy'));
      await ready(tester, find.text('Reminders'));
      await tester.tap(find.text('Reminders'));
      await tester.pump(const Duration(milliseconds: 350));
      final toggle = find.widgetWithText(
        SwitchListTile,
        'Personalized reminder timing',
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(seconds: 10) &&
          !tester.widget<SwitchListTile>(toggle).value) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(
        await tester.runAsync(() => store.setting('personalizedTiming')),
        'true',
      );
      expect(await tester.runAsync(() => store.setting('reminders')), 'true');
      expect(await tester.runAsync(() => store.setting('analytics')), isNull);
      final payload = (await tester.runAsync(store.syncPayload))!;
      expect(
        (payload['settings'] as List).where(
          (r) => r['key'] == 'personalizedTiming',
        ),
        isEmpty,
      );
    },
  );
}
