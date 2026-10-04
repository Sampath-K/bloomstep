import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../core/garden_store.dart';
import '../core/rules.dart';

class RemoteConfigResult {
  const RemoteConfigResult(this.config, {this.warning, this.fromCache = false});
  final RemoteConfig config;
  final String? warning;
  final bool fromCache;
}

class RemoteConfig {
  const RemoteConfig._(
    this.version,
    this.enabled,
    this.treatmentPercent,
    this.issuedAt,
    this.expiresAt,
  );
  final int version, treatmentPercent;
  final bool enabled;
  final DateTime? issuedAt, expiresAt;
  static const defaults = RemoteConfig._(1, false, 25, null, null);
  static const control = 'A tiny step is enough';
  static const treatment = 'Your next tiny step is here';
  static const apiOrigin = String.fromEnvironment('API_ORIGIN');
  static const guardrails = [
    'reminder_opt_out',
    'fewer_reminders',
    'pushy_feedback',
  ];

  // Deliberately empty until a source-reviewed published cohort and guardrail
  // report exists. Remote flags and self-asserted review fields cannot enable it.
  static const reviewedEvidenceChecksum = '';

  static bool _keys(Map value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  /// Integrity/version identity, not a signature or evidence of approval.
  static String checksum(Map<String, dynamic> document) => sha256
      .convert(
        utf8.encode(jsonEncode(_canonical({...document}..remove('checksum')))),
      )
      .toString();

  static DateTime _utc(Object? raw) {
    if (raw is! String ||
        !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?Z$')
            .hasMatch(raw)) {
      throw const FormatException('Invalid UTC configuration timestamp.');
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 19) != raw.substring(0, 19)) {
      throw const FormatException('Invalid configuration date.');
    }
    return parsed;
  }

