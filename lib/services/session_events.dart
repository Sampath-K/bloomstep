import 'package:uuid/uuid.dart';

import '../core/garden_store.dart';
import '../core/models.dart';

class SessionEvents {
  static Future<void> entered(
    GardenStore store, {
    required bool authenticatedNow,
    String? sessionId,
  }) async {
    sessionId ??= const Uuid().v4();
    await store.track(
      'session_started',
      properties: {'sessionId': sessionId, 'platform': 'windows'},
    );
    if (authenticatedNow) {
      await store.track(
        'signin_succeeded',
        properties: {
          'sessionId': sessionId,
          'platform': 'windows',
          'localDay': localDate(DateTime.now()),
        },
      );
    }
  }
}
