const labels = {
  signin_succeeded: 'Observed sign-in', recipe_created: 'Saved first recipe', first_checkin: 'Saved first positive check-in',
};
const unavailable = {
  unknown: 'Unknown / absent observations', suppressed: 'Privacy suppressed',
  pending: 'Pending observation window', unsupported: 'Not implemented / unavailable',
};
const validDay = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
const count = value => value === null || Number.isInteger(value) && value >= 0;
const published = value => value === null || Number.isInteger(value) && value >= 50;
const fraction = value => value === null || typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;
const displayCount = value => value === null ? 'Unavailable' : value.toLocaleString();
const displayRate = value => value === null ? 'Unavailable' : `${(value * 100).toFixed(1)}%`;

export function aarrrPanels(data) {
  const fail = () => { throw Error('Invalid or incomplete AARRR report; no substitute metrics rendered.'); };
  const observation = value => value && published(value.accounts) && ['measured', 'unknown', 'suppressed'].includes(value.status) &&
    (value.status === 'measured') === (value.accounts !== null);
  if (data?.schemaVersion !== 1 || data.unit !== 'consented_account' || data.minimumContributors !== 50 ||
      ![data.startDay, data.endDay, data.observedThrough].every(validDay) || data.startDay > data.endDay ||
      data.endDay >= data.observedThrough || typeof data.coverage !== 'string' ||
      ![data.acquisition, data.funnel, data.retention, data.referral, data.revenue].every(value => typeof value?.definition === 'string') ||
      data.acquisition.status !== 'unsupported' || data.acquisition.accountAttributionRate !== null ||
      data.revenue.status !== 'unsupported' || data.revenue.value !== null ||
      data.experiment?.eligible !== false || typeof data.experiment.reason !== 'string' ||
      !Array.isArray(data.funnel.stages) || data.funnel.stages.length !== 3 ||
      !Array.isArray(data.funnel.transitions) || data.funnel.transitions.length !== 2 ||
      !Array.isArray(data.retention.cohorts) || !validDay(data.retention.cohortStartDay)) fail();
  data.funnel.stages.forEach((stage, index) => {
    if (stage.name !== Object.keys(labels)[index] || !observation(stage)) fail();
  });
  data.funnel.transitions.forEach((step, index) => {
    if (step.from !== data.funnel.stages[index].name || step.to !== data.funnel.stages[index + 1].name ||
        step.horizonDays !== 7 || !['measured', 'unknown', 'suppressed'].includes(step.status) ||
        ![step.eligibleAccounts, step.convertedAccounts, step.laggedAccounts, step.pendingAccounts, step.censoredAccounts].every(count) ||
        !fraction(step.rate)) fail();
    const parts = [step.convertedAccounts, step.laggedAccounts, step.pendingAccounts, step.censoredAccounts];
    if (step.status === 'measured' ? !published(step.eligibleAccounts) || step.eligibleAccounts === null ||
        parts.some(value => value === null || value > 0 && value < 50) ||
        parts.reduce((sum, value) => sum + value, 0) !== step.eligibleAccounts ||
        step.rate !== step.convertedAccounts / step.eligibleAccounts :
        step.rate !== null || step.eligibleAccounts !== null || parts.some(value => value !== null)) fail();
  });
  data.retention.cohorts.forEach(cohort => {
    if (!validDay(cohort.cohortDay) || cohort.cohortDay < data.retention.cohortStartDay ||
        cohort.cohortDay > data.endDay || !published(cohort.accounts)) fail();
    [1, 7, 30].forEach(offset => {
      const entry = cohort[`d${offset}`];
      if (!entry || !validDay(entry.targetDay) || !['pending', 'measured', 'suppressed'].includes(entry.status) ||
          !published(entry.eligibleAccounts) || !count(entry.practicingAccounts) || !fraction(entry.rate) ||
          entry.targetDay !== new Date(Date.parse(`${cohort.cohortDay}T00:00:00Z`) + offset * 86400000).toISOString().slice(0, 10)) fail();
      if (entry.status === 'measured' ? entry.targetDay >= data.observedThrough ||
          entry.eligibleAccounts === null || entry.practicingAccounts === null || entry.practicingAccounts > entry.eligibleAccounts ||
          entry.practicingAccounts > 0 && entry.practicingAccounts < 50 ||
          entry.eligibleAccounts - entry.practicingAccounts > 0 && entry.eligibleAccounts - entry.practicingAccounts < 50 ||
          entry.rate !== entry.practicingAccounts / entry.eligibleAccounts :
          entry.rate !== null || entry.practicingAccounts !== null ||
          entry.status === 'pending' && entry.targetDay < data.observedThrough) fail();
    });
  });
  const referral = data.referral;
  if (![referral.initiated, referral.linkOpened, referral.accepted].every(observation) ||
      ![referral.sent, referral.referredActivation].every(value => value?.status === 'unsupported' && value.accounts === null)) fail();
  const showObservation = entry => entry.status === 'measured' ? displayCount(entry.accounts) : unavailable[entry.status];
  const lastD7 = [...data.retention.cohorts].reverse().find(cohort => cohort.d7.status === 'measured');
  const activation = data.funnel.transitions[1];
  const overview = [
    { label: 'Acquisition', value: 'Separate web events', note: 'Page touches, not people; load channel drilldown below.', status: 'unsupported' },
    { label: 'Activation · 7 days', value: activation.status === 'measured' ? displayRate(activation.rate) : unavailable[activation.status],
      note: activation.status === 'measured'
        ? `${displayCount(activation.convertedAccounts)} / ${displayCount(activation.eligibleAccounts)} observed recipe accounts; saved positive same-habit check-in.`
        : 'Saved recipe → first positive same-habit check-in; denominator unavailable.', status: activation.status },
    { label: 'Retention · exact D7', value: lastD7 ? displayRate(lastD7.d7.rate) : 'Unknown / no publishable mature cohort',
      note: lastD7 ? `${lastD7.cohortDay} cohort; local-day activity.` : 'Pending and suppressed cohorts stay distinct.', status: lastD7 ? 'measured' : 'unknown' },
    { label: 'Referral · share intent', value: showObservation(referral.initiated),
      note: 'Distinct observed accounts. Sent/attributed activation unavailable.', status: referral.initiated.status },
    { label: 'Revenue', value: unavailable.unsupported, note: 'No verified payment evidence; not revenue zero.', status: 'unsupported' },
  ];
  const transitionRows = data.funnel.transitions.flatMap(step => [
    { label: `${labels[step.from]} → ${labels[step.to]} · 7-day conversion`,
      value: step.status === 'measured' ? `${displayRate(step.rate)} (${displayCount(step.convertedAccounts)} / ${displayCount(step.eligibleAccounts)} accounts)` : unavailable[step.status] },
    ...['lagged', 'pending', 'censored'].map(key => ({ label: `${labels[step.from]} · ${key === 'lagged' ? 'Observed no next stage in 7 days (not abandonment)' : key}`,
      value: step.status === 'measured' ? displayCount(step[`${key}Accounts`]) : unavailable[step.status] })),
  ]);
  return { overview, stages: data.funnel.stages.map(stage => ({ ...stage, label: labels[stage.name], value: showObservation(stage) })),
    details: [
      { title: 'Ordered saved activation / observed gaps', definition: data.funnel.definition, rows: transitionRows },
      { title: 'Retention cohorts / local-day boundaries', definition: data.retention.definition,
        rows: data.retention.cohorts.length ? data.retention.cohorts.flatMap(cohort => [1, 7, 30].map(offset => {
          const entry = cohort[`d${offset}`];
          return { label: `${cohort.cohortDay} · D${offset} · target ${entry.targetDay}`,
            value: entry.status === 'measured' ? `${displayRate(entry.rate)} (${displayCount(entry.practicingAccounts)} / ${displayCount(entry.eligibleAccounts)} accounts)` : unavailable[entry.status] };
        })) : [{ label: 'Cohorts', value: 'Unknown / no observed eligible cohorts' }] },
      { title: 'Referral evidence / unavailable handoffs', definition: referral.definition,
        rows: [['Share initiated', referral.initiated], ['Link opened (imported receipt)', referral.linkOpened], ['Invitation redeemed', referral.accepted],
          ['Invitation sent / delivered', referral.sent], ['Referred activation', referral.referredActivation]]
          .map(([label, entry]) => ({ label, value: showObservation(entry) })) },
      { title: 'Acquisition and revenue coverage', definition: `${data.acquisition.definition} ${data.revenue.definition}`,
        rows: [{ label: 'Account attribution / installation', value: 'Unknown. No automatic web-to-app join or verified installer census.' },
          { label: 'Experiment eligibility', value: data.experiment.reason }] },
    ],
  };
}

