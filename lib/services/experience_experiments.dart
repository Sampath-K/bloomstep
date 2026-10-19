import 'package:flutter/foundation.dart';

import '../core/experience_policy.dart';
import '../core/garden_store.dart';
import '../core/growthbook_experience_provider.dart';
export '../core/experience_policy.dart';

/// Vendor-neutral UI boundary. Adapters must preserve consent and render ordering.
abstract interface class ExperienceResolver {
  Listenable get changes;
  Duration get remainingEnrollment;
  Future<ExperienceAssignment> resolve(ExperienceSurface surface);
  Future<bool> rendered(ExperienceAssignment assignment);
  Future<bool> outcome(
    ExperienceAssignment assignment,
    ExperienceOutcome outcome,
  );
  Future<void> followup();
}

class ExperienceExperiments implements ExperienceResolver {
  ExperienceExperiments(
    this.store, {
    this.config = ExperienceConfig.off,
    ExperienceAssignmentProvider provider =
        const GrowthBookExperienceProvider(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    store.configureExperiences(config, provider);
  }
  final GardenStore store;
  final ExperienceConfig config;
  final DateTime Function() _clock;
  @override
  Listenable get changes => store.experienceChanges;
  @override
  Duration get remainingEnrollment => config.startAt == null
      ? Duration.zero
      : config.startAt!
            .add(ExperienceDefinition.enrollment)
            .difference(_clock().toUtc());

  @override
  Future<ExperienceAssignment> resolve(ExperienceSurface surface) =>
      store.resolveExperience(surface, config, _clock());
  @override
  Future<bool> rendered(ExperienceAssignment assignment) =>
      store.recordExperience(assignment, config, 'rendered', _clock());
  @override
  Future<bool> outcome(
    ExperienceAssignment assignment,
    ExperienceOutcome outcome,
  ) => store.recordExperience(assignment, config, switch (outcome) {
    ExperienceOutcome.taskCompleted => 'task_completed',
    ExperienceOutcome.error => 'error',
    ExperienceOutcome.burden => 'burden',
  }, _clock());
  @override
  Future<void> followup() => store.followupExperience(config, _clock());
}
