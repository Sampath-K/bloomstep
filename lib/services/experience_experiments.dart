import '../core/experience_policy.dart';
import '../core/garden_store.dart';
export '../core/experience_policy.dart';

class ExperienceExperiments {
  ExperienceExperiments(
    this.store, {
    this.config = ExperienceConfig.off,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    store.configureExperiences(config);
  }
  final GardenStore store;
  final ExperienceConfig config;
  final DateTime Function() _clock;
  Duration get remainingEnrollment => config.startAt == null
      ? Duration.zero
      : config.startAt!
            .add(ExperienceDefinition.enrollment)
            .difference(_clock().toUtc());

  Future<ExperienceAssignment> resolve(ExperienceSurface surface) =>
      store.resolveExperience(surface, config, _clock());
  Future<bool> rendered(ExperienceAssignment assignment) =>
      store.recordExperience(assignment, config, 'rendered', _clock());
  Future<bool> outcome(
    ExperienceAssignment assignment,
    ExperienceOutcome outcome,
  ) => store.recordExperience(assignment, config, switch (outcome) {
    ExperienceOutcome.taskCompleted => 'task_completed',
    ExperienceOutcome.error => 'error',
    ExperienceOutcome.burden => 'burden',
  }, _clock());
  Future<void> followup() => store.followupExperience(config, _clock());
}
