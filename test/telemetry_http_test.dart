import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/measurement_receipt.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/services/sync_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../integration_test/support/local_test_api.dart';
import '../integration_test/support/test_only_app.dart';

class _LostAcknowledgement extends http.BaseClient {
  final _inner = http.Client();
  bool loseNextEvents = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final lose =
        loseNextEvents &&
        request is http.Request &&
        request.method == 'POST' &&
        ((jsonDecode(request.body) as Map)['events'] as List? ?? []).isNotEmpty;
    final response = await _inner.send(request);
    if (lose) {
      loseNextEvents = false;
      expect(response.statusCode, 200);
      await response.stream.drain<void>();
      throw http.ClientException('Synthetic lost acknowledgement.');
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

void main() {
  test('real SQLite receipt import and HTTP sync persist once across lost ack, revoke and account deletion', () async {
    expect(
      const bool.fromEnvironment('BLOOMSTEP_TEST_BUILD'),
      isTrue,
      reason: 'Run with --dart-define=BLOOMSTEP_TEST_BUILD=true.',
    );
    final receiptPath = Platform.environment['BLOOMSTEP_TEST_RECEIPT_PATH'];
    final runRoot = await Directory.systemTemp.createTemp('bloomstep-it-app-');
    final evidenceDir = Platform.environment['EVIDENCE_DIR'] ?? runRoot.path;
    final fixtureAt = DateTime.now()
        .toUtc()
        .subtract(const Duration(seconds: 1))
        .toIso8601String();
    final receiptText = receiptPath != null
        ? await File(receiptPath).readAsString()
        : jsonEncode({
            'schemaVersion': 1,
            'source': 'website',
            'consentedAt': fixtureAt,
            'events': [
              {
                'id': '00000000-0000-4000-8000-000000000001',
                'name': 'landing_view',
                'ts': fixtureAt,
              },
              {
                'id': '00000000-0000-4000-8000-000000000002',
                'name': 'download_click',
                'ts': fixtureAt,
              },
            ],
          });
    final receipt = MeasurementReceipt.parse(receiptText);
    final secret = List.generate(
      32,
      (_) => Random.secure().nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final identity = SyntheticTestSession('synthetic-telemetry', secret);
    final api = await LocalTestApi.start(
      runRoot: runRoot,
      secret: secret,
      telemetry: true,
    );
    final database = File(p.join(runRoot.path, 'server.json'));
    final store = await GardenStore.open(
      p.join(runRoot.path, 'app.db'),
      identity.account!,
    );
    final client = _LostAcknowledgement();
    final sync = SyncService(
      identity,
      store,
      client: client,
      testApiOrigin: api.origin,
    );
    Future<List<Map>> persisted() async =>
        ((jsonDecode(await database.readAsString()) as Map)['documents']
                as List)
            .cast<Map>();
    Future<List<Map>> savedEvents() async =>
        (await persisted()).where((doc) => doc['type'] == 'events').toList();
    Map<String, Object?>? result;
    try {
      await expectLater(
        store.importMeasurementReceipt(receipt),
        throwsStateError,
      );
      final preConsent = await store.plant(
        aspiration: 'Synthetic private aspiration',
        anchor: 'Synthetic private anchor',
        behavior: 'Synthetic private habit',
        celebration: 'Synthetic private celebration',
        species: 'Fern',
      );
      expect(preConsent.id, isNotEmpty);
      expect((await store.syncPayload())['events'], isEmpty);
      await store.setSetting('analytics', 'true');
      expect(
        await store.importMeasurementReceipt(receipt),
        receipt.events.length,
      );
      expect(await store.importMeasurementReceipt(receipt), 0);
      await store.track(
        'signin_succeeded',
        properties: {'platform': 'windows', 'provider': 'microsoft'},
      );
      // Launch funnel: a habit planted after consent + receipt link is attributable.
      final habit = await store.plant(
        aspiration: 'Synthetic private aspiration two',
        anchor: 'Synthetic private anchor two',
        behavior: 'Synthetic private habit two',
        celebration: 'Synthetic private celebration two',
        species: 'Fern',
      );
      await store.checkIn(habit.id, CheckInResult.did);
      final pending = ((await store.syncPayload())['events'] as List)
          .cast<Map>();
      await expectLater(sync.sync(), throwsA(isA<http.ClientException>()));
      final before = await savedEvents();
      expect(before, hasLength(pending.length));
      expect((await store.syncPayload())['events'], pending);
      await sync.sync();
      final after = await savedEvents();
      expect(
        after.map((doc) => doc['record']).toList(),
        before.map((doc) => doc['record']).toList(),
      );
      expect((await store.syncPayload())['events'], isEmpty);
      for (final observation in receipt.events) {
        final saved =
            (after.singleWhere(
                  (doc) => (doc['record'] as Map)['id'] == observation.id,
                )['record']
                as Map);
        expect(saved['ts'], observation.at.toIso8601String());
        expect(
          (saved['properties'] as Map)['measurementSource'],
          'website_receipt',
        );
      }
      expect(jsonEncode(after), isNot(contains('Synthetic private')));
      final eventsText = jsonEncode(
        after
            .map((doc) => {'userId': doc['userId'], 'record': doc['record']})
            .toList(),
      );
      final eventsFile = File(p.join(evidenceDir, 'app-events.json'));
      if (await eventsFile.exists()) {
        throw StateError('Refusing to overwrite app evidence.');
      }
      await eventsFile.writeAsString(eventsText);
      await store.track('share_initiated', properties: {'channel': 'link'});
      await store.setSetting('analytics', 'false');
      expect((await store.syncPayload())['events'], isEmpty);
      expect((await store.export())['events'], isEmpty);
      await sync.sync();
      expect(
        await savedEvents(),
        hasLength(after.length),
        reason: 'Revocation stops/purges local collection; already accepted server observations require separate deletion.',
      );
      await store.setSetting('analytics', 'true');
      final newConsent =
          ((await store.syncPayload())['events'] as List).single as Map;
      expect(
        pending.map((event) => event['id']),
        isNot(contains(newConsent['id'])),
      );
      final response = await http.delete(
        api.origin.resolve('/api/account'),
        headers: {
          'X-Bloomstep-Authorization': 'Bearer ${await identity.accessToken()}',
          'X-Confirm-Delete': 'delete-my-garden',
        },
      );
      expect(response.statusCode, 204);
      expect(await savedEvents(), isEmpty);
      expect(
        (await persisted())
            .where((doc) => doc['type'] == 'account')
            .single['deleted'],
        isTrue,
      );
      await expectLater(sync.sync(), throwsStateError);
      result = {
        'schemaVersion': 1,
        'kind': 'isolated-synthetic-app-telemetry',
        'passed': true,
        'customerAuthentication': false,
        'installerExecuted': false,
        'receiptEvents': receipt.events.length,
        'receiptOrigin': receiptPath == null
            ? 'synthetic_fixture'
            : 'browser_export',
        'persistedEvents': after.length,
        'eventsSha256': sha256.convert(utf8.encode(eventsText)).toString(),
        'receiptSha256': sha256.convert(utf8.encode(receiptText)).toString(),
        'scenarios': [
          'consent off',
          'explicit real browser receipt import',
          'original UUID/timestamp preserved',
          'idempotent import',
          'real app positive check-in',
          'real HTTP persisted collector lost-ack retry dedup',
          'local revocation/purge',
          'new consent identity',
          'server account deletion and rejected resurrection',
        ],
      };
    } finally {
      client.close();
      await store.close();
      await identity.signOut();
      await api.close();
      await runRoot.delete(recursive: true);
      expect(await runRoot.exists(), isFalse);
      if (result != null && Platform.environment['EVIDENCE_DIR'] != null) {
        result['cleanupVerified'] = true;
        final file = File(p.join(evidenceDir, 'app-telemetry-receipt.json'));
        if (await file.exists()) {
          throw StateError('Refusing to overwrite previous evidence.');
        }
        await file.writeAsString(jsonEncode(result));
      }
    }
  }, skip: !const bool.fromEnvironment('BLOOMSTEP_TEST_BUILD'));
}
