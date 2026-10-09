import 'dart:async';

import 'dart:convert';

import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:aptabase_flutter/storage_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

const analyticsSandboxEnabled =
    !kReleaseMode && bool.fromEnvironment('BLOOMSTEP_ANALYTICS_SANDBOX');

class SandboxConfig {
  const SandboxConfig({
    this.enabled = analyticsSandboxEnabled,
    this.aptabaseKey = const String.fromEnvironment('APTABASE_APP_KEY'),
    this.sentryDsn = const String.fromEnvironment('SENTRY_DSN'),
  });
  final bool enabled;
  final String aptabaseKey, sentryDsn;
  Uri? get aptabaseEndpoint {
    if (aptabaseKey.isEmpty) return null;
    final match = RegExp(r'^A-(EU|US)-[0-9]+$').firstMatch(aptabaseKey);
    if (match == null) throw const FormatException('Invalid Aptabase app key.');
    return Uri.parse(
      'https://${match[1]!.toLowerCase()}.aptabase.com/api/v0/events',
    );
  }

  Uri? get sentryEndpoint {
    if (sentryDsn.isEmpty) return null;
    final uri = Uri.parse(sentryDsn);
    if (uri.scheme != 'https' ||
        !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(uri.userInfo) ||
        !RegExp(r'^[a-zA-Z0-9.-]+\.ingest(?:\.[a-z]+)?\.sentry\.io$')
            .hasMatch(uri.host) ||
        !RegExp(r'^/[0-9]+$').hasMatch(uri.path) ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Invalid hosted Sentry DSN.');
    }
    return uri.replace(userInfo: '', path: '/api${uri.path}/envelope/');
  }
}

abstract interface class SandboxBackend {
  Future<void> start(SandboxConfig config, Future<bool> Function() allowed);
  Future<void> event(String name, Map<String, String> properties);
  Future<void> crash();
  Future<void> stop();
}

// Aptabase has no public shutdown API. Never persist its queue, and check current
// account consent again when the SDK asks for a batch, including retry batches.
class ConsentMemoryQueue extends StorageManager {
  ConsentMemoryQueue(this.allowed);
  final Future<bool> Function() allowed;
  final _events = <String, String>{};
  @override
  Future<void> addEvent(String key, String event) async {
    if (await allowed()) _events[key] = event;
  }

  @override
  Future<Iterable<MapEntry<String, String>>> getItems(int length) async {
    if (!await allowed()) _events.clear();
    return _events.entries.take(length).toList();
  }

  @override
  Future<void> deleteEvents(Set<String> keys) async {
    keys.forEach(_events.remove);
  }

  void clear() => _events.clear();
}

SentryEvent scrubSandboxEvent(SentryEvent event) => SentryEvent(
  eventId: event.eventId,
  timestamp: event.timestamp,
  level: SentryLevel.error,
  message: SentryMessage('sandbox_dart_error'),
  environment: 'analytics-sandbox',
);

void configureSandboxSentry(
  SentryFlutterOptions options,
  String dsn,
  Future<bool> Function() allowed,
) {
  options
    ..dsn = dsn
    ..environment = 'analytics-sandbox'
    ..sendDefaultPii = false
    ..autoInitializeNativeSdk = false
    ..enableNativeCrashHandling = false
    ..enableAutoSessionTracking = false
    ..enableAutoNativeBreadcrumbs = false
    ..enableAutoPerformanceTracing = false
    ..attachScreenshot = false
    ..tracesSampleRate = 0
    ..sendClientReports = false
    ..enableLogs = false
    ..enableMetrics = false
    ..maxBreadcrumbs = 0;
  for (final integration in options.integrations.toList()) {
    options.removeIntegration(integration);
  }
  options.beforeSend = (event, hint) async =>
      await allowed() ? scrubSandboxEvent(event) : null;
}

class SandboxSentryTransport implements Transport {
  SandboxSentryTransport(
    this.config,
    this.allowed,
    this.onError, {
    http.Client? client,
  }) : client = client ?? http.Client();
  final SandboxConfig config;
  final Future<bool> Function() allowed;
  final void Function(String) onError;
  final http.Client client;
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    if (!await allowed()) return null;
    // Send an allowlisted envelope, not SDK-enriched device/context/attachment data.
    final id = envelope.header.eventId ?? SentryId.newId();
    final event = scrubSandboxEvent(SentryEvent(eventId: id));
    final body = [
      jsonEncode({'event_id': id.toString(), 'dsn': config.sentryDsn}),
      jsonEncode({'type': 'event'}),
      jsonEncode(event.toJson()),
    ].join('\n');
    if (!await allowed()) return null;
    try {
      final response = await client
          .post(
            config.sentryEndpoint!,
            headers: {'Content-Type': 'application/x-sentry-envelope'},
            body: body,
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Sentry sandbox HTTP ${response.statusCode}.');
      }
      return id;
    } catch (error) {
      onError('Staging Sentry request failed. No delivery claim.');
      rethrow;
    }
  }

  void close() => client.close();
}

