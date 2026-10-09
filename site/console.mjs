import { loadOperatorAuth, operatorRequest } from './operator-auth.mjs';
import { reminderPreferencePanels } from './reminder-panels.mjs';
import { websitePanels } from './website-panels.mjs';
import { loadAarrr } from './aarrr-panels.mjs';
const groups = [
  ['activationRetention', 'Activation / returning activity', [
    ['signins', 'Sign-ins'], ['recipesCreated', 'Recipes created'],
    ['checkins', 'Check-in events'], ['graduations', 'Graduations'],
    ['returningCheckinUsers', 'Users checking in on two or more UTC days'],
  ]],
  ['reminderLearning', 'Reminders / learning', [
    ['remindersSent', 'Reminder requests'], ['reflections', 'Naturalness checks'],
    ['weeklyReflections', 'Weekly reflections'],
  ]],
  ['voiceRatings', 'Feedback / ratings', [
    ['feedbackSubmitted', 'Feedback submissions'], ['ratingPrompts', 'Rating prompts'],
    ['ratings', 'Rating outcomes'],
  ]],
  ['sharingExperiment', 'Sharing / experiment', [
    ['sharesInitiated', 'Shares initiated'], ['experiments', 'Experiment outcomes'],
  ]],
];
const statuses = ['received', 'under review', 'planned', 'in progress', 'shipped', 'not planned'];

export function approvedConnection(value, token, siteOrigin) {
  const origin = new URL(value);
  if (origin.protocol !== 'https:' || origin.origin !== siteOrigin || origin.username ||
      origin.password || origin.pathname !== '/' || origin.search || origin.hash) {
    throw new Error('Use this deployed HTTPS site only. Tokens are never sent to another origin.');
  }
  if (!/^[\w-]+\.[\w-]+\.[\w-]+$/.test(token.trim())) {
    throw new Error('A short-lived signed API token with the product-team role is required.');
  }
  return { origin: origin.origin, token: token.trim() };
}

export function formatMetric(value) {
  if (value === null) return 'Unavailable / suppressed';
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw new Error('Invalid aggregate value; no default counts were substituted.');
  }
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(value);
}

export function tokenHeaders(token) {
  return { 'X-Bloomstep-Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' };
}

export function metricPanels(data) {
  if (!data || !Number.isInteger(data.minimumCohort) || !Array.isArray(data.daily) ||
      !Array.isArray(data.limitations)) throw new Error('Incomplete aggregate response.');
  return groups.map(([key, title, fields]) => {
    const category = data.categories?.[key];
    if (!category) throw new Error('Missing registered measurement category.');
    return { title, rows: fields.map(([field, label]) => ({ label, value: formatMetric(category[field]) })) };
  });
}

