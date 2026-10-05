import 'package:bloomstep/core/reminder_preference_episode.dart';
import 'package:flutter_test/flutter_test.dart';

const epoch = '38b822ed-afde-4906-a754-e6be1be6a756';
const cohort = '564c5f5c-4d7d-4ea6-9f46-8ce5cb4d4ddb';

void main() {
  test('fresh versioned choice is necessary in addition to analytics; existing analytics alone never authorizes episodes', () {
    expect(
      ReminderObservationConsent.read(null, analyticsEnabled: true),
      isNull,
    );
    expect(
      ReminderObservationConsent.read(null, analyticsEnabled: false),
      isNull,
    );
    final choice = ReminderObservationConsent.explicitChoice(epoch);
    expect(choice.toJson(), {'disclosureVersion': 1, 'consentEpoch': epoch});
    expect(
      ReminderObservationConsent.read(choice.toJson(), analyticsEnabled: false),
      isNull,
    );
    expect(
      ReminderObservationConsent.read(
        choice.toJson(),
        analyticsEnabled: true,
      )!.consentEpoch,
      epoch,
    );
    for (final invalid in [
      {'disclosureVersion': 0, 'consentEpoch': epoch},
      {'disclosureVersion': 2, 'consentEpoch': epoch},
      {'disclosureVersion': 1, 'consentEpoch': 'an-email-not-epoch'},
      {'disclosureVersion': 1, 'consentEpoch': epoch, 'enabled': true},
    ]) {
      expect(
        () => ReminderObservationConsent.read(invalid, analyticsEnabled: true),
        throwsFormatException,
      );
    }
  });

  test('episode stores only versioned random linkage and time, with roundtrip provenance', () {
    final start = DateTime.utc(2026, 8, 1, 12);
    final episode = ReminderPreferenceEpisode.start(
      consentEpoch: epoch,
      cohortId: cohort,
      startedAt: start,
    );
    final raw = episode.toJson();
    expect(raw.keys.toSet(), {
      'schemaVersion',
      'disclosureVersion',
      'consentEpoch',
      'cohortId',
      'startedAt',
      'lastObservedAt',
      'disabledAt',
      'followupAt',
    });
    expect(ReminderPreferenceEpisode.fromJson(raw).toJson(), raw);
    expect(episode.followup(start.add(const Duration(days: 29))), isNull);
    final closed = episode.followup(start.add(const Duration(days: 30)))!;
    expect(closed.followupAt, start.add(const Duration(days: 30)));
    expect(closed.followup(start.add(const Duration(days: 31))), isNull);
  });

  test(
    'disabled is terminal and retries cannot invent a new time or followup',
    () {
      final start = DateTime.utc(2026, 8, 1);
      final episode = ReminderPreferenceEpisode.start(
        consentEpoch: epoch,
        cohortId: cohort,
        startedAt: start,
      );
      final disabled = episode.disable(start.add(const Duration(days: 2)))!;
      expect(disabled.disable(start.add(const Duration(days: 3))), isNull);
      expect(disabled.followup(start.add(const Duration(days: 31))), isNull);
      expect(
        ReminderPreferenceEpisode.fromJson(disabled.toJson()).disabledAt,
        disabled.disabledAt,
      );
    },
  );

  test('regressed clocks fail explicitly rather than inferred ordering', () {
    final start = DateTime.utc(2026, 8, 1);
    final episode = ReminderPreferenceEpisode.start(
      consentEpoch: epoch,
      cohortId: cohort,
      startedAt: start,
    );
    expect(
      () => episode.disable(start.subtract(const Duration(milliseconds: 1))),
      throwsStateError,
    );
    expect(
      () => episode.followup(start.subtract(const Duration(milliseconds: 1))),
      throwsStateError,
    );
    final closed = episode.followup(start.add(const Duration(days: 30)))!;
    expect(
      () => closed.disable(start.add(const Duration(days: 29))),
      throwsStateError,
    );
  });

  test('unknown schemas, malformed private extras and impossible historical state fail without a migration fallback', () {
    final start = DateTime.utc(2026, 8, 1);
    final raw = ReminderPreferenceEpisode.start(
      consentEpoch: epoch,
      cohortId: cohort,
      startedAt: start,
    ).toJson();
    for (final broken in [
      {...raw, 'schemaVersion': 2},
      {...raw, 'disclosureVersion': 0},
      {...raw, 'consentEpoch': 'an-account-or-email'},
      {...raw, 'cohortId': 'not-a-uuid'},
      {...raw, 'startedAt': '2026-02-30T12:00:00.000Z'},
      {...raw, 'startedAt': '2026-08-01T00:00:00+00:00'},
      {...raw, 'followupAt': '2026-08-02T00:00:00.000Z'},
      {...raw, 'disabledAt': '2026-07-31T00:00:00.000Z'},
      {...raw, 'lastObservedAt': '2026-07-31T00:00:00.000Z'},
      {...raw, 'habitText': 'Synthetic prohibited field'},
    ]) {
      expect(
        () => ReminderPreferenceEpisode.fromJson(broken),
        throwsFormatException,
      );
    }
  });

  test('confirmed followup does not prevent a later explicit disable but cannot justify earlier disabled chronology', () {
    final start = DateTime.utc(2026, 8, 1);
    final episode = ReminderPreferenceEpisode.start(
      consentEpoch: epoch,
      cohortId: cohort,
      startedAt: start,
    );
    final followed = episode.followup(start.add(const Duration(days: 30)))!;
    final disabled = followed.disable(start.add(const Duration(days: 31)))!;
    expect(disabled.followupAt, start.add(const Duration(days: 30)));
    expect(disabled.disabledAt, start.add(const Duration(days: 31)));
    expect(
      ReminderPreferenceEpisode.fromJson(disabled.toJson()).toJson(),
      disabled.toJson(),
    );
    final invalid = {
      ...disabled.toJson(),
      'disabledAt': start.add(const Duration(days: 29)).toIso8601String(),
    };
    expect(
      () => ReminderPreferenceEpisode.fromJson(invalid),
      throwsFormatException,
    );
  });
}
