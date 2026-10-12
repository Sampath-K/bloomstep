import 'package:bloomstep/services/analytics_sandbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:bloomstep/features/garden/analytics_sandbox_controls.dart';

class FakeBackend implements SandboxBackend {
  int starts = 0, events = 0, crashes = 0, stops = 0;
  SandboxConfig? config;
  @override
  Future<void> start(
    SandboxConfig value,
    Future<bool> Function() allowed,
  ) async {
    expect(await allowed(), true);
    config = value;
    starts++;
  }

  @override
  Future<void> event(String name, Map<String, String> properties) async {
    expect(name, startsWith('sandbox_'));
    events++;
  }

  @override
  Future<void> crash() async {
    crashes++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  testWidgets(
    'staging settings are unchecked and closing revokes the SDK scope',
    (tester) async {
      final backend = FakeBackend();
      final sandbox = AnalyticsSandbox(
        config: const SandboxConfig(enabled: true, aptabaseKey: 'A-EU-123'),
        productConsent: () async => true,
        backend: backend,
        onError: fail,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AnalyticsSandboxControls(sandbox: sandbox)),
        ),
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(backend.starts, 0);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(backend.starts, 1);
      expect(await sandbox.allowed(), true);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(await sandbox.allowed(), false);
      expect(backend.stops, greaterThan(0));
      await sandbox.close();
    },
  );
  test('defaults initialize no vendors even with both consents', () async {
    final backend = FakeBackend();
    final sandbox = AnalyticsSandbox(
      config: const SandboxConfig(enabled: true),
      productConsent: () async => true,
      backend: backend,
      onError: fail,
    );
    await sandbox.consentChanged(true);
    expect(backend.starts, 0);
    await sandbox.close();
  });
  test(
    'fake keys initialize only with both consents and stop on revoke',
    () async {
      var product = false;
      final backend = FakeBackend();
      final sandbox = AnalyticsSandbox(
        config: const SandboxConfig(
          enabled: true,
          aptabaseKey: 'A-EU-1234567890',
          sentryDsn: 'https://abc123@o1.ingest.de.sentry.io/123',
        ),
        productConsent: () async => product,
        backend: backend,
        onError: fail,
      );
      await sandbox.referral('BS-SANDBOX');
      await sandbox.recordCrash();
      await sandbox.consentChanged(true);
      expect(backend.starts, 0);
      product = true;
      await sandbox.consentChanged(true);
      expect(backend.starts, 1);
      expect(
        backend.config!.aptabaseEndpoint.toString(),
        'https://eu.aptabase.com/api/v0/events',
      );
      expect(
        backend.config!.sentryEndpoint.toString(),
        'https://o1.ingest.de.sentry.io/api/123/envelope/',
      );
      await sandbox.referral('BS-SANDBOX');
      await sandbox.recordCrash();
      expect(backend.events, 2);
      expect(backend.crashes, 1);
      product = false;
      await sandbox.referral('BS-SANDBOX');
      await sandbox.recordCrash();
      expect(backend.events, 2);
      expect(backend.crashes, 1);
      await sandbox.consentChanged(false);
      expect(await sandbox.allowed(), false);
      await sandbox.close();
    },
  );
  test('disabled builds ignore keys and endpoints validate regions', () async {
    final backend = FakeBackend();
    final sandbox = AnalyticsSandbox(
      config: const SandboxConfig(enabled: false, aptabaseKey: 'A-US-123'),
      productConsent: () async => true,
      backend: backend,
      onError: fail,
    );
    await sandbox.consentChanged(true);
    expect(backend.starts, 0);
    expect(
      const SandboxConfig(aptabaseKey: 'A-US-123').aptabaseEndpoint.toString(),
      'https://us.aptabase.com/api/v0/events',
    );
    expect(
      () => const SandboxConfig(aptabaseKey: 'A-XX-123').aptabaseEndpoint,
      throwsFormatException,
    );
    expect(
      () =>
          const SandboxConfig(sentryDsn: 'http://secret@evil.test/1')
              .sentryEndpoint,
      throwsFormatException,
    );
    await sandbox.close();
  });
  test(
    'Aptabase queue drops pending and future data when consent revoked',
    () async {
      var allowed = true;
      final queue = ConsentMemoryQueue(() async => allowed);
      await queue.addEvent('id', 'fixed event');
      expect(await queue.getItems(25), hasLength(1));
      allowed = false;
      expect(await queue.getItems(25), isEmpty);
      await queue.addEvent('blocked', 'fixed event');
      allowed = true;
      expect(await queue.getItems(25), isEmpty);
    },
  );
  test(
    'Sentry initializes scrubbed, no native/background collection',
    () async {
      var allowed = true;
      final options = SentryFlutterOptions();
      configureSandboxSentry(
        options,
        'https://abc@o1.ingest.sentry.io/123',
        () async => allowed,
      );
      expect(options.sendDefaultPii, false);
      expect(options.autoInitializeNativeSdk, false);
      expect(options.integrations, isEmpty);
      final event = SentryEvent(
        message: SentryMessage('private text'),
        user: SentryUser(email: 'private@example.test'),
        tags: {'private': 'account'},
        breadcrumbs: [Breadcrumb(message: 'private URL')],
      );
      final scrubbed = await options.beforeSend!(event, Hint());
      expect(scrubbed!.message!.formatted, 'sandbox_dart_error');
      expect(scrubbed.user, isNull);
      expect(scrubbed.tags, isNull);
      expect(scrubbed.breadcrumbs, isNull);
      allowed = false;
      expect(await options.beforeSend!(event, Hint()), isNull);
    },
  );
  test(
    'real Sentry transport uses hosted envelope endpoint after consent only',
    () async {
      var consent = false;
      final requests = <http.Request>[];
      const config = SandboxConfig(
        enabled: true,
        sentryDsn: 'https://abc@o1.ingest.sentry.io/123',
      );
      final transport = SandboxSentryTransport(
        config,
        () async => consent,
        fail,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      final envelope = SentryEnvelope.fromEvent(
        SentryEvent(
          message: SentryMessage('secret'),
          user: SentryUser(email: 'secret@example.test'),
        ),
        SdkVersion(name: 'test', version: '1'),
      );
      await transport.send(envelope);
      expect(requests, isEmpty);
      consent = true;
      await transport.send(envelope);
      expect(
        requests.single.url.toString(),
        'https://o1.ingest.sentry.io/api/123/envelope/',
      );
      expect(requests.single.body, contains('sandbox_dart_error'));
      expect(requests.single.body, isNot(contains('secret')));
      consent = false;
      await transport.send(envelope);
      expect(requests, hasLength(1));
      transport.close();
    },
  );
}