export function dashboardPanels(data) {
  const dashboards = data?.dashboards;
  if (!dashboards || dashboards.registryVersion !== 1 ||
      dashboards.minimumCohort !== 50 || !dashboards.funnel?.stages ||
      !Array.isArray(dashboards.retention?.cohorts) ||
      !Array.isArray(dashboards.outcomes?.daily) || !dashboards.reminderHealth) {
    throw new Error('Incomplete typed dashboard response.');
  }

  const metric = (label, value) => ({ label, value: formatMetric(value) });
  const percentage = value => {
    if (value === null) return 'Unavailable / suppressed';
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) {
      throw new Error('Invalid dashboard rate.');
    }
    return `${formatMetric(value * 100)}%`;
  };
  const rate = (label, value) => {
    if (!value) throw new Error('Missing dashboard rate.');
    return { label, value: `${percentage(value.rate)} (${formatMetric(value.convertedUsers)} / ${formatMetric(value.eligibleUsers)} users)` };
  };
  const panel = (title, source, rows) => {
    if (typeof source.definition !== 'string') throw new Error('Missing dashboard definition.');
    return { title, definition: source.definition, rows };
  };
  const funnel = dashboards.funnel;
  const retention = dashboards.retention;
  const outcomes = dashboards.outcomes;
  const reminders = dashboards.reminderHealth;
  const auth = dashboards.authentication;
  const authRows = auth === undefined
    ? [{ label: 'Coverage', value: 'Unavailable: snapshot predates authentication instrumentation' }]
    : ['session_entry', 'api_token'].flatMap(stage => {
      if (!auth.stages?.[stage] || auth.allUserSigninSuccessRate !== null ||
          auth.preAuthFailures !== null || auth.providerBreakdown !== null) {
        throw new Error('Invalid authentication coverage claims.');
      }
      const fields = {
        ...Object.fromEntries(['observedUsers', 'succeededUsers', 'failedUsers']
          .map(field => [field, auth.stages[stage][field]])),
        ...Object.fromEntries(['timeout', 'network', 'validation', 'unavailable', 'unknown']
          .map(kind => [`${kind} failure users`, auth.stages[stage].failureKinds?.[kind]])),
      };
      return Object.entries(fields).map(([field, value]) => {
        if (value !== null && (!Number.isInteger(value) || value < 50)) {
          throw new Error('Invalid authentication cohort.');
        }
        return metric(`${stage.replaceAll('_', ' ')} ${field.replace('Users', ' users')}`, value);
      });
    });
  return [
    panel('Ordered opt-in funnel', funnel, [
      ...Object.entries(funnel.stages).map(([name, stage]) => metric(name.replaceAll('_', ' '), stage.users)),
      rate('Visit to download', funnel.visitToDownload),
      rate('Download to launch', funnel.downloadToLaunch),
      rate('Launch to sign-in', funnel.launchToSignin),
      rate('Same-day activation', funnel.sameDayActivation),
    ]),
    panel('Exact-day practice retention', retention, retention.cohorts.length === 0
      ? [{ label: 'Cohorts', value: 'No observed eligible cohorts' }]
      : retention.cohorts.flatMap(cohort => [1, 7, 30].map(offset => {
        const value = cohort[`d${offset}`];
        if (!value || typeof value.matured !== 'boolean') throw new Error('Invalid retention cohort.');
        return { label: `${cohort.cohortDay} D${offset}`, value: value.matured
          ? `${percentage(value.rate)} (${formatMetric(value.practicingUsers)} / ${formatMetric(value.eligibleUsers)} users)`
          : 'Not yet mature; unavailable' };
      }))),
    panel('Observed habit outcomes', outcomes, outcomes.daily.flatMap(day => [
      metric(`${day.day} median automaticity`, day.medianAutomaticity),
      metric(`${day.day} score contributors`, day.scoreUsers),
      metric(`${day.day} practicing users`, day.practicingUsers),
      metric(`${day.day} graduated users`, day.graduatedUsers),
      metric(`${day.day} graduations`, day.graduationCount),
    ])),
    panel('Observed reminder health', reminders, [
      metric('Users sent a reminder request', reminders.sentUsers),
      metric('Observed delivered users', reminders.deliveredUsers),
      metric('Observed opened users', reminders.openedUsers),
      metric('Observed dismissed users', reminders.dismissedUsers),
      rate('Observed delivery to action', reminders.actionRate),
      rate('Sent users disabling reminders', reminders.disableRate),
    ]),
    panel('Partial account-consented authentication observations',
      auth ?? { definition: 'Historical snapshot has no authentication observations; pre-auth failures and provider/global conversion are unknown.' },
      [...authRows, { label: 'Pre-auth failures / global conversion / provider attribution',
        value: 'UNKNOWN / NOT covered; never zero or a full sign-in funnel' }]),
  ];
}

