import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/models.dart';
import 'package:bloomstep/core/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'real store graduation requires two fortnightly checks and practice',
    () async {
      final store = await GardenStore.open(':memory:', 'learning-test');
      addTearDown(store.close);
      final h = await store.plant(
        aspiration: 'Focus',
        anchor: 'coffee',
        behavior: 'write one word',
        celebration: 'smile',
        species: 'Fern',
      );
      for (var i = 1; i <= 28; i++) {
        await store.checkIn(h.id, CheckInResult.did, now: DateTime(2026, 9, i));
      }
      await store.reflect(h.id, [6, 6, 6, 6], now: DateTime(2026, 9, 14));
      expect((await store.habits()).single.status, 'active');
      await expectLater(
        store.reflect(h.id, [6, 6, 6, 6], now: DateTime(2026, 9, 15)),
        throwsStateError,
      );
      await store.reflect(h.id, [6, 6, 6, 6], now: DateTime(2026, 9, 28));
      expect((await store.habits()).single.status, 'graduated');
      expect((await store.habits()).single.stage, GrowthStage.bloom);
    },
  );
  test('reconnects stop after two per absence and explain when due', () {
    expect(reconnectDue(2, 0), isFalse);
    expect(reconnectDue(3, 0), isTrue);
    expect(reconnectDue(6, 1), isFalse);
    expect(reconnectDue(7, 1), isTrue);
    expect(reconnectDue(30, 2), isFalse);
  });
}
