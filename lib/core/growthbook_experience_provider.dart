import 'package:growthbook_sdk_flutter/growthbook_sdk_flutter.dart';

import 'experience_policy.dart';

/// Local GrowthBook evaluation only. No CDN, tracking plugin, cache or account identity.
class GrowthBookExperienceProvider implements ExperienceAssignmentProvider {
  const GrowthBookExperienceProvider();
  @override
  String get id => 'growthbook_flutter_v1';

  @override
  ExperienceArm? evaluate(ExperienceConfig config, String subject) {
    if (!config.enabled || config.surface == null || subject.isEmpty) {
      return null;
    }
    final definition = ExperienceDefinition(config.surface!);
    final context = GBContext(
      enabled: true,
      attributes: {'id': subject},
      backgroundSync: false,
      remoteEval: false,
      trackingCallBack: (_) {},
    );
    final experiment = GBExperiment.fromJson({
      'key': definition.id,
      'variations': ['control', 'candidate'],
      'weights': [0.5, 0.5],
      'hashAttribute': 'id',
      'hashVersion': 2,
      'seed': config.key,
      'active': true,
      'coverage': 1.0,
      'disableStickyBucketing': true,
    });
    // The SDK callback is deliberately a no-op: evaluation is not exposure.
    final result = ExperimentEvaluator().evaluateExperiment(
      GBUtils.initializeEvalContext(context, null),
      experiment,
    );
    if (!result.inExperiment || result.hashUsed != true) return null;
    return switch (result.variationID) {
      0 => ExperienceArm.control,
      1 => ExperienceArm.candidate,
      _ => null,
    };
  }
}
