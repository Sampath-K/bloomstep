import { z } from 'zod';
import { addDays, normalizedEvents, effectiveCheckins, timestampKey } from './dashboards.mjs';

const coverage = 'Observed opt-in, self-selected account-linked events only; no all-user census or complete broker/installer attribution. Historical first_checkin defines activation even if later undone. Missing required dates/IDs are excluded, not inferred. Both denominator and contributing numerator require 50 users. Bounded scans fail closed, never publish partial counts.';

/**
 * @param {{userId:string, record:unknown}[]} rows
 * @param {string} startDay @param {string} endDay @param {string} observedThrough
 */
export function goalMetrics(rows, startDay, endDay, observedThrough) {
  if (![startDay, endDay, observedThrough].every(day => z.iso.date().safeParse(day).success) ||
      startDay > endDay || endDay > addDays(startDay, 29)) throw new Error('Invalid goal metric window.');
  if (endDay >= observedThrough) throw new Error('Goal metrics require completed UTC days.');
  const events = normalizedEvents(rows);
  const practice = effectiveCheckins(events).filter(row => row.record.properties?.habitId && row.record.properties?.localDay);
  const window = events.filter(row => row.record.ts.slice(0, 10) >= startDay && row.record.ts.slice(0, 10) <= endDay);
  /** @type {Map<string,string>} */
  const activation = new Map();
  for (const row of events) {
    const day = row.record.properties?.localDay;
    const previous = activation.get(row.userId);
    if (row.record.name === 'first_checkin' && ['did', 'didMore'].includes(String(row.record.properties?.result)) &&
        typeof day === 'string' && row.record.properties?.habitId &&
        (!previous || day < previous)) activation.set(row.userId, day);
  }
  /** @param {number} horizon */
  const matured = horizon => new Map([...activation].filter(([, day]) =>
    addDays(day, horizon) >= startDay && addDays(day, horizon) <= endDay));
  /**
   * @param {string} id @param {string} label @param {number|null} target
   * @param {'at_least'|'at_most'|'track'} comparison @param {'fraction'|'per_user'|'hours'|'business_days'} unit
   * @param {Set<string>} eligible @param {Map<string,number>} contributions @param {string} definition
   */
  const measured = (id, label, target, comparison, unit, eligible, contributions, definition) => {
    const contributors = [...contributions].filter(([user, value]) => eligible.has(user) && value > 0);
    const numerator = contributors.reduce((total, [, value]) => total + value, 0);
    const reason = eligible.size < 50 ? 'cohort_below_50' : contributors.length < 50 ? 'contributors_below_50' : null;
    return { id, label, target, comparison, unit, value: reason ? null : numerator / eligible.size,
      numerator: contributors.length < 50 ? null : numerator, denominator: eligible.size < 50 ? null : eligible.size,
      reason, definition };
  };
  /** @param {string} id @param {string} label @param {number} target @param {'fraction'|'per_user'|'hours'|'business_days'} unit @param {string} definition */
  const unavailable = (id, label, target, unit, definition) => ({
    ...measured(id, label, target, id === 'invites_30' || id === 'crash_free' ? 'at_least' : 'at_most',
      unit, new Set(), new Map(), definition),
    reason: 'not_observable',
  });
  const launches = window.filter(row => row.record.name === 'first_launch');
  const signed = window.filter(row => row.record.name === 'signin_succeeded');
  const launchUsers = new Set(launches.map(row => row.userId));
  const converted = new Map(signed.filter(row => launches.some(first => first.userId === row.userId &&
    timestampKey(first.record.ts) <= timestampKey(row.record.ts))).map(row => [row.userId, 1]));
  const day0 = new Map(events.filter(row => row.record.name === 'first_checkin' &&
    ['did', 'didMore'].includes(String(row.record.properties?.result)) && row.record.properties?.habitId &&
    row.record.properties?.localDay && signed.some(first => first.userId === row.userId &&
      first.record.properties?.localDay === row.record.properties?.localDay &&
      timestampKey(first.record.ts) <= timestampKey(row.record.ts))).map(row => [row.userId, 1]));
  const goals = [
    measured('launch_signin', 'First launch to signed in', .85, 'at_least', 'fraction', launchUsers, converted,
      'Distinct observed first-launch accounts with a subsequent sign-in in the selected UTC window; not an attempt-success rate.'),
    measured('day0', 'Signed in to first check-in (day0)', .60, 'at_least', 'fraction', new Set(signed.map(row => row.userId)), day0,
      'Sign-in accounts observed in the selected UTC window with an ordered positive first_checkin on the same explicit localDay, including conversion across UTC midnight; no UTC-date fallback.'),
  ];
  for (const [horizon, id, target] of /** @type {[number,string,number][]} */ ([[7, 'd7', .40], [30, 'd30', .25]])) {
    const cohort = matured(horizon);
    const qualifying = new Map();
    for (const [user, day] of cohort) {
      const entries = practice.filter(row => row.userId === user && row.record.properties.localDay >= addDays(day, horizon === 7 ? 1 : 23) &&
        row.record.properties.localDay <= addDays(day, horizon));
      const count = horizon === 7 ? entries.length : new Set(entries.map(row => row.record.properties.localDay)).size;
      if (count >= (horizon === 7 ? 3 : 4)) qualifying.set(user, 1);
    }
    goals.push(measured(id, horizon === 7 ? 'D7: at least3 check-ins in days1-7' : 'D30: practice on at least4 days23-30',
      target, 'at_least', 'fraction', new Set(cohort.keys()), qualifying,
      `Activated cohorts whose day+${horizon} closes in the selected UTC window. Latest effective positive habit/local-day results; ${horizon === 7 ? 'three distinct habit/day check-ins, not exact day7 or three event retries' : 'four distinct practice dates of eight, not four habits on one date or exact day30'}.`));
  }
  for (const horizon of [30, 60, 90]) {
    const cohort = matured(horizon);
    const graduated = new Map();
    for (const [user, day] of cohort) {
      const ids = new Set(events.filter(row => row.userId === user && row.record.name === 'habit_graduated' &&
        row.record.properties?.habitId && typeof row.record.properties?.localDay === 'string' &&
        row.record.properties.localDay >= day && row.record.properties.localDay <= addDays(day, horizon))
        .map(row => row.record.properties?.habitId));
      if (ids.size) graduated.set(user, ids.size);
    }
    goals.push(measured(`north_star_${horizon}`, `Graduated habits per activated user at${horizon} days`, null, 'track', 'per_user',
      new Set(cohort.keys()), graduated, `Activated cohorts whose day+${horizon} closes in the selected window; distinct account/habit graduation IDs from activation through day+${horizon}, inclusive. No numeric north-star target was specified.`));
    if (horizon === 90) goals.push(measured('graduated_d90', 'At least1 graduated habit by day90', .15, 'at_least', 'fraction',
      new Set(cohort.keys()), new Map([...graduated.keys()].map(user => [user, 1])), 'Same mature90-day activated cohort; each observed graduating account counts once.'));
  }
  goals.push(
    unavailable('notification_disable_30', 'Notification disable rate (30 days)', .10, 'fraction', 'A bounded first-observed reminder request is not lifetime notification enablement. Requires an explicit consented cohort-start observation and30-day follow-up; the legacy selected-window disable proxy is not substituted.'),
    unavailable('invites_30', 'Invites per activated user (30 days)', .3, 'per_user', 'Share initiation is not verified invitation delivery. No delivery census or K-factor is inferred.'),
    unavailable('feedback_response', 'Feedback first response', 2, 'business_days', 'Requires server receipt/first-response timestamps plus an approved business timezone/holiday calendar; private status or client timestamps are not an SLA.'),
    unavailable('low_rating_response', 'First response to ratings of3 stars or less', 48, 'hours', 'Requires server receipt and first-response timestamps for private low ratings; no response-time median or compliance rate is inferred.'),
    unavailable('crash_free', 'Crash-free sessions', .995, 'fraction', 'Observed Dart errors may be nonfatal; complete session/native fatal census is absent. Unclean exits are not automatically crashes.'),
  );
  return { schemaVersion: 1, source: 'on_demand_target_aligned', startDay, endDay, observedThrough,
    minimumCohort: 50, coverage, goals };
}