export function renderAarrr(container, data, { fixture = false } = {}) {
  const panels = aarrrPanels(data);
  const node = (tag, text, className) => {
    const value = document.createElement(tag);
    if (text !== undefined) value.textContent = text;
    if (className) value.className = className;
    return value;
  };
  const fragment = document.createDocumentFragment();
  fragment.append(node('p', fixture ? 'ISOLATED SYNTHETIC FIXTURE PREVIEW — not production traffic' : 'PRIVATE · observed opt-in accounts', 'eyebrow'));
  fragment.append(node('h2', 'Growth, with the evidence visible'));
  fragment.append(node('p', `${data.startDay} — ${data.endDay} · completed UTC dates · observed through ${data.observedThrough} · 50-contributor privacy floor`, 'small'));
  fragment.append(node('p', data.coverage, 'coverage-note'));
  const grid = node('div', undefined, 'aarrr-overview');
  for (const item of panels.overview) {
    const card = node('article', undefined, 'aarrr-kpi');
    card.append(node('h3', item.label), node('p', item.value, 'aarrr-value'), node('p', item.note, 'small'),
      node('span', item.status, `metric-state ${item.status}`));
    grid.append(card);
  }
  fragment.append(grid);
  const funnel = node('article', undefined, 'aarrr-funnel');
  funnel.append(node('h3', 'Saved activation · cumulative observed stages'));
  const maximum = Math.max(1, ...panels.stages.map(stage => stage.accounts ?? 0));
  for (const stage of panels.stages) {
    const row = node('div', undefined, 'aarrr-stage');
    row.append(node('span', stage.label), node('strong', stage.value));
    if (stage.accounts !== null) {
      const bar = node('div', undefined, 'aarrr-track'), fill = node('div', undefined, 'aarrr-fill');
      fill.style.width = `${stage.accounts / maximum * 100}%`;
      bar.setAttribute('aria-hidden', 'true'); bar.append(fill); row.append(bar);
    }
    funnel.append(row);
  }
  funnel.append(node('p', 'Bars never bridge anonymous website events to app accounts. Gaps below are observations, not inferred abandonment.', 'small'));
  fragment.append(funnel);
  for (const panel of panels.details) {
    const detail = node('details', undefined, 'aarrr-detail');
    detail.append(node('summary', panel.title), node('p', panel.definition, 'small'));
    const list = node('dl', undefined, 'metric-list');
    for (const row of panel.rows) list.append(node('dt', row.label), node('dd', row.value));
    detail.append(list); fragment.append(detail);
  }
  container.replaceChildren(fragment);
}

export async function loadAarrr(container, request, days, options = {}) {
  container.replaceChildren();
  try {
    if (!Number.isInteger(days) || days < 1 || days > 30) throw Error('Choose 1-30 UTC days.');
    const data = await request(`/api/team/metrics?days=${days}`);
    renderAarrr(container, data?.dashboards?.aarrr, options);
    return data;
  } catch (error) {
    container.replaceChildren();
    throw error;
  }
}