export function goalPanels(data) {
  const metrics = data?.goalMetrics;
  if (metrics?.schemaVersion !== 1 || metrics.source !== 'on_demand_target_aligned' ||
      metrics.minimumCohort !== 50 || !Array.isArray(metrics.goals) || metrics.goals.length !== 13 ||
      typeof metrics.coverage !== 'string' ||
      ![metrics.startDay, metrics.endDay, metrics.observedThrough].every(day => typeof day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day))) {
    throw new Error('Incomplete target-aligned metric response.');
  }
  const seen = new Set();
  const rows = metrics.goals.map(goal => {
    if (typeof goal.id !== 'string' || seen.has(goal.id) || typeof goal.label !== 'string' || typeof goal.definition !== 'string' ||
        !['fraction', 'per_user', 'hours', 'business_days'].includes(goal.unit) ||
        !['at_least', 'at_most', 'track'].includes(goal.comparison) ||
        ![null, 'not_observable', 'cohort_below_50', 'contributors_below_50'].includes(goal.reason) ||
        (goal.value === null) !== (goal.reason !== null) ||
        (goal.target === null) !== (goal.comparison === 'track') ||
        [goal.target, goal.value].some(value => value !== null &&
          (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || goal.unit === 'fraction' && value > 1)) ||
        [goal.numerator, goal.denominator].some(value => value !== null && (!Number.isInteger(value) || value < 50)) ||
        goal.value !== null && (goal.numerator === null || goal.denominator === null)) {
      throw new Error('Invalid target-aligned metric; no substitute value rendered.');
    }
    seen.add(goal.id);
    const display = value => value === null ? 'Unavailable' : goal.unit === 'fraction' ? `${formatMetric(value * 100)}%` :
      `${formatMetric(value)} ${goal.unit.replaceAll('_', ' ')}`;
    const target = goal.target === null ? 'Tracking only; no numeric target specified' :
      `Goal ${goal.comparison === 'at_least' ? '>=' : '<='}${display(goal.target)}`;
    const evidence = goal.reason ? `Unavailable (${goal.reason}); no pass/fail claim` :
      `Observed ${display(goal.value)}; ${goal.comparison === 'track' ? 'tracking only' :
        (goal.comparison === 'at_least' ? goal.value >= goal.target : goal.value <= goal.target) ?
          'observed target met, not population proof' : 'observed target not met'}`;
    return { label: goal.label, value: `${target}; actual ${evidence}; numerator ${formatMetric(goal.numerator)} / denominator ${formatMetric(goal.denominator)}. ${goal.definition}` };
  });
  return [{ title: 'Original goals / observed actuals (version1, on demand)',
    definition: `${metrics.startDay} through ${metrics.endDay}; completed UTC dates before ${metrics.observedThrough}. ${metrics.coverage} Frequency/graduation horizons must end in this selected window; immature cohorts are excluded, never failing outcomes. These are not persisted daily-worker snapshots.`,
    rows }];
}

