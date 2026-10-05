import 'dart:convert';

import 'package:bloomstep/core/garden_store.dart';
import 'package:bloomstep/core/event_registry.g.dart' as registry;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<List<Map>> observations(GardenStore store) async =>
    ((await store.export())['events'] as List)
        .cast<Map>()
        .where(
          (row) => (row['name'] as String).startsWith('reminder_preference_'),
        )
        .toList();
Map props(Map row) => jsonDecode(row['properties'] as String) as Map;

void main() {
  test('legacy persisted analytics true and reminders true never acquire new consent or episode on reopen', () async {
    final path = 'reminder-legacy-${DateTime.now().microsecondsSinceEpoch}.db';
    var store = await GardenStore.open(path, 'synthetic-legacy-consent');
    try {
      await store.setSetting('analytics', 'true');
      await store.setSetting('reminders', 'true');
      await store.close();
      store = await GardenStore.open(path, 'synthetic-legacy-consent');
      expect(await store.reminderObservationOptedIn(), isFalse);
      final at = DateTime.utc(2026, 8, 1);
      await store.saveReminderPreference(true, explicitChoice: false, now: at);
      await store.observeReminderPreferenceFollowup(
        now: at.add(const Duration(days: 31)),
      );
      expect(await observations(store), isEmpty);
      expect(await store.setting('reminderObservationConsent'), isNull);
      expect(await store.setting('reminderObservationEpisode'), isNull);
      await store.setReminderObservationConsent(true);
      await store.observeReminderPreferenceFollowup(
        now: at.add(const Duration(days: 32)),
      );
      expect(await observations(store), isEmpty);
      expect(await store.setting('reminderObservationEpisode'), isNull);
    } finally {
      await store.close();
      await databaseFactoryFfi.deleteDatabase(path);
    }
  });
  test('disk reopen preserves fresh epoch and original episode timestamps without another enrollment', () async {
    final path =
        'reminder-observation-${DateTime.now().microsecondsSinceEpoch}.db';
    var store = await GardenStore.open(path, 'synthetic-persisted');
    try {
      final at = DateTime.utc(2026, 8, 1, 12, 0, 0, 0, 123);
      await store.setSetting('analytics', 'true');
      await store.setReminderObservationConsent(true);
      await store.saveReminderPreference(true, explicitChoice: true, now: at);
      final before = (await observations(store)).single;
      await store.close();
      store = await GardenStore.open(path, 'synthetic-persisted');
      await store.saveReminderPreference(
        true,
        explicitChoice: false,
        now: at.add(const Duration(days: 1)),
      );
      await store.observeReminderPreferenceFollowup(
        now: at.add(const Duration(days: 30)),
      );
      final after = await observations(store);
      expect(after, hasLength(2));
      expect(after.first, before);
      expect(props(after.last)['cohortId'], props(before)['cohortId']);
      expect(props(after.last)['consentEpoch'], props(before)['consentEpoch']);
      expect(
        after.last['ts'],
        at.add(const Duration(days: 30)).toIso8601String(),
      );
    } finally {
      await store.close();
      await databaseFactoryFfi.deleteDatabase(path);
    }
  });
  test('stale epoch and unsupported disclosure fail explicitly without changing preference or adding outcome', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-invalid-state');
    addTearDown(store.close);
    final at = DateTime.utc(2026, 8, 1);
    await store.setSetting('analytics', 'true');
    await store.setReminderObservationConsent(true);
    await store.saveReminderPreference(true, explicitChoice: true, now: at);
    await store.setSetting(
      'reminderObservationConsent',
      jsonEncode({
        'disclosureVersion': 1,
        'consentEpoch': '6ed07684-9482-4d6f-a574-c3482c7b3db6',
      }),
    );
    await expectLater(
      store.saveReminderPreference(
        false,
        explicitChoice: true,
        now: at.add(const Duration(days: 1)),
      ),
      throwsStateError,
    );
    expect(await store.setting('reminders'), 'true');
    expect(await observations(store), hasLength(1));
    await store.setSetting(
      'reminderObservationConsent',
      jsonEncode({
        'disclosureVersion': 2,
        'consentEpoch': '6ed07684-9482-4d6f-a574-c3482c7b3db6',
      }),
    );
    await expectLater(
      store.observeReminderPreferenceFollowup(
        now: at.add(const Duration(days: 31)),
      ),
      throwsFormatException,
    );
    await store.setReminderObservationConsent(false);
    expect(await observations(store), isEmpty);
    expect(await store.reminderObservationOptedIn(), isFalse);
  });
  test('generated native reminder schema matches required Windows disclosure fields', () {
    const properties = <String, Object?>{
      'disclosureVersion': 1,
      'cohortId': '73df8338-cd80-4f64-8196-98a24e5d34df',
      'consentEpoch': '6ed07684-9482-4d6f-a574-c3482c7b3db6',
      'platform': 'windows',
      'localDay': '2026-08-01',
    };
    for (final name in [
      'reminder_preference_started',
      'reminder_preference_disabled',
      'reminder_preference_followup',
    ]) {
      expect(registry.isValidEventProperties(name, properties), isTrue);
      expect(
        registry.isValidEventProperties(name, {
          ...properties,
          'platform': 'web',
        }),
        isFalse,
      );
      for (final key in properties.keys) {
        expect(
          registry.isValidEventProperties(name, {...properties}..remove(key)),
          isFalse,
        );
      }
    }
  });
  test('account changes roll back queued consent and preference transactions without cross-owner collection', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-owner-a');
    addTearDown(store.close);
    await store.setSetting('analytics', 'true');
    final consentWrite = store.setReminderObservationConsent(true);
    final rejectedConsent = expectLater(consentWrite, throwsStateError);
    await store.switchAccount('synthetic-owner-b');
    await rejectedConsent;
    expect(await store.reminderObservationOptedIn(), isFalse);
    await store.switchAccount('synthetic-owner-a');
    expect(await store.reminderObservationOptedIn(), isFalse);
    await store.setReminderObservationConsent(true);
    final preferenceWrite = store.saveReminderPreference(
      true,
      explicitChoice: true,
      now: DateTime.utc(2026, 8, 1),
    );
    final rejectedPreference = expectLater(preferenceWrite, throwsStateError);
    await store.switchAccount('synthetic-owner-b');
    await rejectedPreference;
    expect(await store.setting('reminders'), isNull);
    expect(await observations(store), isEmpty);
    await store.switchAccount('synthetic-owner-a');
    expect(await store.setting('reminders'), isNull);
    expect(await observations(store), isEmpty);
  });
  test('revoked pending facts cannot be restored by acknowledgments and unrelated product events survive', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-ack-race');
    addTearDown(store.close);
    await store.setSetting('analytics', 'true');
    await store.setReminderObservationConsent(true);
    await store.saveReminderPreference(
      true,
      explicitChoice: true,
      now: DateTime.utc(2026, 8, 1),
    );
    final sent = await store.syncPayload();
    await store.setReminderObservationConsent(false);
    await store.acknowledgeSync(sent);
    expect(await observations(store), isEmpty);
    expect(await store.setting('reminderObservationEpisode'), isNull);
    expect(
      ((await store.export())['events'] as List).where(
        (row) => (row as Map)['name'] == 'analytics_consent',
      ),
      hasLength(1),
    );
    expect((await store.syncPayload())['events'], isEmpty);
  });
  test('generic tracking cannot bypass the fresh choice or manufacture an episode outcome', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-generic-track');
    addTearDown(store.close);
    await store.setSetting('analytics', 'true');
    const properties = <String, Object?>{
      'disclosureVersion': 1,
      'cohortId': '73df8338-cd80-4f64-8196-98a24e5d34df',
      'consentEpoch': '6ed07684-9482-4d6f-a574-c3482c7b3db6',
      'platform': 'windows',
      'localDay': '2026-08-01',
    };
    for (final consent in [false, true]) {
      if (consent) await store.setReminderObservationConsent(true);
      await expectLater(
        store.track('reminder_preference_started', properties: properties),
        throwsStateError,
      );
      expect(await observations(store), isEmpty);
    }
  });
  test('old analytics consent never authorizes added collection or retrospective opt-in', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-old-consent');
    addTearDown(store.close);
    final at = DateTime.utc(2026, 8, 1);
    await store.setSetting('analytics', 'true');
    await store.saveReminderPreference(true, explicitChoice: true, now: at);
    expect(await observations(store), isEmpty);
    await store.setReminderObservationConsent(true);
    await store.observeReminderPreferenceFollowup(
      now: at.add(const Duration(days: 31)),
    );
    expect(await observations(store), isEmpty);
    await store.saveReminderPreference(
      false,
      explicitChoice: true,
      now: at.add(const Duration(days: 32)),
    );
    await store.saveReminderPreference(
      true,
      explicitChoice: true,
      now: at.add(const Duration(days: 33)),
    );
    expect(
      (await observations(store)).single['name'],
      'reminder_preference_started',
    );
  });
  test('fresh choice requires analytics; restore, repeat and disposal never enroll or disable', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-transitions');
    addTearDown(store.close);
    await expectLater(
      store.setReminderObservationConsent(true),
      throwsStateError,
    );
    await store.setSetting('analytics', 'true');
    await store.setReminderObservationConsent(true);
    final at = DateTime.utc(2026, 8, 1);
    await store.saveReminderPreference(true, explicitChoice: false, now: at);
    expect(await observations(store), isEmpty);
    await store.saveReminderPreference(false, explicitChoice: false, now: at);
    await store.saveReminderPreference(true, explicitChoice: true, now: at);
    await store.saveReminderPreference(
      true,
      explicitChoice: true,
      now: at.add(const Duration(hours: 1)),
    );
    await store.saveReminderPreference(
      false,
      explicitChoice: false,
      now: at.add(const Duration(days: 1)),
    );
    await store.observeReminderPreferenceFollowup(
      now: at.add(const Duration(days: 31)),
    );
    expect((await observations(store)).map((row) => row['name']), [
      'reminder_preference_started',
    ]);
  });
  test('actual disable links once; exact30-day followup links once without clock invention', () async {
    for (final disable in [true, false]) {
      final store = await GardenStore.open(
        ':memory:',
        'synthetic-closure-$disable',
      );
      try {
        await store.setSetting('analytics', 'true');
        await store.setReminderObservationConsent(true);
        final at = DateTime.utc(2026, 8, 1, 12);
        await store.saveReminderPreference(true, explicitChoice: true, now: at);
        await expectLater(
          store.observeReminderPreferenceFollowup(
            now: at.subtract(const Duration(microseconds: 1)),
          ),
          throwsStateError,
        );
        if (disable) {
          await store.saveReminderPreference(
            false,
            explicitChoice: true,
            now: at.add(const Duration(days: 2)),
          );
          await store.saveReminderPreference(
            false,
            explicitChoice: true,
            now: at.add(const Duration(days: 3)),
          );
        } else {
          await store.observeReminderPreferenceFollowup(
            now: at
                .add(const Duration(days: 30))
                .subtract(const Duration(microseconds: 1)),
          );
        }
        await store.observeReminderPreferenceFollowup(
          now: at.add(const Duration(days: 30)),
        );
        await store.observeReminderPreferenceFollowup(
          now: at.add(const Duration(days: 31)),
        );
        final rows = await observations(store);
        expect(rows, hasLength(2));
        expect(
          rows.last['name'],
          disable
              ? 'reminder_preference_disabled'
              : 'reminder_preference_followup',
        );
        expect(props(rows.first)['cohortId'], props(rows.last)['cohortId']);
        expect(
          props(rows.first)['consentEpoch'],
          props(rows.last)['consentEpoch'],
        );
        expect(props(rows.first)['disclosureVersion'], 1);
        expect(rows.first['ts'], at.toIso8601String());
        expect((await store.syncPayload())['settings'], isEmpty);
      } finally {
        await store.close();
      }
    }
  });
  test('revocation purges state and prevents old epoch binding, analytics off and account erase purge added facts', () async {
    final store = await GardenStore.open(':memory:', 'synthetic-purge');
    addTearDown(store.close);
    final at = DateTime.utc(2026, 8, 1);
    await store.setSetting('analytics', 'true');
    await store.setReminderObservationConsent(true);
    await store.saveReminderPreference(true, explicitChoice: true, now: at);
    final epoch = props((await observations(store)).single)['consentEpoch'];
    await store.setReminderObservationConsent(false);
    expect(await observations(store), isEmpty);
    expect(await store.reminderObservationOptedIn(), isFalse);
    await store.setReminderObservationConsent(true);
    await store.observeReminderPreferenceFollowup(
      now: at.add(const Duration(days: 31)),
    );
    expect(await observations(store), isEmpty);
    await store.saveReminderPreference(
      false,
      explicitChoice: true,
      now: at.add(const Duration(days: 32)),
    );
    await store.saveReminderPreference(
      true,
      explicitChoice: true,
      now: at.add(const Duration(days: 33)),
    );
    expect(
      props((await observations(store)).single)['consentEpoch'],
      isNot(epoch),
    );
    await store.setSetting('analytics', 'false');
    expect(await store.reminderObservationOptedIn(), isFalse);
    expect(await observations(store), isEmpty);
    expect(
      (await store.export())['settings'],
      isNot(contains(containsPair('key', 'reminderObservationConsent'))),
    );
    await store.deleteLocalAccount();
    expect(await store.setting('reminderObservationEpisode'), isNull);
  });
}
