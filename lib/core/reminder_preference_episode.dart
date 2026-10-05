class ReminderObservationConsent {
  const ReminderObservationConsent._(this.consentEpoch);
  final String consentEpoch;

  factory ReminderObservationConsent.explicitChoice(String epoch) {
    if (!ReminderPreferenceEpisode._uuid.hasMatch(epoch)) {
      throw const FormatException(
        'Invalid reminder observation consent epoch.',
      );
    }
    return ReminderObservationConsent._(epoch);
  }

  static ReminderObservationConsent? read(
    Map<String, Object?>? json, {
    required bool analyticsEnabled,
  }) {
    if (!analyticsEnabled || json == null) return null;
    if (json.length != 2 ||
        !json.keys.toSet().containsAll({'disclosureVersion', 'consentEpoch'}) ||
        json['disclosureVersion'] !=
            ReminderPreferenceEpisode.disclosureVersion ||
        json['consentEpoch'] is! String) {
      throw const FormatException(
        'Reminder observation consent has an unsupported disclosure or invalid state.',
      );
    }
    return ReminderObservationConsent.explicitChoice(
      json['consentEpoch'] as String,
    );
  }

  Map<String, Object?> toJson() => {
    'disclosureVersion': ReminderPreferenceEpisode.disclosureVersion,
    'consentEpoch': consentEpoch,
  };
}

class ReminderPreferenceEpisode {
  const ReminderPreferenceEpisode._({
    required this.consentEpoch,
    required this.cohortId,
    required this.startedAt,
    required this.lastObservedAt,
    this.disabledAt,
    this.followupAt,
  });

  static const disclosureVersion = 1;
  static const horizon = Duration(days: 30);
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  final String consentEpoch, cohortId;
  final DateTime startedAt, lastObservedAt;
  final DateTime? disabledAt, followupAt;

  factory ReminderPreferenceEpisode.start({
    required String consentEpoch,
    required String cohortId,
    required DateTime startedAt,
  }) => ReminderPreferenceEpisode.fromJson({
    'schemaVersion': 1,
    'disclosureVersion': disclosureVersion,
    'consentEpoch': consentEpoch,
    'cohortId': cohortId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'lastObservedAt': startedAt.toUtc().toIso8601String(),
    'disabledAt': null,
    'followupAt': null,
  });

  factory ReminderPreferenceEpisode.fromJson(Map<String, Object?> json) {
    const keys = {
      'schemaVersion',
      'disclosureVersion',
      'consentEpoch',
      'cohortId',
      'startedAt',
      'lastObservedAt',
      'disabledAt',
      'followupAt',
    };
    if (json.length != keys.length ||
        !json.keys.toSet().containsAll(keys) ||
        json['schemaVersion'] != 1 ||
        json['disclosureVersion'] != disclosureVersion ||
        json['consentEpoch'] is! String ||
        json['cohortId'] is! String ||
        !_uuid.hasMatch(json['consentEpoch'] as String) ||
        !_uuid.hasMatch(json['cohortId'] as String)) {
      throw const FormatException('Invalid reminder observation episode.');
    }
    DateTime? timestamp(Object? value, {bool nullable = false}) {
      if (value == null && nullable) return null;
      if (value is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:\d{3})?Z$')
              .hasMatch(value)) {
        throw const FormatException('Invalid reminder observation time.');
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null || parsed.toIso8601String() != value) {
        throw const FormatException('Invalid reminder observation time.');
      }
      return parsed;
    }

    final start = timestamp(json['startedAt'])!;
    final last = timestamp(json['lastObservedAt'])!;
    final disabled = timestamp(json['disabledAt'], nullable: true);
    final followed = timestamp(json['followupAt'], nullable: true);
    if (last.isBefore(start) ||
        disabled != null &&
            (disabled.isBefore(start) || disabled.isAfter(last)) ||
        followed != null &&
            (followed.isBefore(start.add(horizon)) || followed.isAfter(last)) ||
        followed != null && disabled != null && !disabled.isAfter(followed)) {
      throw const FormatException('Invalid reminder observation chronology.');
    }
    return ReminderPreferenceEpisode._(
      consentEpoch: json['consentEpoch'] as String,
      cohortId: json['cohortId'] as String,
      startedAt: start,
      lastObservedAt: last,
      disabledAt: disabled,
      followupAt: followed,
    );
  }

  void _requireClock(DateTime at) {
    if (at.toUtc().isBefore(lastObservedAt)) {
      throw StateError(
        'Reminder observation clock regressed; no outcome recorded.',
      );
    }
  }

  ReminderPreferenceEpisode? disable(DateTime at) {
    _requireClock(at);
    if (disabledAt != null) return null;
    return ReminderPreferenceEpisode.fromJson({
      ...toJson(),
      'lastObservedAt': at.toUtc().toIso8601String(),
      'disabledAt': at.toUtc().toIso8601String(),
    });
  }

  ReminderPreferenceEpisode? followup(DateTime at) {
    _requireClock(at);
    if (disabledAt != null ||
        followupAt != null ||
        at.toUtc().isBefore(startedAt.add(horizon))) {
      return null;
    }
    return ReminderPreferenceEpisode.fromJson({
      ...toJson(),
      'lastObservedAt': at.toUtc().toIso8601String(),
      'followupAt': at.toUtc().toIso8601String(),
    });
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'disclosureVersion': disclosureVersion,
    'consentEpoch': consentEpoch,
    'cohortId': cohortId,
    'startedAt': startedAt.toIso8601String(),
    'lastObservedAt': lastObservedAt.toIso8601String(),
    'disabledAt': disabledAt?.toIso8601String(),
    'followupAt': followupAt?.toIso8601String(),
  };
}
