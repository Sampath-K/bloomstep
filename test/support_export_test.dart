import 'dart:async';
import 'dart:convert';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/services/identity.dart';
import 'package:bloomstep/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Identity extends IdentityService {
  _Identity(String owner) {
    account = owner;
  }
  @override
  Future<String> accessToken() async => 'synthetic-token';
}

const _id = 'd2bb9b7d-481f-4ac5-bfba-808bdf4e2fda';
Map<String, Object?> _receipt() => {
  'id': _id,
  'schemaVersion': 1,
  'receivedAt': '2026-09-01T12:00:00.000Z',
  'firstRespondedAt': '2026-09-01T14:00:00.000Z',
};

void main() {
  test('prepared owner export surfaces component failures without implying a complete server export', () async {
    final store = await GardenStore.open(
      ':memory:',
      'synthetic-prepared-export',
    );
    addTearDown(store.close);
    await store.submitVoice('Idea', 'Synthetic local export');
    final before = await store.export();
    final client = MockClient((_) async => http.Response('{}', 200));
    addTearDown(client.close);
    final prepared =
        await SyncService(
          _Identity(store.account),
          store,
          client: client,
        ).prepareOwnerExport(
          invitationExport: () async =>
              throw StateError('Synthetic unavailable invitation service'),
        );
    expect(prepared.data['voice'], before['voice']);
    expect(prepared.data.containsKey('serverSupportReceipts'), isFalse);
    expect(
      prepared.data['supportReceiptExportWarning'],
      contains('not exported'),
    );
    expect(
      prepared.data['invitationExportWarning'],
      contains('not a current server export'),
    );
    expect(prepared.warnings, hasLength(2));
    expect(await store.export(), before);
  });

  test('prepared export preserves successful private server components and rejects a changed generation even in fallback', () async {
    final store = await GardenStore.open(
      ':memory:',
      'synthetic-prepared-success',
    );
    addTearDown(store.close);
    var invalidate = false;
    final client = MockClient((_) async {
      if (invalidate) await store.deleteLocalAccount();
      return http.Response(
        jsonEncode({
          'voiceReceipts': [_receipt()],
        }),
        200,
      );
    });
    addTearDown(client.close);
    final service = SyncService(
      _Identity(store.account),
      store,
      client: client,
    );
    final prepared = await service.prepareOwnerExport(
      invitationExport: () async => {'schemaVersion': 1, 'creations': []},
    );
    expect(prepared.warnings, isEmpty);
    expect(
      prepared.data['serverSupportReceipts'],
      containsPair('receipts', [_receipt()]),
    );
    expect(prepared.data['serverInvitations'], {
      'schemaVersion': 1,
      'creations': [],
    });
    invalidate = true;
    await expectLater(service.prepareOwnerExport(), throwsStateError);
  });

  test('owner receipts export is GET-only, with no merge, acknowledgment or clock invention', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-export');
    addTearDown(store.close);
    await store.submitVoice('Idea', 'Synthetic local note');
    final before = await store.export();
    final pending = await store.syncPayload();
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/sync');
      expect(
        request.headers['X-Bloomstep-Authorization'],
        'Bearer synthetic-token',
      );
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response(
        jsonEncode({
          'voiceReceipts': [_receipt()],
          'voice': [
            {'id': _id, 'body': 'Synthetic remote note: must not be merged'},
          ],
        }),
        200,
      );
    });
    addTearDown(client.close);
    final exported = await SyncService(
      _Identity(store.account),
      store,
      client: client,
    ).exportVoiceReceipts();
    expect(exported['source'], 'server_voice_receipts');
    expect(exported['receipts'], [_receipt()]);
    expect(await store.export(), before);
    expect(await store.syncPayload(), pending);
    expect(await store.setting('lastSync'), isNull);
  });

  test('legacy and older-writer unknown facts stay explicit, never inferred from local replies', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-legacy-export');
    addTearDown(store.close);
    final rows = [
      {
        ..._receipt(),
        'receivedAt': null,
        'firstRespondedAt': null,
        'reason': 'legacy_receipt_unavailable',
      },
      {
        ..._receipt(),
        'id': '54a84e6b-328a-4dd9-aa99-6823b7a7b6c8',
        'firstRespondedAt': null,
        'reason': 'first_response_unavailable',
      },
    ];
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'voiceReceipts': rows}), 200),
    );
    addTearDown(client.close);
    final exported = await SyncService(
      _Identity(store.account),
      store,
      client: client,
    ).exportVoiceReceipts();
    expect(exported['receipts'], rows);
  });

  test('old backend, malformed receipts, failed transport and offline remain export errors', () async {
    final store = await GardenStore.open(
      ':memory:',
      'synthetic-invalid-export',
    );
    addTearDown(store.close);
    final badRows = [
      {..._receipt(), 'id': 'not-a-record'},
      {..._receipt(), 'receivedAt': '2026-02-30T12:00:00.000Z'},
      {..._receipt(), 'receivedAt': '2026-09-01T12:00:00+00:00'},
      {..._receipt(), 'firstRespondedAt': '2026-09-01T11:00:00.000Z'},
      {..._receipt(), 'receivedAt': null},
      {..._receipt(), 'reason': 'legacy_receipt_unavailable'},
      {..._receipt(), 'reason': 'first_response_unavailable'},
      {..._receipt(), 'body': 'Must not leak extra private server payload'},
    ];
    for (final body in [
      <String, Object?>{},
      {'voiceReceipts': 'invalid'},
      {
        'voiceReceipts': [_receipt(), _receipt()],
      },
      for (final row in badRows)
        {
          'voiceReceipts': [row],
        },
    ]) {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(body), 200),
      );
      try {
        await expectLater(
          SyncService(
            _Identity(store.account),
            store,
            client: client,
          ).exportVoiceReceipts(),
          throwsA(anything),
        );
      } finally {
        client.close();
      }
    }
    for (final status in [401, 409, 503]) {
      final client = MockClient(
        (_) async => http.Response('unavailable', status),
      );
      try {
        await expectLater(
          SyncService(
            _Identity(store.account),
            store,
            client: client,
          ).exportVoiceReceipts(),
          throwsStateError,
        );
      } finally {
        client.close();
      }
    }
    final offline = MockClient(
      (_) async => throw http.ClientException('Synthetic offline'),
    );
    addTearDown(offline.close);
    await expectLater(
      SyncService(
        _Identity(store.account),
        store,
        client: offline,
      ).exportVoiceReceipts(),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('locally deleted owner voice receipts are not resurrected by read-only export', () async {
    final store = await GardenStore.open(
      ':memory:',
      'synthetic-deleted-export',
    );
    addTearDown(store.close);
    await store.submitVoice('Idea', 'Synthetic delete fixture');
    final id = (await store.voice()).single['id'];
    await store.deleteRecord('voice', id as String);
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'voiceReceipts': [
            {..._receipt(), 'id': id},
          ],
        }),
        200,
      ),
    );
    addTearDown(client.close);
    final before = await store.export();
    final exported = await SyncService(
      _Identity(store.account),
      store,
      client: client,
    ).exportVoiceReceipts();
    expect(exported['receipts'], isEmpty);
    expect(await store.export(), before);
  });

  test('account mismatch never requests server receipts; same-account generation change rejects late read', () async {
    final store = await GardenStore.open(
      ':memory:',
      'synthetic-generation-export',
    );
    addTearDown(store.close);
    var calls = 0;
    final gate = Completer<void>();
    final client = MockClient((_) async {
      calls++;
      await gate.future;
      return http.Response(
        jsonEncode({
          'voiceReceipts': [_receipt()],
        }),
        200,
      );
    });
    addTearDown(client.close);
    await expectLater(
      SyncService(
        _Identity('another-owner'),
        store,
        client: client,
      ).exportVoiceReceipts(),
      throwsStateError,
    );
    expect(calls, 0);
    final operation = SyncService(
      _Identity(store.account),
      store,
      client: client,
    ).exportVoiceReceipts();
    while (calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await store.deleteLocalAccount();
    gate.complete();
    await expectLater(operation, throwsStateError);
  });

  test(
    'changed identity during GET cannot export an old owner receipt',
    () async {
      final store = await GardenStore.open(
        ':memory:',
        'synthetic-identity-export',
      );
      addTearDown(store.close);
      final identity = _Identity(store.account);
      final client = MockClient((_) async {
        identity.account = 'another-owner';
        return http.Response(
          jsonEncode({
            'voiceReceipts': [_receipt()],
          }),
          200,
        );
      });
      addTearDown(client.close);
      await expectLater(
        SyncService(identity, store, client: client).exportVoiceReceipts(),
        throwsStateError,
      );
    },
  );
}
