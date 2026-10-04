import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/garden_store.dart';
import '../core/rules.dart';

class RemoteConfig {
  const RemoteConfig(this.version, this.enabled, this.treatmentPercent);
  final int version, treatmentPercent;
  final bool enabled;
  static const defaults = RemoteConfig(1, false, 25);
  static const control = 'A tiny step is enough';
  static const treatment = 'Your next tiny step is here';

  static RemoteConfig parse(Map<String, dynamic> json) {
    final experiment = json['experiment'];
    final version = json['version'];
    if (json['schemaVersion'] != 1 ||
        version is! int ||
        version < 1 ||
        experiment is! Map ||
        experiment['id'] != 'gentle-reminder-copy-v1' ||
        experiment['enabled'] is! bool ||
        experiment['treatmentPercent'] is! int ||
        experiment['treatmentPercent'] < 0 ||
        experiment['treatmentPercent'] > 50 ||
        experiment['control'] != control ||
        experiment['treatment'] != treatment) {
      throw const FormatException(
        'Remote config is invalid or outside reviewed limits.',
      );
    }
    return RemoteConfig(
      version,
      experiment['enabled'] as bool,
      experiment['treatmentPercent'] as int,
    );
  }

  String title(String account) =>
      enabled && experimentBucket(account) < treatmentPercent
      ? treatment
      : control;

  static Future<RemoteConfig> fetch(GardenStore store) async {
    final response = await http
        .get(
          Uri.parse(
            'https://brave-plant-02c10e800.5.azurestaticapps.net/config.json',
          ),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 || response.bodyBytes.length > 8192) {
      throw StateError('Remote config download failed.');
    }
    final config = parse(
      (jsonDecode(response.body) as Map).cast<String, dynamic>(),
    );
    await store.setSetting('remoteConfig', response.body);
    await store.setSetting(
      'remoteConfigAt',
      DateTime.now().toUtc().toIso8601String(),
    );
    return config;
  }
}
