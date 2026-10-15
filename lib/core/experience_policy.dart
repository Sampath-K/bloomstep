import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'experience_policy.g.dart';
export 'experience_policy.g.dart' show experiencePolicyHash;

enum ExperienceSurface { invitationHeading, gardenPrompt }

enum ExperienceArm { control, candidate }

enum ExperienceOutcome { taskCompleted, error, burden }

final _policy = jsonDecode(experiencePolicyJson) as Map<String, dynamic>;

class ExperienceDefinition {
  ExperienceDefinition(this.surface);
  final ExperienceSurface surface;
  Map<String, dynamic> get _row => (_policy['catalog'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((row) => row['surface'] == surface.name);
  String get id => _row['id'] as String;
  String copy(ExperienceArm arm) => _row[arm.name] as String;
  static const followup = Duration(days: 7);
  static const enrollment = Duration(days: 28);
  static const taskWindow = Duration(hours: 24);
}

class ExperienceConfig {
  const ExperienceConfig._(
    this.surface,
    this.startAt,
    this.version,
    this.enabled,
  );
  static const off = ExperienceConfig._(null, null, 0, false);
  final ExperienceSurface? surface;
  final DateTime? startAt;
  final int version;
  final bool enabled;

  // A config flag cannot substitute for reviewed evidence or authorize rollout.
  static const reviewedConfigChecksum = '';

  @visibleForTesting
  factory ExperienceConfig.synthetic(
    ExperienceSurface surface, {
    required DateTime startAt,
    int version = 1,
  }) {
    if (!const bool.fromEnvironment('BLOOMSTEP_TEST_BUILD')) {
      throw StateError('Synthetic experience config requires a test build.');
    }
    if (version < 1 || !startAt.isUtc) {
      throw const FormatException('Invalid experience configuration.');
    }
    return ExperienceConfig._(surface, startAt, version, true);
  }

  factory ExperienceConfig.parse(
    Map<String, dynamic> json, {
    required DateTime now,
  }) {
    const keys = {
      'schemaVersion',
      'policyHash',
      'version',
      'surface',
      'startAt',
      'endAt',
      'enabled',
      'checksum',
    };
    if (json.length != keys.length ||
        !json.keys.toSet().containsAll(keys) ||
        json['schemaVersion'] != 1 ||
        json['policyHash'] != experiencePolicyHash ||
        json['version'] is! int ||
        (json['version'] as int) < 1 ||
        json['enabled'] is! bool ||
        !ExperienceSurface.values.any((s) => s.name == json['surface'])) {
      throw const FormatException(
        'Experience config is outside the reviewed policy.',
      );
    }
    final ordered = Map<String, dynamic>.fromEntries(
      json.entries.where((e) => e.key != 'checksum').toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
    final hash = sha256.convert(utf8.encode(jsonEncode(ordered))).toString();
    final start = DateTime.tryParse('${json['startAt']}');
    final end = DateTime.tryParse('${json['endAt']}');
    if (hash != json['checksum'] ||
        start == null ||
        end == null ||
        !start.isUtc ||
        !end.isUtc ||
        start.toIso8601String() != json['startAt'] ||
        end.toIso8601String() != json['endAt'] ||
        end.difference(start) != ExperienceDefinition.enrollment ||
        now.toUtc().isBefore(start) ||
        !now.toUtc().isBefore(end) ||
        json['enabled'] == true &&
            (reviewedConfigChecksum.isEmpty ||
                hash != reviewedConfigChecksum)) {
      throw const FormatException(
        'Experience config is expired, invalid or not source-approved.',
      );
    }
    return ExperienceConfig._(
      ExperienceSurface.values.singleWhere((s) => s.name == json['surface']),
      start,
      json['version'] as int,
      json['enabled'] as bool,
    );
  }

  bool activeAt(DateTime now) =>
      enabled &&
      startAt != null &&
      !now.toUtc().isBefore(startAt!) &&
      now.toUtc().isBefore(startAt!.add(ExperienceDefinition.enrollment));
  String get key =>
      '${surface?.name}:$version:${startAt?.toIso8601String()}:$experiencePolicyHash';
}

class ExperienceAssignment {
  const ExperienceAssignment({
    required this.surface,
    required this.arm,
    required this.active,
    this.cohortId,
    this.consentEpoch,
    this.owner,
    this.generation,
    this.consentGeneration,
    this.configKey,
  });
  factory ExperienceAssignment.control(ExperienceSurface surface) =>
      ExperienceAssignment(
        surface: surface,
        arm: ExperienceArm.control,
        active: false,
      );
  final ExperienceSurface surface;
  final ExperienceArm arm;
  final bool active;
  final String? cohortId, consentEpoch, owner, configKey;
  final int? generation, consentGeneration;
  String get copy => ExperienceDefinition(surface).copy(arm);
  bool get isControl => arm == ExperienceArm.control;
}
