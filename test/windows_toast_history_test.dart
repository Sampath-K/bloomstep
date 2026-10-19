import 'package:budlark/services/windows_toast_history.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('budlark/toast_history');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getHistory') return ['123', '456'];
          if (call.method == 'getSetting') return 0;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('Win32 history and removal use the app-pinned native adapter', () async {
    expect(await WindowsToastHistory.activeTags(), ['123', '456']);
    await WindowsToastHistory.cancel(123);
    expect(calls.map((call) => call.method), ['getHistory', 'cancel']);
    expect(calls.last.arguments, {'id': 123});
  });
  test('native failures are surfaced, never replaced by an empty history', () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'history_unavailable');
        });
    expect(WindowsToastHistory.activeTags(), throwsA(isA<PlatformException>()));
  });
  test('invalid native history is rejected', () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => [123]);
    expect(WindowsToastHistory.activeTags(), throwsA(isA<FormatException>()));
  });
  test('user-disabled notifications are not represented as enabled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 2);
    await expectLater(
      WindowsToastHistory.requireEnabled(),
      throwsA(isA<StateError>()),
    );
  });
  test('registration uses the native identity-only adapter', () async {
    await WindowsToastHistory.registerApp();
    expect(calls.single.method, 'registerApp');
    expect(calls.single.arguments, isNull);
  });
  test('registration errors remain failures rather than a success flag', () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'notification_registration_failed',
            message: 'Repair or reinstall Budlark, then retry.',
            details: -2147024891,
          );
        });
    expect(
      WindowsToastHistory.registerApp(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'notification_registration_failed',
        ),
      ),
    );
  });
  test('invalid native availability is not treated as enabled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 5);
    await expectLater(
      WindowsToastHistory.requireEnabled(),
      throwsA(isA<FormatException>()),
    );
  });
  for (final entry in {
    1: 'disabled for Budlark',
    2: 'disabled for this Windows user',
    3: 'device policy',
    4: 'registration',
  }.entries) {
    test('Windows setting ${entry.key} has an actionable cause', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return entry.key;
          });
      await expectLater(
        WindowsToastHistory.requireEnabled(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'cause',
            contains(entry.value),
          ),
        ),
      );
      await expectLater(
        WindowsToastHistory.show(
          id: 123,
          title: 'Reminder',
          body: 'A tiny step',
          payload: '{}',
          actions: {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls.where((call) => call.method == 'show'), isEmpty);
    });
  }
  test('settings launch failure is surfaced without claiming permission', () async {
    await expectLater(
      WindowsToastHistory.openNotificationSettings(
        launcher: (uri, mode) async {
          expect(uri.toString(), 'ms-settings:notifications');
          expect(mode, LaunchMode.externalApplication);
          return false;
        },
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('opening settings does not claim notifications were enabled', () async {
    await WindowsToastHistory.openNotificationSettings(
      launcher: (uri, mode) async {
        expect(uri.toString(), 'ms-settings:notifications');
        expect(mode, LaunchMode.externalApplication);
        return true;
      },
    );
    expect(calls, isEmpty);
  });
  test(
    'native toast preserves escaped text and actual action payloads',
    () async {
      await WindowsToastHistory.show(
        id: 123,
        title: 'A < B',
        body: 'one & two',
        payload: '{"action":"open"}',
        actions: {'Did it': '{"action":"did"}'},
      );
      expect(calls.first.method, 'getSetting');
      expect(calls.last.method, 'show');
      final data = calls.last.arguments as Map;
      expect(data['id'], 123);
      final xml = data['xml'] as String;
      expect(xml, contains('A &lt; B'));
      expect(xml, contains('one &amp; two'));
      expect(xml, contains('content="Did it"'));
      expect(xml, contains('&quot;did&quot;'));
      expect(xml, isNot(contains('< B')));
    },
  );
}
