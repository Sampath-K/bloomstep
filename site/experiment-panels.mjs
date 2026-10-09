const text = value => typeof value === 'string' ? value : '';
const pct = value => typeof value === 'number' && Number.isFinite(value) ? `${(value * 100).toFixed(1)}%` : 'Unavailable';
const decisions = {
  promote: 'Candidate promoted (build-time artifact only)', retain_control: 'Control retained', candidate_worse: 'Control retained (candidate worse)',
  rollback_harm: 'Rolled back: pre-registered harm look', insufficient: 'Insufficient evidence; control retained', killed: 'Stopped by kill switch',
};

/** Validates the private /api/team/experiments report and returns display panels; never derives counts itself. */
export function experimentPanels(data) {
  if (data?.schemaVersion !== 1 || !['production', 'isolated'].includes(data.environment) || typeof data.enabled !== 'boolean' ||
      typeof data.killed !== 'boolean' || data.activeCounts !== null || typeof data.definition !== 'string' ||
      !Array.isArray(data.concluded) || !Array.isArray(data.promotions) || !Array.isArray(data.audit) || !Array.isArray(data.catalog) ||
      !/^[0-9a-f]{64}$/.test(data.policyHash ?? '')) {
    throw Error('Incomplete experiment report; no substitute status rendered.');
  }
  const environment = data.environment === 'isolated' ? 'Isolated acceptance store (synthetic, not customers)' : 'Production';
  const panels = [
    { title: `Page experiments — ${environment}`, definition: data.definition, rows: [
      { label: 'Loop state', value: data.enabled ? 'Enabled' : `Off (${text(data.reason) || 'gate closed'})` },
      { label: 'Kill switch', value: data.killed ? 'Engaged' : 'Not engaged' },
      { label: 'Active experiment', value: data.active ? `${data.active.experimentId} until ${data.active.endAt}` : 'None' },
      { label: 'Active arm counts', value: data.active ? 'Withheld until the pre-registered final analysis' : 'Not applicable' },
      { label: 'Guardrails', value: 'Consented visits only; harm-only interim looks; fixed-horizon final α=0.05; low cells insufficient; no live efficacy claim' },
      { label: 'Policy hash', value: data.policyHash },
      { label: 'Curated catalog', value: data.catalog.join(', ') },
    ] },
  ];
  panels.push({ title: 'Concluded experiments', definition: 'Visit-level download intent; not people, installs or activation.',
    rows: data.concluded.length ? data.concluded.map(row => ({ label: `${row.key} (${row.experimentId})`,
      value: `${decisions[row.decision] ?? 'Unknown decision'}; control ${pct(row.stats?.p0)} vs candidate ${pct(row.stats?.p1)}` +
        (row.stats?.ci95 ? `; 95% CI of difference ${pct(row.stats.ci95[0])} to ${pct(row.stats.ci95[1])}` : '') })) :
      [{ label: 'History', value: 'No concluded experiments' }] });
  panels.push({ title: 'Promotion artifacts', definition: 'Production winners ship only through a reviewed draft PR editing site/experiment-promotions.json.',
    rows: data.promotions.length ? data.promotions.map(row => ({ label: row.key, value: `${row.status} at ${row.at}` })) :
      [{ label: 'Promotions', value: 'None' }] });
  panels.push({ title: 'Audit history', definition: 'Bounded audit trail without visit identifiers.', collapsed: true,
    rows: data.audit.slice(-50).map(row => ({ label: `${row.at} ${row.action}`, value: text(row.experimentId) || text(row.reason) || text(row.decision) || '' })) });
  return panels;
}

export function renderExperiments(container, data) {
  const fragment = document.createDocumentFragment();
  for (const panel of experimentPanels(data)) {
    const card = document.createElement(panel.collapsed ? 'details' : 'article');
    const title = document.createElement(panel.collapsed ? 'summary' : 'h3');
    title.textContent = panel.title;
    const description = document.createElement('p'); description.textContent = panel.definition;
    card.append(title, description);
    for (const row of panel.rows) {
      const line = document.createElement('p'); line.textContent = `${row.label}: ${row.value}`; card.append(line);
    }
    fragment.append(card);
  }
  container.replaceChildren(fragment);
}

export async function loadExperiments(container, request) {
  container.replaceChildren();
  try {
    const data = await request('/api/team/experiments');
    renderExperiments(container, data);
    return data;
  } catch (error) {
    container.replaceChildren();
    throw error;
  }
}
