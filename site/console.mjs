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
  ];
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
  element('origin').value = location.origin;
  if (new URLSearchParams(location.search).get('invite') === 'garden') element('invitation').hidden = false;

  async function request(path, body) {
    const connection = approvedConnection(element('origin').value, element('token').value, location.origin);
    const controller = new AbortController();
    pending.add(controller);
    const timeout = setTimeout(() => controller.abort(), 20000);
    try {
      const response = await fetch(connection.origin + path, {
        method: body ? 'POST' : 'GET',
        signal: controller.signal,
        headers: tokenHeaders(connection.token),
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      const data = await response.json();
      if (!response.ok) {
        throw new Error(`API request failed (HTTP ${response.status}): ${typeof data.error === 'string' ? data.error.slice(0, 500) : 'No private details shown.'}`);
      }
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

  element('admin').addEventListener('submit', event => {
    event.preventDefault(); void loadFeedback(true);
  });
  next.addEventListener('click', () => { if (cursor !== null) void loadFeedback(false); });
  element('metrics').addEventListener('click', async () => {
    status.textContent = 'Loading consent-safe aggregate counts...';
    element('measurement').replaceChildren();
    try {
      const days = Number(element('metric-days').value);
      if (!Number.isInteger(days) || days < 1 || days > 30) throw new Error('Choose 1-30 UTC days.');
      const data = await request(`/api/team/metrics?days=${days}`);
      const cards = [...dashboardPanels(data), ...metricPanels(data)];
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
      element('daily-counts').textContent = JSON.stringify(data.daily, null, 2);
      status.textContent = `Typed dashboards cover ${data.dashboards.startDay} through ${data.dashboards.endDay} (completed UTC days); compatibility counts include today. Cohorts below ${data.minimumCohort} are suppressed, not zero. Missing instrumentation is unavailable, not inferred. Experiment remains off; crash-free rate is unavailable. Live authenticated measurement is not yet verified.`;
    } catch (error) { status.textContent = error.message; }
  });

  function clear() {
    for (const controller of pending) controller.abort();
    element('token').value = '';
    panel.replaceChildren(); element('measurement').replaceChildren();
    element('daily-counts').textContent = ''; status.textContent = '';
    cursor = null; cursorSeen.clear(); next.disabled = true;
  }
  element('clear-console').addEventListener('click', clear);
  window.addEventListener('pagehide', clear);
}

if (typeof document !== 'undefined') initialize();
