import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/garden_store.dart';
import 'identity.dart';

class SyncService {
  SyncService(this.identity, this.store, {this.client});
  final IdentityService identity;
  final GardenStore store;
  final http.Client? client;
  bool _running = false;

  static String _apiError(http.Response response) {
    if (response.body.length > 16384) return '';
    try {
      final data = jsonDecode(response.body);
      if (data is! Map || data['error'] is! String) return '';
      final message = (data['error'] as String)
          .replaceAll(
            RegExp(r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]'),
            ' ',
          )
          .trim();
      if (message.isEmpty) return '';
      return ' ${message.length > 500 ? '${message.substring(0, 500)}…' : message}';
    } on FormatException {
      return '';
    }
  }

  Future<void> sync() async {
    if (_running) return;
    _running = true;
    try {
      final account = store.account;
      final generation = store.syncGeneration;
      if (identity.account != account) {
        throw StateError(
          'Sign in to the account that owns this garden before syncing.',
        );
      }
      final token = await identity.accessToken();
      store.requireSyncSession(account, generation);
      final pendingDeletions =
          (await store.syncPayload())['deletions'] as List? ?? [];
      for (var start = 0; start < pendingDeletions.length; start += 100) {
        final chunk = <String, Object?>{
          for (final t in GardenStore.syncTables) t: [],
        };
        chunk['deletions'] = pendingDeletions.sublist(
          start,
          (start + 100).clamp(0, pendingDeletions.length),
        );
        await _request(token, chunk, account, generation);
      }
      final payload = await store.syncPayload();
      const tables = GardenStore.syncTables;
      for (final table in tables) {
        final records = payload[table] as List;
        final size = table == 'checkins' || table == 'events' ? 500 : 25;
        for (var start = 0; start < records.length; start += size) {
          final chunk = <String, Object?>{for (final t in tables) t: []};
          chunk[table] = records.sublist(
            start,
            (start + size).clamp(0, records.length),
          );
          if (table == 'events') {
            final pending = (await store.syncPayload())['events'] as List;
            final ids = pending.map((row) => (row as Map)['id']).toSet();
            chunk[table] = (chunk[table] as List)
                .where((row) => ids.contains((row as Map)['id']))
                .toList();
            if ((chunk[table] as List).isEmpty) continue;
          }
          await _request(token, chunk, account, generation);
        }
      }
      await _request(token, null, account, generation);
      store.requireSyncSession(account, generation);
      await store.setSetting(
        'lastSync',
        DateTime.now().toUtc().toIso8601String(),
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _request(
    String token,
    Map<String, Object?>? body,
    String account,
    int generation,
  ) async {
    final received = await _fetch(token, body, account, generation);
    if ((body?['deletions'] as List? ?? []).isNotEmpty) {
      final acknowledgments = received['deletions'];
      if (acknowledgments is! List ||
          (body!['deletions'] as List).any(
            (raw) => !acknowledgments.any(
              (row) =>
                  row is Map &&
                  row['type'] == (raw as Map)['type'] &&
                  row['recordId'] == raw['recordId'],
            ),
          )) {
        throw StateError(
          'The service did not confirm record deletion. Local removal remains queued; retry safely.',
        );
      }
    }
    await store.mergeSync(received, account: account, generation: generation);
    if (body != null) {
      await store.acknowledgeSync(
        body,
        account: account,
        generation: generation,
      );
    }
  }

  Future<Map<String, dynamic>> _fetch(
    String token,
    Map<String, Object?>? body,
    String account,
    int generation,
  ) async {
    store.requireSyncSession(account, generation);
    final url = Uri.parse('${IdentityService.apiOrigin}/api/sync');
    final headers = {
      'X-Bloomstep-Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final httpClient = client ?? http.Client();
    late http.Response response;
    try {
      response = body == null
          ? await httpClient
                .get(url, headers: headers)
                .timeout(const Duration(seconds: 30))
          : await httpClient
                .post(url, headers: headers, body: jsonEncode(body))
                .timeout(const Duration(seconds: 30));
    } finally {
      if (client == null) httpClient.close();
    }
    store.requireSyncSession(account, generation);
    if (response.statusCode != 200) {
      throw StateError(
        'Sync failed (HTTP ${response.statusCode}).${_apiError(response)} Local changes remain on this device.',
      );
    }
    return (jsonDecode(response.body) as Map).cast<String, dynamic>();
  }

  void _requireExportOwner(String owner, int generation) {
    store.requireSyncSession(owner, generation);
    if (identity.account != owner) {
      throw StateError(
        'Sign in to the garden owner before exporting server data.',
      );
    }
  }

  Future<({Map<String, Object?> data, List<String> warnings})>
  prepareOwnerExport({
    Future<Map<String, Object?>> Function()? invitationExport,
  }) async {
    final owner = store.account;
    final generation = store.syncGeneration;
    _requireExportOwner(owner, generation);
    final data = await store.export();
    _requireExportOwner(owner, generation);
    final warnings = <String>[];
    if (invitationExport != null) {
      try {
        data['serverInvitations'] = await invitationExport();
      } catch (_) {
        data['invitationExportWarning'] = 'Offline or unavailable: includes local receipts only, not a current server export.';
        warnings.add('Server invitation receipts are unavailable.');
      }
      _requireExportOwner(owner, generation);
    }
    try {
      data['serverSupportReceipts'] = await exportVoiceReceipts();
    } catch (_) {
      data['supportReceiptExportWarning'] = 'Offline, unavailable, or incompatible service: server support receipts were not exported. No receipt or response times were inferred from local feedback.';
      warnings.add('Server support receipts are unavailable.');
    }
    _requireExportOwner(owner, generation);
    return (data: data, warnings: List<String>.unmodifiable(warnings));
  }

  Future<Map<String, Object?>> exportVoiceReceipts() async {
    final owner = store.account;
    final generation = store.syncGeneration;
    void requireOwner() => _requireExportOwner(owner, generation);

    requireOwner();
    final token = await identity.accessToken();
    requireOwner();
    final received = await _fetch(token, null, owner, generation);
    requireOwner();
    final rows = received['voiceReceipts'];
    if (rows is! List) {
      throw StateError(
        'This service does not provide server support receipts. Their export is unavailable.',
      );
    }
    if (rows.length > 10000) {
      throw const FormatException(
        'Server support receipt export exceeds the record cap.',
      );
    }
    final deleted = (await store.deletedVoiceIds()).toSet();
    requireOwner();
    final ids = <String>{};
    final receipts = <Map<String, Object?>>[];
    final uuid = RegExp(
      r'^(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)$',
      caseSensitive: false,
    );
    DateTime? timestamp(Object? value) {
      if (value == null) return null;
      if (value is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
              .hasMatch(value)) {
        throw const FormatException(
          'Invalid server support receipt timestamp.',
        );
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null || parsed.toIso8601String() != value) {
        throw const FormatException(
          'Invalid server support receipt timestamp.',
        );
      }
      return parsed;
    }

    for (final row in rows) {
      if (row is! Map ||
          row.keys.any(
            (key) => !const {
              'id',
              'schemaVersion',
              'receivedAt',
              'firstRespondedAt',
              'reason',
            }.contains(key),
          ) ||
          !row.keys.toSet().containsAll({
            'id',
            'schemaVersion',
            'receivedAt',
            'firstRespondedAt',
          }) ||
          row['schemaVersion'] != 1 ||
          row['id'] is! String ||
          !uuid.hasMatch(row['id'] as String) ||
          !ids.add(row['id'] as String)) {
        throw const FormatException(
          'Invalid or duplicate server support receipt.',
        );
      }
      final receipt = timestamp(row['receivedAt']);
      final response = timestamp(row['firstRespondedAt']);
      final reason = row['reason'];
      if (receipt == null
          ? response != null || reason != 'legacy_receipt_unavailable'
          : response != null
          ? response.isBefore(receipt) || reason != null
          : reason != null && reason != 'first_response_unavailable') {
        throw const FormatException(
          'Invalid server support receipt provenance.',
        );
      }
      if (!deleted.contains(row['id'])) {
        receipts.add(row.cast<String, Object?>());
      }
    }
    return {
      'schemaVersion': 1,
      'source': 'server_voice_receipts',
      'definition': 'Authenticated read-only server receipt and first committed operator reply facts, not customer-read or notification delivery. Missing historical times remain unavailable.',
      'receipts': receipts,
    };
  }

  Future<void> deleteAccount() async {
    final account = store.account;
    final generation = store.syncGeneration;
    if (identity.account != account) {
      throw StateError(
        'Sign in to the account that owns this garden before deletion.',
      );
    }
    final token = await identity.accessToken();
    store.requireSyncSession(account, generation);
    final httpClient = client ?? http.Client();
    late http.Response response;
    try {
      response = await httpClient
          .delete(
            Uri.parse('${IdentityService.apiOrigin}/api/account'),
            headers: {
              'X-Bloomstep-Authorization': 'Bearer $token',
              'x-confirm-delete': 'delete-my-garden',
            },
          )
          .timeout(const Duration(seconds: 30));
    } finally {
      if (client == null) httpClient.close();
    }
    store.requireSyncSession(account, generation);
    if (response.statusCode != 204) {
      throw StateError(
        'Cloud deletion failed (HTTP ${response.statusCode}).${_apiError(response)} Local data has not been deleted.',
      );
    }
    await store.deleteLocalAccount();
    await identity.signOut();
  }
}
