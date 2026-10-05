export function reminderPreferencePanels(data) {
  const value = data?.reminderPreferenceCohorts;
  const reasons = [null, 'cohort_below_50', 'contributors_below_50',
    'followup_unavailable', 'invalid_observations', 'conflicting_observations'];
  const count = input => input === null || Number.isInteger(input) && input >= 50 && input <= 200;
  if (value?.schemaVersion !== 1 || value.source !== 'observed_app_reminder_preference' ||
      value.minimumCohort !== 50 || value.horizonDays !== 30 ||
      value.originalGoalReason !== 'not_observable' || typeof value.definition !== 'string' ||
      ![value.startDay, value.endDay].every(day => typeof day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day)) ||
      typeof value.observedAt !== 'string' || !Number.isFinite(Date.parse(value.observedAt)) ||
      !reasons.includes(value.reason) ||
      ![value.matureAccounts, value.disabledAccounts, value.confirmedEnabledAccounts,
        value.unknownFollowupAccounts, value.immatureAccounts].every(count) ||
      (value.reason !== null ? value.observedDisableFraction !== null :
        value.matureAccounts === null || value.disabledAccounts === null ||
        value.confirmedEnabledAccounts === null ||
        typeof value.observedDisableFraction !== 'number' ||
        !Number.isFinite(value.observedDisableFraction) ||
        value.observedDisableFraction < 0 || value.observedDisableFraction > 1 ||
        value.disabledAccounts > value.matureAccounts ||
        value.disabledAccounts + value.confirmedEnabledAccounts !== value.matureAccounts ||
        value.observedDisableFraction !== value.disabledAccounts / value.matureAccounts ||
        value.unknownFollowupAccounts !== null)) {
    throw new Error('Invalid reminder preference cohort; no substitute coverage rendered.');
  }
  const shown = count => count === null ? 'Unavailable / suppressed' : String(count);
  return [{
    title: 'Observed app reminder preference — separate, narrower coverage',
    definition: `${value.startDay} through ${value.endDay}, completed UTC horizon dates; observed at ${value.observedAt}. ${value.definition}`,
    rows: [
      { label: 'Observed closed30-day disable fraction', value: value.reason
        ? `Unavailable (${value.reason}); no inferred non-disable outcome`
        : `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(value.observedDisableFraction * 100)}% (${shown(value.disabledAccounts)} / ${shown(value.matureAccounts)} owners); no original-goal pass/fail comparison` },
      { label: 'Mature observed owners', value: shown(value.matureAccounts) },
      { label: 'Explicit app disable owners by30-day deadline', value: shown(value.disabledAccounts) },
      { label: 'Confirmed same-episode app-preference followup owners', value: shown(value.confirmedEnabledAccounts) },
      { label: 'Unknown followup owners (never assumed enabled)', value: shown(value.unknownFollowupAccounts) },
      { label: 'Immature owners (not failures)', value: shown(value.immatureAccounts) },
      { label: 'Original notification disable<=10% goal', value: 'Unavailable (not_observable); OS/lifetime/all-user notification coverage is absent. This preference cohort does not replace it.' },
    ],
  }];
}