class VendorSandboxBackend implements SandboxBackend {
  VendorSandboxBackend(this.onError);
  final void Function(String) onError;
  static ConsentMemoryQueue? _queue;
  static bool _aptabaseInitialized = false;
  static Future<bool> Function()? _queueAllowed;
  bool _aptabaseActive = false;
  bool _sentryActive = false;
  SandboxSentryTransport? _transport;
  Future<bool> Function()? _allowed;
  Future<void> _pendingEvents = Future<void>.value();
  @override
  Future<void> start(
    SandboxConfig config,
    Future<bool> Function() allowed,
  ) async {
    _allowed = allowed;
    _queueAllowed = allowed;
    if (config.aptabaseEndpoint != null) {
      _queue ??= ConsentMemoryQueue(
        () async => await _queueAllowed?.call() ?? false,
      );
      if (!_aptabaseInitialized) {
        await Aptabase.init(config.aptabaseKey, const InitOptions(), _queue);
        _aptabaseInitialized = true;
      }
      _aptabaseActive = true;
    }
    if (config.sentryEndpoint != null) {
      _transport = SandboxSentryTransport(config, allowed, onError);
      _sentryActive = true;
      await SentryFlutter.init((options) {
        configureSandboxSentry(options, config.sentryDsn, allowed);
        options.transport = _transport!;
      });
    }
  }

  @override
  Future<void> event(String name, Map<String, String> properties) {
    final next = _pendingEvents.then((_) async {
      if (_aptabaseActive && (await _allowed?.call() ?? false)) {
        await Aptabase.instance.trackEvent(name, properties);
      }
    });
    _pendingEvents = next.catchError((Object error) {
      onError('Staging Aptabase event failed. No delivery claim.');
    });
    return _pendingEvents;
  }

  @override
  Future<void> crash() async {
    if (_sentryActive && (await _allowed?.call() ?? false)) {
      await Sentry.captureEvent(
        SentryEvent(message: SentryMessage('sandbox_dart_error')),
      );
    }
  }

  @override
  Future<void> stop() async {
    _aptabaseActive = false;
    _allowed = null;
    _queueAllowed = null;
    await _pendingEvents;
    _queue?.clear();
    if (_sentryActive) await Sentry.close();
    _transport?.close();
    _transport = null;
    _sentryActive = false;
  }
}

class AnalyticsSandbox {
  AnalyticsSandbox({
    required this.productConsent,
    required this.onError,
    this.config = const SandboxConfig(),
    SandboxBackend? backend,
  }) : backend = backend ?? VendorSandboxBackend(onError);
  final Future<bool> Function() productConsent;
  final void Function(String) onError;
  final SandboxConfig config;
  final SandboxBackend backend;
  bool _consent = false, _started = false, _closed = false;
  Future<void> _pending = Future<void>.value();
  FlutterExceptionHandler? _previous, _handler;
  bool Function(Object, StackTrace)? _previousUnhandled, _unhandled;
  Future<bool> allowed() async =>
      config.enabled && !_closed && _consent && await productConsent();

  Future<void> consentChanged(bool value) {
    _consent = value;
    final next = _pending.then((_) async {
      if (!await allowed()) {
        await backend.stop();
        _started = false;
        return;
      }
      if (_started) return;
      if (config.aptabaseEndpoint == null && config.sentryEndpoint == null) {
        return;
      }
      await backend.start(config, allowed);
      if (!await allowed()) {
        await backend.stop();
        return;
      }
      _started = true;
      await backend.event('sandbox_session_started', {});
    });
    _pending = next.catchError((Object error) async {
      _consent = false;
      _started = false;
      onError('Staging analytics failed; no further events will be queued.');
      await backend.stop();
    });
    return _pending;
  }

  Future<void> referral(String code) async {
    if (code != 'BS-SANDBOX') {
      throw const FormatException('Use the shared staging code BS-SANDBOX.');
    }
    if (_started && await allowed()) {
      await backend.event('sandbox_referral_entered', {
        'campaign': 'prelaunch',
      });
    }
  }

  Future<void> recordCrash() async {
    if (_started && await allowed()) await backend.crash();
  }

  void attach() {
    if (!config.enabled) return;
    _previous = FlutterError.onError;
    _previousUnhandled = PlatformDispatcher.instance.onError;
    void report() {
      unawaited(
        recordCrash().catchError((Object error) {
          onError('Staging crash observation failed. No error text was sent.');
        }),
      );
    }

    _handler = (details) {
      report();
      if (_previous != null) {
        _previous!(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    _unhandled = (error, stack) {
      report();
      return _previousUnhandled?.call(error, stack) ?? false;
    };
    FlutterError.onError = _handler;
    PlatformDispatcher.instance.onError = _unhandled;
  }

  Future<void> close() async {
    _closed = true;
    _consent = false;
    if (_handler != null && FlutterError.onError == _handler) {
      FlutterError.onError = _previous;
    }
    if (_unhandled != null &&
        PlatformDispatcher.instance.onError == _unhandled) {
      PlatformDispatcher.instance.onError = _previousUnhandled;
    }
    await _pending;
    await backend.stop();
  }
}
