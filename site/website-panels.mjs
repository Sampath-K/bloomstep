import { acquisitionPanels } from './acquisition-panels.mjs';
import { attributionFields } from '../api/src/website-attribution.mjs';

const validDay = day => typeof day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day) &&
  Number.isFinite(Date.parse(`${day}T00:00:00Z`)) && new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) === day;
const stageNames = ['landing_view', 'primary_cta_click', 'download_click'];
const stageLabels = { landing_view: 'Observed landing events (not unique visits)', primary_cta_click: 'Primary CTA events', download_click: 'Download click events (not completed downloads)' };

export function websitePanels(data) {
  if (data?.schemaVersion !== 1 || data.channel !== 'web' || data.synthetic !== false ||
      typeof data.definition !== 'string' || !data.stages || !data.sources || !data.architectures || !data.linked ||
      !Array.isArray(data.steps) || !Array.isArray(data.linked.steps) || data.linked.minimumContributors !== 50) {
    throw Error('Incomplete website funnel response; no substitute counts rendered.');
  }
  const dimension = (values, names) => values && Object.keys(values).length === names.length &&
    names.every(name => Object.hasOwn(values, name) && (values[name] === null || Number.isInteger(values[name]) && values[name] >= 50));
  if (![data.startDay, data.endDay].every(validDay) || data.startDay > data.endDay ||
      Date.parse(data.endDay) - Date.parse(data.startDay) > 29 * 86400000 ||
      !dimension(data.stages, stageNames) || !dimension(data.sources, attributionFields.source) ||
      !dimension(data.architectures, ['arm64', 'x64', 'unknown']) || data.steps.length !== 2 ||
      data.steps.some((step, index) => step.from !== stageNames[index] || step.to !== stageNames[index + 1])) {
    throw Error('Invalid website window, stages or dimensions.');
  }

  const count = value => {
    if (value === null) return 'Unknown / absent observations';
    if (!Number.isInteger(value) || value < 50) throw Error('Invalid unsuppressed website count.');
    return value.toLocaleString();
  };
  const linkedCount = value => {
    if (value !== null && (!Number.isInteger(value) || value < 50)) throw Error('Unsuppressed linked contributor count.');
    return value === null ? 'Insufficient data' : value.toLocaleString();
  };
  const rate = value => {
    if (value === null) return 'Insufficient data';
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) throw Error('Invalid website rate.');
    return `${(value * 100).toFixed(1)}%`;
  };
  return [
    { title: 'Launch decision overview · website events', definition: `${data.startDay} through ${data.endDay} (UTC; final/current UTC day is partial and in progress). ${data.definition} Freshness / capture completeness is unknown: this response has no ingestion watermark. A successful read is not proof of fresh traffic or complete capture. Not live customer evidence by itself.`,
      rows: [
        ...Object.entries(data.stages).map(([label, value]) => ({ label: stageLabels[label], value: count(value) })),
        ...data.steps.map(step => {
          const numerator = data.stages[step.to], denominator = data.stages[step.from];
          if (step.rate !== null && (numerator === null || denominator === null || numerator < 50 || denominator < 50 ||
              step.rate !== numerator / denominator || step.reason !== null) ||
              step.rate === null && step.reason !== 'events_below_50') throw Error('Invalid thresholded event conversion.');
          return { label: `${step.from} → ${step.to} (event ratio, not unique-person conversion)`,
            value: step.rate === null ? 'Unknown / absent or privacy suppressed; no conversion claim' :
              `${rate(step.rate)} (${count(numerator)} / ${count(denominator)} events)` };
        }),
        ...Object.entries(data.sources).map(([label, value]) => ({ label: `Landing source: ${label}`, value: count(value) })),
        ...Object.entries(data.architectures).map(([label, value]) => ({ label: `Download: ${label}`, value: count(value) })),
      ] },
    { title: 'Separately consented account-linked web cohort', definition: data.linked.definition,
      rows: [
        ...Object.entries(data.linked.stages).map(([label, value]) => ({ label, value: linkedCount(value) })),
        ...data.linked.steps.map(step => {
          const numerator = data.linked.stages[step.to], denominator = data.linked.stages[step.from];
          if (step.rate !== null && (numerator === null || denominator === null || numerator === undefined || denominator === undefined ||
              numerator < 50 || denominator < 50 || numerator > denominator || step.rate !== numerator / denominator)) {
            throw Error('Invalid linked account conversion denominator.');
          }
          return { label: `${step.from} → ${step.to}`, value: step.rate === null ? 'Unknown / absent or privacy suppressed' :
            `${rate(step.rate)} (${linkedCount(numerator)} / ${linkedCount(denominator)} observed accounts)` };
        }),
        { label: 'Store channel', value: 'Reserved / unavailable; not zero' },
      ] },
    ...acquisitionPanels(data.acquisition),
  ];
}

export function renderWebsite(container, data, { fixture = false } = {}) {
  const panels = websitePanels(data);
  const fragment = document.createDocumentFragment();
  const coverage = document.createElement('p');
  coverage.className = 'coverage-note';
  coverage.textContent = fixture ? 'ISOLATED SYNTHETIC FIXTURE — not live traffic or customer evidence.' :
    'Private observation report · synthetic collector partition excluded. Null means unknown / absent or suppressed, never zero. Freshness cannot be verified without an ingestion watermark.';
  fragment.append(coverage);
  for (const panel of panels) {
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

export async function loadWebsite(container, request, days, options = {}) {
  container.replaceChildren();
  try {
    if (!Number.isInteger(days) || days < 1 || days > 30) throw Error('Choose 1-30 website days.');
    const data = await request(`/api/team/website?days=${days}`);
    renderWebsite(container, data, options);
    return data;
  } catch (error) {
    container.replaceChildren();
    throw error;
  }
}
