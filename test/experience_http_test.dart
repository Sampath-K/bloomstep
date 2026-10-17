import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/services/experience_experiments.dart';
import 'package:bloomstep/services/sync_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../integration_test/support/local_test_api.dart';
import '../integration_test/support/test_only_app.dart';

class _LostPurgeAck extends http.BaseClient {
  final _inner = http.Client();
  bool drop = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (drop &&
        request is http.Request &&
        request.method == 'POST' &&
        ((jsonDecode(request.body) as Map)['deletions'] as List? ?? [])
            .isNotEmpty) {
      drop = false;
      expect(response.statusCode, 200);
      await response.stream.drain<void>();
      throw http.ClientException('Synthetic lost purge acknowledgment.');
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

void main() {
  test('real app SQLite to authenticated HTTP: restart, effective practice, offline purge retry and suppression', () async {
    final root = await Directory.systemTemp.createTemp(
      'bloomstep-it-experience-',
    );
    final secret = List.generate(
      32,
      (_) => Random.secure().nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final identity = SyntheticTestSession('synthetic-experience', secret);
    final api = await LocalTestApi.start(runRoot: root, secret: secret);
    var now = DateTime.now().toUtc().subtract(const Duration(days: 8));
    final start = now;
    final path = p.join(root.path, 'app.db');
    var store = await GardenStore.open(
      path,
      identity.account!,
      clock: () => now,
    );
    final client = _LostPurgeAck();
    final config = ExperienceConfig.synthetic(
      ExperienceSurface.gardenPrompt,
      startAt: start,
    );
    Future<List<Map>> docs() async =>
        ((jsonDecode(
                  await File(p.join(root.path, 'server.json')).readAsString(),
                ) as Map)['documents']
                as List)
            .cast<Map>();
    SyncService sync() =>
        SyncService(identity, store, client: client, testApiOrigin: api.origin);
    try {
      await store.setSetting('analytics', 'true');
      var experiments = ExperienceExperiments(
        store,
        config: config,
        clock: () => now,
      );
      final assignment = await experiments.resolve(
        ExperienceSurface.gardenPrompt,
      );
      await experiments.rendered(assignment);
      final habit = await store.plant(
        aspiration: 'PRIVATE CONTENT',
        anchor: 'PRIVATE CONTENT',
        behavior: 'PRIVATE CONTENT',
        celebration: 'PRIVATE CONTENT',
        species: 'Fern',
      );
      now = start.add(const Duration(days: 2));
      await store.checkIn(habit.id, CheckInResult.did);
      await sync().sync();
      await store.close();
      store = await GardenStore.open(path, identity.account!, clock: () => now);
      experiments = ExperienceExperiments(
        store,
        config: config,
        clock: () => now,
      );
      final reopened = await experiments.resolve(
        ExperienceSurface.gardenPrompt,
      );
      expect(reopened.cohortId, assignment.cohortId);
      expect(reopened.arm, assignment.arm);
      now = start.add(const Duration(days: 7));
      await experiments.followup();
      await sync().sync();
      final before = (await docs())
          .where(
            (d) =>
                d['type'] == 'events' &&
                (d['record'] as Map)['name'] == 'experience_observation',
          )
          .toList();
      expect(before, hasLength(4));
      expect(jsonEncode(before), isNot(contains('PRIVATE CONTENT')));
      final beforeHash = sha256
          .convert(utf8.encode(jsonEncode(before)))
          .toString();
      await store.setSetting('analytics', 'false');
      final marker = ((await store.syncPayload())['deletions'] as List).single;
      await expectLater(sync().sync(), throwsA(isA<http.ClientException>()));
      expect((await store.syncPayload())['deletions'], [marker]);
      expect(
        (await docs()).where(
          (d) =>
              d['type'] == 'events' &&
              (d['record'] as Map)['name'] == 'experience_observation',
        ),
        isEmpty,
      );
      await store.close();
      store = await GardenStore.open(path, identity.account!, clock: () => now);
      await sync().sync();
      expect((await store.syncPayload())['deletions'], isEmpty);
      expect((await store.habits()).single.id, habit.id);
      expect(
        (await docs()).where(
          (d) =>
              d['type'] == 'events' &&
              (d['record'] as Map)['name'] == 'session_started',
        ),
        isEmpty,
      );
      expect(
        (await docs()).where(
          (d) =>
              d['type'] == 'events' &&
              (d['record'] as Map)['name'] == 'recipe_created',
        ),
        hasLength(1),
      );
      final evidence = Platform.environment['EXPERIENCE_EVIDENCE_DIR'];
      if (evidence != null) {
        final out = File(p.join(evidence, 'app-http-receipt.json'));
        await out.parent.create(recursive: true);
        await out.writeAsString(
          jsonEncode({
            'kind': 'isolated-synthetic-app-experience-http',
            'passed': true,
            'syntheticOnly': true,
            'customerData': false,
            'productionWrites': false,
            'sourcePolicyHash': experiencePolicyHash,
            'persistedObservations': before.length,
            'persistedHash': beforeHash,
            'sqliteRestartAssignmentStable': true,
            'lostPurgeAckRetriedAfterRestart': true,
            'purgedRemoteExperimentEvents': true,
            'unrelatedRecipeAndEventsPreserved': true,
            'paidServices': [],
            'newBillableResources': [],
          }),
        );
      }
    } finally {
      client.close();
      await store.close();
      await api.close();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
