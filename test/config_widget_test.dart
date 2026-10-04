import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/features/garden/garden_screen.dart';
import 'package:bloomstep/services/desktop_reminders.dart';
import 'package:bloomstep/services/remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Readiness timeout: $finder');
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
    expect(find.textContaining('Remote configuration expired'), findsOneWidget);
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
      const warning =
          'Remote configuration download/cache invalid; using reviewed local control copy. No experiment is active.';
      await tester.pumpWidget(
        MaterialApp(
          home: GardenScreen(
            store: store,
            reminderGateway: ConfigGateway(),
            configLoader: (_) async => const RemoteConfigResult(
              RemoteConfig.defaults,
              warning: warning,
            ),
          ),
        ),
      );
      await ready(tester, find.text(warning));
      expect(find.text(warning), findsOneWidget);
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await ready(tester, find.text('Personalized reminder timing'));
      final toggle = find.widgetWithText(
        SwitchListTile,
        'Personalized reminder timing',
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.ensureVisible(toggle);
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
      expect(await tester.runAsync(() => store.setting('reminders')), isNull);
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
