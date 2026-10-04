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
    await store.mergeSync(
      (jsonDecode(response.body) as Map).cast<String, dynamic>(),
      account: account,
      generation: generation,
    );
    if (body != null) {
      await store.acknowledgeSync(
        body,
        account: account,
        generation: generation,
      );
    }
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
