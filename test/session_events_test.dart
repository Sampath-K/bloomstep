import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/services/session_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'restored entry is observed session activity, not a new sign-in or install',
    () async {
      final store = await GardenStore.open(':memory:', 'synthetic-session');
      addTearDown(store.close);
      await store.setSetting('analytics', 'true');
      await SessionEvents.entered(store, authenticatedNow: false);
      final events = (await store.export())['events'] as List;
      expect(
        events.where((e) => (e as Map)['name'] == 'session_started'),
        hasLength(1),
      );
      expect(
        events.any(
          (e) => [
            'signin_succeeded',
            'first_launch',
            'install_completed',
          ].contains((e as Map)['name']),
        ),
        isFalse,
      );
    },
  );
  test(
    'fresh verified sign-in is tracked only with existing account consent',
    () async {
      final store = await GardenStore.open(':memory:', 'synthetic-signin');
      addTearDown(store.close);
      await SessionEvents.entered(store, authenticatedNow: true);
      expect((await store.export())['events'], isEmpty);
      await store.setSetting('analytics', 'true');
      await SessionEvents.entered(store, authenticatedNow: true);
      final events = (await store.export())['events'] as List;
      expect(
        events.where((e) => (e as Map)['name'] == 'signin_succeeded'),
        hasLength(1),
      );
    },
  );
}