export function supportPanels(data) {
  const metrics = data?.supportMetrics;
  const first = metrics?.firstResponses;
  const low = metrics?.lowRatings48h;
  const calendar = metrics?.businessDays;
  const coverage = metrics?.coverage;
  const reasons = [null, 'cohort_below_50', 'contributors_below_50', 'invalid_receipts',
    'conflicting_receipts', 'server_clock_unavailable', 'first_response_unavailable'];
  const count = value => value === null || Number.isInteger(value) && value >= 50 && value <= 10000;
  const duration = value => value === null || typeof value === 'number' && Number.isFinite(value) && value >= 0;
  if (metrics?.schemaVersion !== 1 || metrics.source !== 'server_voice_receipts' ||
      metrics.minimumCohort !== 50 || typeof metrics.definition !== 'string' ||
      ![metrics.startDay, metrics.endDay].every(day => typeof day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day)) ||
      typeof metrics.observedAt !== 'string' || !Number.isFinite(Date.parse(metrics.observedAt)) ||
      !first || !low || !calendar || !coverage ||
      !reasons.includes(first.reason) || !reasons.includes(low.reason) ||
      ![first.records, first.contributingAccounts, low.contributingAccounts, low.matureRecords,
        low.within48, low.respondedLate, low.overdueUnanswered, low.immatureRecords, coverage.legacyRecords].every(count) ||
      ![first.medianHours, first.maximumHours].every(duration) ||
      (first.reason === null
        ? [first.records, first.contributingAccounts, first.medianHours, first.maximumHours].some(value => value === null) ||
          first.records < first.contributingAccounts || first.maximumHours < first.medianHours
        : [first.records, first.contributingAccounts, first.medianHours, first.maximumHours].some(value => value !== null)) ||
      low.thresholdHours !== 48 ||
      (low.reason === null
        ? typeof low.complianceFraction !== 'number' || !Number.isFinite(low.complianceFraction) ||
          low.complianceFraction < 0 || low.complianceFraction > 1 ||
          [low.matureRecords, low.within48, low.contributingAccounts].some(value => value === null) ||
          low.matureRecords < low.contributingAccounts || low.within48 > low.matureRecords ||
          low.complianceFraction !== low.within48 / low.matureRecords
        : low.complianceFraction !== null) ||
      calendar.target !== 2 || calendar.value !== null || calendar.reason !== 'calendar_not_configured' ||
      !['contributors_below_50', 'legacy_receipt_unavailable'].includes(coverage.legacyReason) ||
      coverage.legacyReason === 'contributors_below_50' && coverage.legacyRecords !== null) {
    throw new Error('Invalid server support measurement; no inferred timing or compliance rendered.');
  }
  const unavailable = reason => `Unavailable (${reason}); no pass/fail claim`;
  const elapsed = value => first.reason ? unavailable(first.reason) : `${formatMetric(value)} hours (descriptive only)`;
  return [{
    title: 'Private support — server receipt / first actual operator reply',
    definition: `${metrics.startDay} through ${metrics.endDay}, receipt UTC dates; observed at ${metrics.observedAt}. ${metrics.definition} Counts/subsets require50 distinct contributing owners. This is separate from opt-in product goals and persisted worker snapshots.`,
    rows: [
      { label: 'Median answered elapsed time', value: elapsed(first.medianHours) },
      { label: 'Maximum answered elapsed time', value: elapsed(first.maximumHours) },
      { label: 'Answered records / contributing accounts', value: `${formatMetric(first.records)} / ${formatMetric(first.contributingAccounts)}` },
      { label: 'Observed mature low-rating response fraction within48h',
        value: `48-hour threshold; ${low.reason ? unavailable(low.reason) : `${formatMetric(low.complianceFraction * 100)}% observed; no numeric compliance target specified`}; ${formatMetric(low.within48)} timely / ${formatMetric(low.matureRecords)} mature records` },
      { label: 'Mature low-rating contributing accounts', value: formatMetric(low.contributingAccounts) },
      { label: 'Mature responses later than48h', value: formatMetric(low.respondedLate) },
      { label: 'Overdue unanswered low ratings (included in mature denominator)', value: formatMetric(low.overdueUnanswered) },
      { label: 'Immature low ratings (deadline still open; not failing outcomes)', value: formatMetric(low.immatureRecords) },
      { label: 'Business-day response goal', value: `<=2 business days; ${unavailable(calendar.reason)}. Timezone/holiday calendar is not configured; elapsed hours do not substitute.` },
      { label: 'Excluded legacy records (all retained scanned feedback; receipt window unknown)',
        value: `${formatMetric(coverage.legacyRecords)} (${coverage.legacyReason}); no client-time/reply-prefix backfill` },
    ],
  }];
}

