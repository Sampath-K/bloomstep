import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/services/remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> document(DateTime now, {int version = 2}) {
  final value = <String, dynamic>{
    'schemaVersion': 2,
    'version': version,
    'issuedAt': now.toUtc().toIso8601String(),
    'expiresAt': now.add(const Duration(days: 7)).toUtc().toIso8601String(),
    'experiment': {
      'id': 'gentle-reminder-copy-v1',
      'enabled': false,
      'treatmentPercent': 25,
      'control': RemoteConfig.control,
      'treatment': RemoteConfig.treatment,
      'guardrails': ['reminder_opt_out', 'fewer_reminders', 'pushy_feedback'],
      'review': null,
    },
  };
  return seal(value);
}

Map<String, dynamic> seal(Map<String, dynamic> value) {
  value.remove('checksum');
  value['checksum'] = RemoteConfig.checksum(value);
  return value;
}

void main() {
  final now = DateTime.utc(2026, 10, 4, 12);
  test('strict registry rejects unknown fields and unreviewed experiment', () {
    expect(RemoteConfig.defaults.enabled, isFalse);
    expect(RemoteConfig.parse(document(now), now: now).enabled, isFalse);
    for (final invalid in [
      seal(document(now)..['extra'] = 'ignored'),
      seal(document(now)..['schemaVersion'] = 1),
      seal(document(now)..['version'] = 0),
      seal(
        document(now)
          ..['expiresAt'] = now.add(const Duration(days: 8)).toIso8601String(),
      ),
      seal(
        document(
          now,
        )..['issuedAt'] = now.add(const Duration(minutes: 6)).toIso8601String(),
      ),
      seal(document(now)..['expiresAt'] = now.toIso8601String()),
      document(now)..['checksum'] = '0' * 64,
      seal(document(now)..['experiment']['enabled'] = true),
      seal(document(now)..['experiment']['treatmentPercent'] = 51),
      seal(document(now)..['experiment']['extra'] = true),
      seal(document(now)..['experiment']['guardrails'] = ['reminder_opt_out']),
      seal(
        document(now)
          ..['experiment']['review'] = {
            'cohortSize': 50,
            'evidenceUrl': 'https://example.com/review',
          },
      ),
    ]) {
      expect(
        () => RemoteConfig.parse(invalid, now: now),
        throwsFormatException,
      );
    }
  });

  late GardenStore store;
  setUp(() async => store = await GardenStore.open(':memory:', 'config-a'));
  tearDown(() => store.close());

  test(
    'compiled origin path, request bound and validated offline cache',
    () async {
      final first = await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example/api',
        clock: () => now,
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://approved.example/config.json',
          );
          expect(request.headers, isNot(contains('Authorization')));
          return http.Response(jsonEncode(document(now)), 200);
        }),
      );
      expect(first.warning, isNull);
      expect(first.fromCache, isFalse);
      final offline = await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example/api',
        clock: () => now,
        client: MockClient((_) async => throw StateError('private error')),
      );
      expect(offline.fromCache, isTrue);
      expect(offline.config.version, 2);
      expect(offline.warning, contains('validated offline cache'));
      expect(offline.warning, isNot(contains('private error')));
    },
  );

  test(
    'rollback and same-version checksum drift never replace accepted cache',
    () async {
      Future<RemoteConfigResult> fetch(Map<String, dynamic> json) =>
          RemoteConfig.fetch(
            store,
            origin: 'https://approved.example',
            clock: () => now,
            client: MockClient(
              (_) async => http.Response(jsonEncode(json), 200),
            ),
          );
      await fetch(document(now, version: 4));
      for (final bad in [
        document(now, version: 3),
        seal(
          document(now, version: 4)..['experiment']['treatmentPercent'] = 20,
        ),
      ]) {
        final result = await fetch(bad);
        expect(result.config.version, 4);
        expect(result.fromCache, isTrue);
        expect(result.warning, isNotNull);
      }
      expect((await fetch(document(now, version: 5))).config.version, 5);
    },
  );

  test(
    'expired, tampered and legacy cache explicitly fall back to control',
    () async {
      final client = MockClient((_) async => http.Response('invalid', 200));
      await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => now,
        client: MockClient(
          (_) async => http.Response(jsonEncode(document(now)), 200),
        ),
      );
      final expired = await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => now.add(const Duration(days: 7)),
        client: client,
      );
      expect(expired.config, RemoteConfig.defaults);
      expect(expired.warning, contains('reviewed local control'));
      final state =
          jsonDecode((await store.setting('remoteConfigState'))!) as Map;
      state['document']['experiment']['control'] = 'tampered';
      await store.setSetting('remoteConfigState', jsonEncode(state));
      final tampered = await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => now,
        client: client,
      );
      expect(tampered.config, RemoteConfig.defaults);
      expect(tampered.warning, isNotNull);
      await store.switchAccount('legacy');
      await store.setSetting('remoteConfig', jsonEncode({'version': 1}));
      final legacy = await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => now,
        client: client,
      );
      expect(legacy.config, RemoteConfig.defaults);
      expect(legacy.warning, isNotNull);
    },
  );

  test(
    'concurrent fetches serialize monotonic floor and cache origin is isolated',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final high = RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => now,
        client: MockClient((_) async {
          entered.complete();
          await release.future;
          return http.Response(jsonEncode(document(now, version: 5)), 200);
        }),
      );
      await entered.future;
      final low = RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => now,
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode(document(now, version: 4)), 200),
        ),
      );
      release.complete();
      expect((await high).config.version, 5);
      expect((await low).config.version, 5);
      final otherOrigin = await RemoteConfig.fetch(
        store,
        origin: 'https://different.example',
        clock: () => now,
        client: MockClient((_) async => http.Response('', 503)),
      );
      expect(otherOrigin.config, RemoteConfig.defaults);
      expect(otherOrigin.warning, isNotNull);
    },
  );

  test(
    'bad responses, corrupted floor and future cache fail visibly closed',
    () async {
      Future<RemoteConfigResult> fetch(http.Response response) =>
          RemoteConfig.fetch(
            store,
            origin: 'https://approved.example',
            clock: () => now,
            client: MockClient((_) async => response),
          );
      for (final response in [
        http.Response('', 503),
        http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example/config.json'},
        ),
        http.Response('[]', 200),
        http.Response('{"schemaVersion":2}', 200),
      ]) {
        expect((await fetch(response)).warning, isNotNull);
      }
      await fetch(http.Response(jsonEncode(document(now)), 200));
      final state =
          jsonDecode((await store.setting('remoteConfigState'))!) as Map;
      state['fetchedAt'] = now
          .add(const Duration(minutes: 1))
          .toIso8601String();
      await store.setSetting('remoteConfigState', jsonEncode(state));
      expect(
        (await fetch(http.Response('', 503))).config,
        RemoteConfig.defaults,
      );
      await store.setSetting('remoteConfigFloor', 'broken');
      expect(
        (await fetch(
          http.Response(jsonEncode(document(now, version: 99)), 200),
        )).config,
        RemoteConfig.defaults,
      );
    },
  );

  test(
    'valid higher download repairs corrupt cache without losing floor',
    () async {
      Future<RemoteConfigResult> fetch(int version) => RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => now,
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode(document(now, version: version)), 200),
        ),
      );
      await fetch(3);
      await store.setSetting('remoteConfigState', '{invalid');
      expect((await fetch(4)).config.version, 4);
      expect((await fetch(2)).config.version, 4);
    },
  );

  test(
    'persisted cache reopens, remains local and is erased by account deletion',
    () async {
      final path = 'config-reopen-${DateTime.now().microsecondsSinceEpoch}.db';
      var disk = await GardenStore.open(path, 'durable-config');
      try {
        await RemoteConfig.fetch(
          disk,
          origin: 'https://approved.example',
          clock: () => now,
          client: MockClient(
            (_) async => http.Response(jsonEncode(document(now)), 200),
          ),
        );
        expect(
          ((await disk.syncPayload())['settings'] as List).where(
            (r) => r['key'].toString().startsWith('remoteConfig'),
          ),
          isEmpty,
        );
        await disk.close();
        disk = await GardenStore.open(path, 'durable-config');
        final cached = await RemoteConfig.fetch(
          disk,
          origin: 'https://approved.example',
          clock: () => now,
          client: MockClient((_) async => http.Response('', 503)),
        );
        expect(cached.fromCache, isTrue);
        expect(cached.config.version, 2);
        await disk.deleteLocalAccount();
        expect(await disk.setting('remoteConfigFloor'), isNull);
        expect(await disk.setting('remoteConfigState'), isNull);
      } finally {
        await disk.close();
        await databaseFactoryFfi.deleteDatabase(path);
      }
    },
  );

  test(
    'published disabled static document matches strict checksum registry',
    () {
      final json = (jsonDecode(
        File('site\\config.json').readAsStringSync(),
      ) as Map).cast<String, dynamic>();
      final config = RemoteConfig.parse(
        json,
        now: DateTime.parse(json['issuedAt']).add(const Duration(minutes: 1)),
      );
      expect(config.enabled, isFalse);
      expect(config.title('test-account'), RemoteConfig.control);
      expect(RemoteConfig.reviewedEvidenceChecksum, isEmpty);
    },
  );

  test(
    'expiry and clock changes are checked again after download completes',
    () async {
      var date = now;
      final json = document(now);
      json['expiresAt'] = now.add(const Duration(seconds: 2)).toIso8601String();
      seal(json);
      final expired = await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => date,
        client: MockClient((_) async {
          date = now.add(const Duration(seconds: 3));
          return http.Response(jsonEncode(json), 200);
        }),
      );
      expect(expired.config, RemoteConfig.defaults);
      expect(expired.warning, isNotNull);
      date = now;
      final backwards = await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => date,
        client: MockClient((_) async {
          date = now.subtract(const Duration(seconds: 1));
          return http.Response(jsonEncode(document(now)), 200);
        }),
      );
      expect(backwards.config, RemoteConfig.defaults);
      expect(backwards.warning, isNotNull);
      expect(await store.setting('remoteConfigFloor'), isNull);
    },
  );

  test('download timeout is bounded across both headers and body', () async {
    final pending = Completer<http.Response>();
    final watch = Stopwatch()..start();
    try {
      final result = await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => now,
        client: MockClient((_) => pending.future),
      );
      expect(result.warning, isNotNull);
      expect(result.config, RemoteConfig.defaults);
      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
    } finally {
      pending.complete(http.Response('', 503));
    }
  });

  test('recomputed higher cache document cannot bypass the persisted accepted checksum', () async {
    await RemoteConfig.fetch(
      store,
      origin: 'https://approved.example',
      clock: () => now,
      client: MockClient(
        (_) async => http.Response(jsonEncode(document(now)), 200),
      ),
    );
    final state =
        jsonDecode((await store.setting('remoteConfigState'))!) as Map;
    state['document'] = document(now, version: 99);
    await store.setSetting('remoteConfigState', jsonEncode(state));
    final result = await RemoteConfig.fetch(
      store,
      origin: 'https://approved.example',
      clock: () => now,
      client: MockClient((_) async => http.Response('', 503)),
    );
    expect(result.config, RemoteConfig.defaults);
    expect(result.warning, isNotNull);
  });

  test(
    'reject unsafe origin, oversized response and account changes',
    () async {
      for (final origin in [
        '',
        'http://approved.example',
        'https://u:p@example.com',
        'https://example.com/?secret=1',
      ]) {
        var called = false;
        final result = await RemoteConfig.fetch(
          store,
          origin: origin,
          clock: () => now,
          client: MockClient((_) async {
            called = true;
            return http.Response('{}', 200);
          }),
        );
        expect(called, isFalse);
        expect(result.warning, isNotNull);
      }
      final large = await RemoteConfig.fetch(
        store,
        origin: 'https://approved.example',
        clock: () => now,
        client: MockClient((_) async => http.Response('x' * 8193, 200)),
      );
      expect(large.config, RemoteConfig.defaults);
      await expectLater(
        RemoteConfig.fetch(
          store,
          origin: 'https://approved.example',
          clock: () => now,
          client: MockClient((_) async {
            await store.switchAccount('config-b');
            return http.Response(jsonEncode(document(now)), 200);
          }),
        ),
        throwsStateError,
      );
      expect(await store.setting('remoteConfigState'), isNull);
    },
  );
}
