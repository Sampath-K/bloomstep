import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/garden_store.dart';
import 'identity.dart';

class SyncService {
  SyncService(this.identity, this.store);
  final IdentityService identity;
  final GardenStore store;
  bool _running = false;

  Future<void> sync() async {
    if (_running) return;
    _running = true;
    try {
      final token = await identity.accessToken();
      final payload = await store.syncPayload();
      final tables = ['habits', 'checkins', 'reflections', 'voice', 'events'];
      for (final table in tables) {
        final records = payload[table] as List;
        final size = table == 'checkins' || table == 'events' ? 500 : 100;
        for (var start = 0; start < records.length; start += size) {
          final chunk = <String, Object?>{for (final t in tables) t: []};
          chunk[table] = records.sublist(
            start,
            (start + size).clamp(0, records.length),
          );
          await _request(token, chunk);
        }
      }
      await _request(token, null);
      await store.setSetting(
        'lastSync',
        DateTime.now().toUtc().toIso8601String(),
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _request(String token, Map<String, Object?>? body) async {
    final url = Uri.parse('${IdentityService.apiOrigin}/api/sync');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response = body == null
        ? await http
              .get(url, headers: headers)
              .timeout(const Duration(seconds: 30))
        : await http
              .post(url, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError(
        'Sync failed (HTTP ${response.statusCode}). Local changes remain on this device.',
      );
    }
    await store.mergeSync(
      (jsonDecode(response.body) as Map).cast<String, dynamic>(),
    );
  }

  Future<void> deleteAccount() async {
    final response = await http
        .delete(
          Uri.parse('${IdentityService.apiOrigin}/api/account'),
          headers: {
            'Authorization': 'Bearer ${await identity.accessToken()}',
            'x-confirm-delete': 'delete-my-garden',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 204) {
      throw StateError(
        'Cloud deletion failed (HTTP ${response.statusCode}). Local data has not been deleted.',
      );
    }
    await store.deleteLocalAccount();
    await identity.signOut();
  }
}