export function snapshotPanels(data) {
  const series = data?.dailySnapshots;
  if (series?.source !== 'persisted_daily_worker' || !Array.isArray(series.days) ||
      typeof series.definition !== 'string' || series.days.length < 1 || series.days.length > 30) {
    throw new Error('Incomplete persisted daily worker series.');
  }
  const history = { title: 'Persisted daily worker — completed UTC-day history', definition: series.definition,
    rows: series.days.map(day => {
      if (day.status === 'unavailable' && day.record === null) {
        return { label: day.day, value: `Unavailable (${day.reason}); no raw-data fallback` };
      }
      if (day.status !== 'available' || !day.record || day.registryVersion !== 1 || typeof day.generatedAt !== 'string') {
        throw new Error('Invalid persisted daily worker record.');
      }
      if (day.generationOffsetSeconds !== undefined &&
          (typeof day.generationOffsetSeconds !== 'number' || !Number.isFinite(day.generationOffsetSeconds))) {
        throw new Error('Invalid snapshot generation delay.');
      }
      const timing = day.generationOffsetSeconds === undefined ? '' :
        `; generation offset ${day.generationOffsetSeconds} seconds from ${day.scheduledAt} (not proof of scheduled execution)`;
      return { label: day.day, value: `Generated ${day.generatedAt}; registry v${day.registryVersion}${timing}; independent daily cohorts (null remains suppressed/unavailable)` };
    }) };
  if (series.schedule !== undefined) {
    const schedule = series.schedule;
    if (schedule.cron !== '20 2 * * *' || schedule.backfillMaxDays !== 30 ||
        typeof schedule.latestDueAt !== 'string' || typeof schedule.latestTickDue !== 'boolean' ||
        typeof schedule.definition !== 'string') throw new Error('Invalid worker schedule contract.');
    history.definition += ` ${schedule.definition} Backfill is explicit and limited to30 completed UTC days.`;
    history.rows.unshift({ label: 'Latest completed-day schedule (UTC)',
      value: `Due ${schedule.latestDueAt}; ${schedule.latestTickDue ? 'due time passed' : 'awaiting declared due time'}; no punctuality or fresh-snapshot success inferred` });
  }
  const latest = series.days.find(day => day.day === series.endDay);
  if (!latest || latest.status !== 'available') {
    history.rows.push({ label: 'Latest completed UTC day', value: 'Unavailable; no older-day or on-demand substitute' });
    return [history];
  }
  return [history, ...dashboardPanels(latest.record).map(panel => ({
    ...panel, title: `Persisted ${latest.day} — ${panel.title}`,
    definition: `Generated ${latest.generatedAt}. ${panel.definition}`,
  }))];
}

export function replyAttempt(previous, payload, id = () => crypto.randomUUID()) {
  const key = JSON.stringify(payload);
  return previous?.key === key ? previous : { key, requestId: id() };
}

