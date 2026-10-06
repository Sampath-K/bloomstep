import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/services/auth_observations.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<Map>> observations(GardenStore store) async =>
    ((await store.export())['events'] as List)
        .cast<Map>()
        .where((row) => row['name'] == 'auth_observation')
        .map((row) => jsonDecode(row['properties'] as String) as Map)
        .toList();

void main() {
  test('real accessToken seam observes unavailable offline session without a test authenticator', () async {
    final store = await GardenStore.open(':memory:', 'a');
    addTearDown(store.close);
    await store.setSetting('analytics', 'true');
    final observer = AuthObservations(store, onWriteError: (_) {});
    final identity = IdentityService()
      ..account = 'a'
      ..observations = observer;
    await expectLater(identity.accessToken(), throwsA(isA<AuthFailure>()));
    final rows = await observations(store);
    expect(rows, hasLength(2));
    expect(rows[1]['authStage'], 'api_token');
    expect(rows[1]['authErrorKind'], 'unavailable');
    identity.account = 'b';
    await expectLater(identity.accessToken(), throwsA(isA<AuthFailure>()));
    expect(await observations(store), hasLength(2));
    observer.close();
  });

  test('closed client schema rejects arbitrary payloads and unguarded observations', () async {
    final store = await GardenStore.open(':memory:', 'a');
    addTearDown(store.close);
    await store.setSetting('analytics', 'true');
    await expectLater(store.track('auth_observation'), throwsArgumentError);
    final base = <String, Object?>{
      'attemptId': '11111111-1111-4111-8111-111111111111',
      'authStage': 'api_token',
      'outcome': 'started',
      'authErrorKind': 'none',
      'authSource': 'external_unattributed',
      'elapsedMs': 0,
      'platform': 'windows',
    };
    for (final properties in [
      {...base, 'token': 'secret'},
      {...base, 'authSource': 'microsoft'},
      {...base, 'outcome': 'failed'},
      {...base, 'elapsedMs': 180001},
    ]) {
      await expectLater(
        store.trackAuthObservation(
          properties,
          owner: 'a',
          generation: store.syncGeneration,
          consentGeneration: store.analyticsGeneration,
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      store.track('auth_observation', properties: base),
      throwsStateError,
    );
    expect(await observations(store), isEmpty);
  });

  test(
    'stage-specific auth errors stay actionable without raw callback details',
    () async {
      for (final step in AuthStep.values) {
        for (final error in [
          TimeoutException('token code state nonce PKCE'),
          const SocketException('issuer email subject'),
          const FormatException('https://secret?access_token=private'),
          StateError('private stack'),
        ]) {
          await expectLater(
            guardAuthStep(step, () async => throw error),
            throwsA(
              isA<AuthFailure>()
                  .having(
                    (failure) => failure.message,
                    'safe message',
                    step.message,
                  )
                  .having(
                    (failure) => failure.kind,
                    'fixed category',
                    AuthObservations.errorKind(error),
                  ),
            ),
          );
        }
      }
      expect(AuthObservations.errorKind(StateError('cancelled')), 'unknown');
    },
  );

  test(
    'expired and rollback elapsed clocks never invent terminal evidence',
    () async {
      final store = await GardenStore.open(':memory:', 'a');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      var clock = Duration.zero;
      final observer = AuthObservations(
        store,
        onWriteError: (_) {},
        monotonicNow: () => clock,
      );
      for (final duration in [
        const Duration(milliseconds: 180001),
        const Duration(milliseconds: -1),
      ]) {
        clock = Duration.zero;
        expect(
          await observer.run(AuthStage.apiToken, () async {
            clock = duration;
            return 'credential';
          }),
          'credential',
        );
      }
      expect(await observations(store), hasLength(2));
      expect(
        (await observations(store)).every((row) => row['outcome'] == 'started'),
        isTrue,
      );
    },
  );

  test(
    'concurrent retries each get a distinct ID and respect the shared cap',
    () async {
      final store = await GardenStore.open(':memory:', 'a');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      final observer = AuthObservations(store, onWriteError: (_) {});
      await Future.wait(
        List.generate(
          20,
          (_) => observer.run(AuthStage.apiToken, () async => 'credential'),
        ),
      );
      final rows = await observations(store);
      expect(rows, hasLength(20));
      expect(rows.map((row) => row['attemptId']).toSet(), hasLength(10));
      expect(rows.where((row) => row['outcome'] == 'succeeded'), hasLength(10));
    },
  );

  test('no consent, no capture or retrospective backfill', () async {
    final store = await GardenStore.open(':memory:', 'a');
    addTearDown(store.close);
    final observer = AuthObservations(store, onWriteError: (_) {});
    await expectLater(
      observer.run(AuthStage.apiToken, () async {
        throw const SocketException('secret token');
      }),
      throwsA(isA<SocketException>()),
    );
    await store.setSetting('analytics', 'true');
    expect(await observations(store), isEmpty);
  });

  test('paired bounded stages contain no identity or exception text', () async {
    final store = await GardenStore.open(':memory:', 'a');
    addTearDown(store.close);
    await store.setSetting('analytics', 'true');
    final observer = AuthObservations(store, onWriteError: (_) {});
    for (var i = 0; i < 12; i++) {
      await expectLater(
        observer.run(AuthStage.apiToken, () async {
          throw TimeoutException('https://secret?code=private');
        }),
        throwsA(isA<TimeoutException>()),
      );
    }
    final rows = await observations(store);
    expect(rows, hasLength(20));
    expect(rows.first['outcome'], 'started');
    expect(rows[1]['outcome'], 'failed');
    expect(rows[1]['authErrorKind'], 'timeout');
    expect(rows[1]['attemptId'], rows.first['attemptId']);
    expect(rows.toString(), isNot(contains('private')));
    expect(rows.toString(), isNot(contains('secret')));
  });

  test(
    'withdraw/reconsent, account switch and closed scopes discard pending',
    () async {
      for (final change in ['withdraw', 'switch', 'close']) {
        final store = await GardenStore.open(':memory:', 'a');
        await store.setSetting('analytics', 'true');
        final observer = AuthObservations(store, onWriteError: (_) {});
        final pending = Completer<String>();
        final work = observer.run(AuthStage.apiToken, () => pending.future);
        while ((await observations(store)).isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        if (change == 'withdraw') {
          await store.setSetting('analytics', 'false');
          await store.setSetting('analytics', 'true');
        } else if (change == 'switch') {
          await store.switchAccount('b');
          await store.setSetting('analytics', 'true');
        } else {
          observer.close();
        }
        pending.complete('credential');
        expect(await work, 'credential');
        final rows = await observations(store);
        expect(rows.any((row) => row['outcome'] == 'succeeded'), isFalse);
        await store.close();
      }
    },
  );

  test(
    'telemetry storage failure warns but cannot block authentication',
    () async {
      final store = await GardenStore.open(':memory:', 'a');
      final warnings = <String>[];
      final observer = AuthObservations(store, onWriteError: warnings.add);
      await store.close();
      expect(
        await observer.run(AuthStage.apiToken, () async => 'token'),
        'token',
      );
      expect(warnings, hasLength(1));
      expect(warnings.single, isNot(contains('token')));
    },
  );
}
