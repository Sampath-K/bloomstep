import { z } from 'zod';
import { aggregateEvents } from './engagement.mjs';
import { dashboardSummaries, addDays } from './dashboards.mjs';
import { eventRegistry, registryVersion } from './event_registry.g.mjs';

const day = z.iso.date();
const count = z.number().int().min(50).nullable();
const fraction = z.number().min(0).max(1).nullable();
const definition = dashboardSummaries([], '2026-01-01', '2026-01-01', '2026-01-02');
const compatibility = aggregateEvents([], '2026-01-01', '2026-01-01');
const rateFields = { eligibleUsers: count, convertedUsers: count, rate: fraction, suppressed: z.boolean() };
const rate = z.strictObject(rateFields);
const retentionDay = z.strictObject({
  targetDay: day, matured: z.boolean(), eligibleUsers: count, practicingUsers: count,
  rate: fraction, suppressed: z.boolean(),
});
const stages = ['landing_view', 'download_click', 'install_completed', 'first_launch', 'signin_succeeded',
  'first_checkin', 'habit_graduated', 'share_initiated', 'invite_accepted'];
const dashboards = z.strictObject({
  registryVersion: z.literal(registryVersion), minimumCohort: z.literal(50),
  startDay: day, endDay: day, observedThrough: day,
  // Optional solely for already persisted pre-instrumentation snapshots.
  authentication: z.strictObject({
    stages: z.strictObject(Object.fromEntries(['session_entry', 'api_token'].map(stage => [
      stage, z.strictObject({ observedUsers: count, succeededUsers: count, failedUsers: count,
        failureKinds: z.strictObject(Object.fromEntries(
          ['timeout', 'network', 'validation', 'unavailable', 'unknown'].map(kind => [kind, count]))),
      }),
    ]))),
    allUserSigninSuccessRate: z.null(), preAuthFailures: z.null(), providerBreakdown: z.null(),
    definition: z.literal(definition.authentication.definition),
  }).optional(),
  funnel: z.strictObject({
    stages: z.strictObject(Object.fromEntries(stages.map(name => [name, z.strictObject({ users: count, suppressed: z.boolean() })]))),
    visitToDownload: rate, downloadToLaunch: rate, launchToSignin: rate, sameDayActivation: rate,
    breakdowns: z.array(z.union([
      z.strictObject({ dimension: z.literal('channel'), value: z.enum(['website', 'invite', 'store', 'direct', 'unknown', 'link', 'email']), ...rateFields }),
      z.strictObject({ dimension: z.literal('platform'), value: z.enum(['windows', 'macos', 'linux', 'android', 'ios', 'web']), ...rateFields }),
    ])).max(13),
    definition: z.literal(definition.funnel.definition),
  }),
  retention: z.strictObject({
    cohorts: z.array(z.strictObject({
      cohortDay: day, cohortUsers: count, suppressed: z.boolean(),
      d1: retentionDay, d7: retentionDay, d30: retentionDay,
    })).max(31),
    cohortStartDay: day, cohortEndDay: day, definition: z.literal(definition.retention.definition),
  }),
  outcomes: z.strictObject({
    daily: z.array(z.strictObject({
      day, suppressed: z.boolean(), scoreUsers: count, medianAutomaticity: z.number().min(1).max(7).nullable(),
      practicingUsers: count, graduatedUsers: count, graduationCount: count,
    })).length(1),
    definition: z.literal(definition.outcomes.definition),
  }),
  reminderHealth: z.strictObject({
    sentUsers: count, deliveredUsers: count, openedUsers: count, dismissedUsers: count,
    actionRate: rate, disableRate: rate, definition: z.literal(definition.reminderHealth.definition),
  }),
  appHealth: z.strictObject({
    observedSessionUsers: count, observedCrashUsers: count, crashFreeRate: z.null(),
    definition: z.literal(definition.appHealth.definition),
  }),
  experiment: z.strictObject({ enabled: z.literal(false), reason: z.literal(definition.experiment.reason) }),
});

export const dailySnapshotRecordSchema = z.strictObject({
  startDay: day, endDay: day, minimumCohort: z.literal(50),
  daily: z.array(z.strictObject({
    day, suppressed: z.boolean(), users: count,
    counts: z.strictObject(Object.fromEntries(Object.keys(eventRegistry).map(name => [
      name, name === 'auth_observation' ? count.optional() : count,
    ]))).nullable(),
  })).length(1),
  categories: z.strictObject({
    activationRetention: z.strictObject({ signins: count, recipesCreated: count, checkins: count, graduations: count, returningCheckinUsers: count }),
    reminderLearning: z.strictObject({ remindersSent: count, reflections: count, weeklyReflections: count }),
    voiceRatings: z.strictObject({ feedbackSubmitted: count, ratingPrompts: count, ratings: count }),
    sharingExperiment: z.strictObject({ sharesInitiated: count, experiments: z.null() }),
  }),
  limitations: z.array(z.enum(compatibility.limitations)).length(compatibility.limitations.length),
  dashboards,
}).superRefine((record, context) => {
  const date = record.startDay;
  if (record.endDay !== date || record.daily[0].day !== date || record.dashboards.startDay !== date ||
      record.dashboards.endDay !== date || record.dashboards.observedThrough !== addDays(date, 1) ||
      record.dashboards.outcomes.daily[0].day !== date ||
      record.dashboards.retention.cohortStartDay !== addDays(date, -30) || record.dashboards.retention.cohortEndDay !== date ||
      record.dashboards.retention.cohorts.some(cohort => cohort.cohortDay < addDays(date, -30) || cohort.cohortDay > date)) {
    context.addIssue({ code: 'custom', message: 'Snapshot record must describe exactly its completed UTC day.' });
  }
});

export const snapshotMetadataSchema = z.strictObject({
  day, generatedAt: z.iso.datetime(), registryVersion: z.literal(registryVersion),
  generation: z.string().uuid(), digest: z.string().regex(/^[a-f0-9]{64}$/),
});