function initialize() {
  const element = id => document.getElementById(id);
  const status = element('admin-status');
  const panel = element('feedback');
  const next = element('next-feedback');
  let cursor = null;
  let cursorSeen = new Set();
  const pending = new Set();
  let auth;
  let sessionGeneration = 0;
  element('signin-console').disabled = true;
  loadOperatorAuth(location.origin).then(value => {
    auth = value;
    element('signin-console').disabled = false;
    return value;
  }).catch(() => {
    status.textContent = 'Operator identity is not configured. No manual-token fallback is available.';
    return null;
  });
  element('origin').value = location.origin;

  async function request(path, body) {
    if(!auth) throw new Error('Sign in to the operator console first.');
    const generation = sessionGeneration;
    if(element('origin').value !== location.origin) throw new Error('Use this deployed HTTPS site only.');
    if(generation !== sessionGeneration) throw new Error('Operator session was cleared.');
    const controller = new AbortController();
    pending.add(controller);
    const timeout = setTimeout(() => controller.abort(), 20000);
    try {
      const data = await operatorRequest(auth,location.origin,path,{
        method: body ? 'POST' : 'GET',
        signal: controller.signal,
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      if(generation !== sessionGeneration) throw new Error('Operator session was cleared.');
      return data;
    } finally {
      clearTimeout(timeout);
      pending.delete(controller);
    }
  }

  async function loadFeedback(reset) {
    next.disabled = true;
    status.textContent = 'Loading private feedback...';
    try {
      const pageCursor = reset ? null : cursor;
      const data = await request('/api/team/feedback?limit=20' + (pageCursor ? `&cursor=${encodeURIComponent(pageCursor)}` : ''));
      if (!Array.isArray(data.feedback) || !(data.nextCursor === null || typeof data.nextCursor === 'string')) {
        throw new Error('Incomplete private feedback page.');
      }
      if (reset) { panel.replaceChildren(); cursorSeen = new Set(); }
      if (data.nextCursor !== null && cursorSeen.has(data.nextCursor)) throw new Error('Feedback cursor did not advance.');
      if (data.nextCursor !== null) cursorSeen.add(data.nextCursor);
      for (const item of data.feedback) {
        if (!item.record || !statuses.includes(item.record.status)) throw new Error('Invalid feedback status.');
        const card = document.createElement('article');
        const title = document.createElement('h3');
        title.textContent = `${item.record.kind} - ${item.record.status}`;
        const body = document.createElement('p'); body.textContent = item.record.body;
        const history = document.createElement('div');
        const replies = JSON.parse(item.record.replies);
        if (!Array.isArray(replies) || replies.some(value => typeof value !== 'string')) throw new Error('Invalid private reply thread.');
        for (const text of replies) {
          const reply = document.createElement('p'); reply.textContent = text; history.append(reply);
        }
        const reply = document.createElement('textarea');
        reply.placeholder = 'Private team reply'; reply.maxLength = 2000;
        reply.setAttribute('aria-label', 'Private team reply');
        const selection = document.createElement('select');
        selection.setAttribute('aria-label', 'Feedback status');
        for (const value of statuses) {
          const option = document.createElement('option');
          option.value = value; option.textContent = value; selection.append(option);
        }
        selection.value = item.record.status;
        const send = document.createElement('button'); send.textContent = 'Save status and reply';
        let attempt;
        send.addEventListener('click', async () => {
          if (!reply.value.trim()) { status.textContent = 'Explain the status or enter a private reply.'; return; }
          send.disabled = true;
          const payload = { id: item.record.id, status: selection.value, reply: reply.value.trim() };
          attempt = replyAttempt(attempt, payload);
          try {
            await request(`/api/team/feedback/${encodeURIComponent(item.userId)}`, { ...payload, requestId: attempt.requestId });
            title.textContent = `${item.record.kind} - ${selection.value}`;
            const saved = document.createElement('p'); saved.textContent = payload.reply; history.append(saved);
            reply.value = '';
            status.textContent = 'Reply saved privately. The user receives it on the next successful sync.';
          } catch (error) { status.textContent = error.message; }
          finally { send.disabled = false; }
        });
        card.append(title, body, history, reply, selection, send); panel.append(card);
      }
      cursor = data.nextCursor;
      next.disabled = cursor === null;
      status.textContent = `${data.feedback.length} private items loaded. ${cursor === null ? 'End of pages.' : 'More pages are available, including after an empty filtered page.'}`;
    } catch (error) { status.textContent = error.message; }
  }

  element('signin-console').addEventListener('click', async () => {
    const cleared = clear();
    const generation = sessionGeneration;
    try {
      if(!auth) throw new Error('Not configured');
      await cleared;
      if(generation !== sessionGeneration) return;
      status.textContent = 'Opening secure Bloomstep operator sign-in...';
      await auth.signIn();
      if(generation !== sessionGeneration) return;
      status.textContent = 'Signed in. Server-assigned Bloomstep.Admin is required to load private data.';
    } catch { if(generation === sessionGeneration) status.textContent = 'Operator sign-in failed, cancelled, or is not configured.'; }
  });
  element('admin').addEventListener('submit', event => {
    event.preventDefault(); void loadFeedback(true);
  });
  next.addEventListener('click', () => { if (cursor !== null) void loadFeedback(false); });
  element('metrics').addEventListener('click', async () => {
    status.textContent = 'Loading consent-safe aggregate counts...';
    element('measurement').replaceChildren();
    element('aarrr-report').replaceChildren();
    element('metrics').disabled = true;
    try {
      const days = Number(element('metric-days').value);
      if (!Number.isInteger(days) || days < 1 || days > 30) throw new Error('Choose 1-30 UTC days.');
      const data = await loadAarrr(element('aarrr-report'), request, days);
      const cards = [
        ...goalPanels(data),
        ...supportPanels(data),
        ...reminderPreferencePanels(data),
        ...snapshotPanels(data),
        ...dashboardPanels(data).map(panel => ({ ...panel, title: `On-demand window — ${panel.title}` })),
        ...metricPanels(data).map(panel => ({ ...panel, title: `Raw compatibility window — ${panel.title}` })),
      ];
      const grid = document.createElement('div'); grid.className = 'grid';
      for (const item of cards) {
        const card = document.createElement('article');
        const title = document.createElement('h3'); title.textContent = item.title; card.append(title);
        if (item.definition) {
          const definition = document.createElement('p'); definition.className = 'small';
          definition.textContent = item.definition; card.append(definition);
        }
        for (const row of item.rows) {
          const line = document.createElement('p'); line.textContent = `${row.label}: ${row.value}`; card.append(line);
        }
        grid.append(card);
      }
      const limits = document.createElement('ul');
      for (const text of data.limitations) {
        if (typeof text !== 'string') throw new Error('Invalid measurement limitation.');
        const line = document.createElement('li'); line.textContent = text; limits.append(line);
      }
      element('measurement').append(grid, limits);
      element('daily-counts').textContent = JSON.stringify({ persistedDailyWorker: data.dailySnapshots.days,
        rawCompatibilityDailyCounts: data.daily }, null, 2);
      status.textContent = `Persisted worker history covers ${data.dailySnapshots.startDay} through ${data.dailySnapshots.endDay}; its latest completed-day panels require an available stored snapshot. Separately labelled on-demand dashboards cover ${data.dashboards.startDay} through ${data.dashboards.endDay}; raw compatibility counts include today. Private support uses server receipt/first committed operator reply facts, not product-event consent, customer-read proof or an all-feedback census. Business-day calendar remains unavailable. No daily unique-user/retention/median rollup is inferred. Cohorts below ${data.minimumCohort} are suppressed, not zero. Experiment remains off; crash-free rate is unavailable. Worker deployment and token execution need independent live verification.`;
    } catch (error) {
      element('aarrr-report').replaceChildren();
      status.textContent = `Measurement unavailable: ${error.message} No prior or substitute counts displayed.`;
    } finally { element('metrics').disabled = false; }
  });

  element('website-metrics').addEventListener('click', async () => {
    const output = element('website-funnel'), webStatus = element('website-admin-status');
    output.replaceChildren(); webStatus.textContent = 'Loading separate website aggregates...';
    try {
      const data = await request(`/api/team/website?days=${element('website-days').value}`);
      for (const panel of websitePanels(data)) {
        const card = document.createElement('article'), title = document.createElement('h3');
        title.textContent = panel.title;
        const description = document.createElement('p'); description.textContent = panel.definition;
        card.append(title, description);
        for (const row of panel.rows) {
          const line = document.createElement('p'); line.textContent = `${row.label}: ${row.value}`; card.append(line);
        }
        output.append(card);
      }
      webStatus.textContent = 'Anonymous counts and voluntary linked cohorts are separate; unknowns are not zero. Store is reserved.';
    } catch (error) { webStatus.textContent = error.message; }
  });

  function clear() {
    for (const controller of pending) controller.abort();
    ++sessionGeneration;
    const cleared = auth?.clear();
    panel.replaceChildren(); element('measurement').replaceChildren();
    element('aarrr-report').replaceChildren();
    element('website-funnel').replaceChildren(); element('website-admin-status').textContent = '';
    element('daily-counts').textContent = ''; status.textContent = '';
    cursor = null; cursorSeen.clear(); next.disabled = true;
    return cleared;
  }
  element('clear-console').addEventListener('click', clear);
  window.addEventListener('pagehide', clear);
}

if (typeof document !== 'undefined') initialize();
