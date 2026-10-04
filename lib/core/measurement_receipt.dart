import 'dart:convert';

class ExpiredMeasurementReceipt extends FormatException {
  const ExpiredMeasurementReceipt() : super('Measurement receipt expired.');
}

class MeasurementObservation {
  const MeasurementObservation._(this.id, this.name, this.at);
  final String id;
  final String name;
  final DateTime at;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'ts': at.toIso8601String(),
  };
}

/// Explicitly consented local observations, not authenticated attribution.
class MeasurementReceipt {
  MeasurementReceipt._(this.source, this.consentedAt, this.events);
  final String source;
  final DateTime consentedAt;
  final List<MeasurementObservation> events;
  static const maxBytes = 16384;
  static const lifetime = Duration(days: 7);
  static const _website = {
    'landing_view',
    'invite_link_open',
    'download_click',
  };
  static const _installer = {
    'installer_started',
    'install_completed',
    'first_launch',
    'signin_view',
  };
  static final _id = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final _utc = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
  );

  static MeasurementReceipt parse(String text, {DateTime? now}) {
    const invalid = FormatException(
      'Invalid, expired or unsupported measurement receipt. No data was imported.',
    );
    if (utf8.encode(text).length > maxBytes) throw invalid;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw invalid;
    }
    if (decoded is! Map<String, dynamic> ||
        !_keys(decoded, {'schemaVersion', 'source', 'consentedAt', 'events'}) ||
        decoded['schemaVersion'] is! int ||
        decoded['schemaVersion'] != 1 ||
        !['website', 'installer'].contains(decoded['source'])) {
      throw invalid;
    }
    final source = decoded['source'] as String;
    final consent = _date(decoded['consentedAt']);
    final clock = (now ?? DateTime.now()).toUtc();
    if (consent == null || consent.isAfter(clock)) {
      throw invalid;
    }
    if (!clock.isBefore(consent.add(lifetime))) {
      throw const ExpiredMeasurementReceipt();
    }
    final rows = decoded['events'];
    if (rows is! List || rows.isEmpty || rows.length > 32) throw invalid;
    final names = source == 'website' ? _website : _installer;
    final ids = <String>{};
    final seen = <String>{};
    final events = <MeasurementObservation>[];
    var previous = consent;
    for (final row in rows) {
      if (row is! Map<String, dynamic> ||
          !_keys(row, {'id', 'name', 'ts'}) ||
          row['id'] is! String ||
          !_id.hasMatch(row['id'] as String) ||
          !ids.add(row['id'] as String) ||
          !names.contains(row['name'])) {
        throw invalid;
      }
      final at = _date(row['ts']);
      if (at == null || at.isBefore(previous) || at.isAfter(clock)) {
        throw invalid;
      }
      final name = row['name'] as String;
      if (source == 'installer' &&
          (!seen.add(name) ||
              (events.isEmpty && name != 'installer_started') ||
              (name == 'first_launch' && !seen.contains('install_completed')) ||
              (name == 'signin_view' && !seen.contains('first_launch')))) {
        throw invalid;
      }
      if (source == 'website' && events.isEmpty && name != 'landing_view') {
        throw invalid;
      }
      events.add(MeasurementObservation._(row['id'] as String, name, at));
      previous = at;
    }
    return MeasurementReceipt._(source, consent, List.unmodifiable(events));
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'source': source,
    'consentedAt': consentedAt.toIso8601String(),
    'events': events.map((e) => e.toJson()).toList(),
  };

  void requireCurrent(DateTime now) => parse(jsonEncode(toJson()), now: now);

  static bool _keys(Map<String, dynamic> map, Set<String> keys) =>
      map.length == keys.length && map.keys.every(keys.contains);

  static DateTime? _date(Object? raw) {
    if (raw is! String || !_utc.hasMatch(raw)) return null;
    final date = DateTime.tryParse(raw);
    if (date == null ||
        date.toIso8601String().substring(0, 19) != raw.substring(0, 19)) {
      return null;
    }
    return date.toUtc();
  }
}