  static RemoteConfig parse(Map<String, dynamic> json, {DateTime? now}) {
    final date = (now ?? DateTime.now()).toUtc();
    final experiment = json['experiment'];
    final version = json['version'];
    if (!_keys(json, {
          'schemaVersion',
          'version',
          'issuedAt',
          'expiresAt',
          'checksum',
          'experiment',
        }) ||
        json['schemaVersion'] != 2 ||
        json['schemaVersion'] is! int ||
        version is! int ||
        version < 1 ||
        version > 2147483647 ||
        json['checksum'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(json['checksum']) ||
        json['checksum'] != checksum(json) ||
        experiment is! Map ||
        !_keys(experiment, {
          'id',
          'enabled',
          'treatmentPercent',
          'control',
          'treatment',
          'guardrails',
          'review',
        }) ||
        experiment['id'] != 'gentle-reminder-copy-v1' ||
        experiment['enabled'] is! bool ||
        experiment['treatmentPercent'] is! int ||
        experiment['treatmentPercent'] < 0 ||
        experiment['treatmentPercent'] > 50 ||
        experiment['control'] != control ||
        experiment['treatment'] != treatment ||
        jsonEncode(experiment['guardrails']) != jsonEncode(guardrails)) {
      throw const FormatException(
        'Configuration is outside the reviewed registry.',
      );
    }
    final issued = _utc(json['issuedAt']);
    final expires = _utc(json['expiresAt']);
    if (issued.isAfter(date.add(const Duration(minutes: 5))) ||
        !expires.isAfter(issued) ||
        expires.difference(issued) > const Duration(days: 7) ||
        !date.isBefore(expires)) {
      throw const FormatException(
        'Configuration is expired or has an unsafe lifetime.',
      );
    }
    final review = experiment['review'];
    if (review != null) {
      if (review is! Map ||
          !_keys(review, {'cohortSize', 'reviewedAt', 'evidenceChecksum'}) ||
          review['cohortSize'] is! int ||
          review['cohortSize'] < 50 ||
          review['cohortSize'] > 100000000 ||
          review['evidenceChecksum'] != reviewedEvidenceChecksum ||
          reviewedEvidenceChecksum.isEmpty ||
          _utc(review['reviewedAt']).isAfter(issued)) {
        throw const FormatException(
          'Published cohort/guardrail review is not source-approved.',
        );
      }
    }
    if (experiment['enabled'] == true && review == null) {
      throw const FormatException(
        'An enabled flag cannot authorize an experiment.',
      );
    }
    return RemoteConfig._(
      version,
      experiment['enabled'],
      experiment['treatmentPercent'],
      issued,
      expires,
    );
  }

  bool activeAt(DateTime now) =>
      enabled &&
      reviewedEvidenceChecksum.isNotEmpty &&
      issuedAt != null &&
      !now.toUtc().isBefore(issuedAt!) &&
      expiresAt != null &&
      now.toUtc().isBefore(expiresAt!);

  String variant(String account, {DateTime? now}) =>
      activeAt(now ?? DateTime.now()) &&
          experimentBucket(account) < treatmentPercent
      ? 'gentle'
      : 'control';

  String title(String account, {DateTime? now}) =>
      variant(account, now: now) == 'gentle' ? treatment : control;

  static Uri _endpoint(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443) ||
        !['', '/', '/api', '/api/'].contains(uri.path)) {
      throw const FormatException('Approved API origin is not configured.');
    }
    return uri.replace(path: '/config.json');
  }

  static Map<String, dynamic> _object(String raw) {
    if (utf8.encode(raw).length > 8192) {
      throw const FormatException('Config is too large.');
    }
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Config must be an object.');
    }
    return value;
  }

  static Future<String> _download(http.Client client, Uri endpoint) async {
    final request = http.Request('GET', endpoint)..followRedirects = false;
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw const FormatException('Config download failed.');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 8192) {
        throw const FormatException('Config is too large.');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  static final _fetches = Expando<Future<void>>();

  static Future<RemoteConfigResult> fetch(
    GardenStore store, {
    http.Client? client,
    DateTime Function()? clock,
    String origin = apiOrigin,
  }) {
    final account = store.account;
    final generation = store.syncGeneration;
    final next = (_fetches[store] ?? Future<void>.value()).then((_) {
      store.requireSyncSession(account, generation);
      return _fetch(store, client: client, clock: clock, origin: origin);
    });
    _fetches[store] = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  static Future<RemoteConfigResult> _fetch(
    GardenStore store, {
    http.Client? client,
    DateTime Function()? clock,
    required String origin,
  }) async {
    final account = store.account;
    final generation = store.syncGeneration;
    final clockNow = clock ?? DateTime.now;
    var date = clockNow().toUtc();
    final started = date;
    void requireAccount() => store.requireSyncSession(account, generation);
    Map<String, dynamic>? floor;
    Map<String, dynamic>? cached;
    var damagedFloor = false;
    final rawFloor = await store.setting('remoteConfigFloor');
    try {
      if (rawFloor != null) {
        floor = _object(rawFloor);
        if (!_keys(floor, {'version', 'checksum'}) ||
            floor['version'] is! int ||
            floor['version'] < 1 ||
            floor['version'] > 2147483647 ||
            floor['checksum'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(floor['checksum'])) {
          throw const FormatException();
        }
      }
    } catch (_) {
      damagedFloor = true;
    }
    void noRollback(Map<String, dynamic> document) {
      if (damagedFloor ||
          (floor != null &&
              (document['version'] < floor['version'] ||
                  (document['version'] == floor['version'] &&
                      document['checksum'] != floor['checksum'])))) {
        throw const FormatException('Config rollback or version drift.');
      }
    }

    try {
      final raw = await store.setting('remoteConfigState');
      if (raw != null) cached = _object(raw);
    } catch (_) {
      cached = null;
    }
    try {
      requireAccount();
      final endpoint = _endpoint(origin);
      if (damagedFloor) throw const FormatException('Invalid version floor.');
      if (cached != null &&
          cached['fetchedAt'] is String &&
          _utc(cached['fetchedAt']).isAfter(date)) {
        throw const FormatException('Clock moved backwards.');
      }
      final transport = client ?? http.Client();
      late String body;
      try {
        body = await _download(
          transport,
          endpoint,
        ).timeout(const Duration(seconds: 10));
      } finally {
        if (client == null) transport.close();
      }
      requireAccount();
      date = clockNow().toUtc();
      if (date.isBefore(started)) {
        throw const FormatException('Clock moved backwards.');
      }
      final document = _object(body);
      final config = parse(document, now: date);
      noRollback(document);
      requireAccount();
      await store.setSetting(
        'remoteConfigFloor',
        jsonEncode({
          'version': config.version,
          'checksum': document['checksum'],
        }),
      );
      floor = {'version': config.version, 'checksum': document['checksum']};
      requireAccount();
      await store.setSetting(
        'remoteConfigState',
        jsonEncode({
          'document': document,
          'fetchedAt': date.toIso8601String(),
          'origin': endpoint.toString(),
        }),
      );
      requireAccount();
      return RemoteConfigResult(config);
    } catch (_) {
      requireAccount();
      date = clockNow().toUtc();
      try {
        if (cached == null ||
            !_keys(cached, {'document', 'fetchedAt', 'origin'}) ||
            cached['document'] is! Map<String, dynamic> ||
            floor == null ||
            cached['origin'] != _endpoint(origin).toString()) {
          throw const FormatException('No validated cache.');
        }
        final fetched = _utc(cached['fetchedAt']);
        if (fetched.isAfter(date) ||
            date.difference(fetched) >= const Duration(days: 7)) {
          throw const FormatException(
            'Cache expired or clock moved backwards.',
          );
        }
        final document = cached['document'] as Map<String, dynamic>;
        if (document['version'] != floor['version'] ||
            document['checksum'] != floor['checksum']) {
          throw const FormatException(
            'Cache does not match the accepted version.',
          );
        }
        noRollback(document);
        final config = parse(document, now: date);
        return RemoteConfigResult(
          config,
          fromCache: true,
          warning:
              'Remote configuration download invalid or unavailable; using validated offline cache until ${config.expiresAt!.toIso8601String()}.',
        );
      } catch (_) {
        requireAccount();
        return const RemoteConfigResult(
          defaults,
          warning: 'Remote configuration download/cache invalid, expired or unavailable; using reviewed local control copy. No experiment is active.',
        );
      }
    }
  }
}
