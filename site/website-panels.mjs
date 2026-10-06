export function websitePanels(data) {
  if (data?.schemaVersion !== 1 || data.channel !== 'web' || data.synthetic !== false ||
      typeof data.definition !== 'string' || !data.stages || !data.sources || !data.architectures || !data.linked ||
      !Array.isArray(data.steps) || !Array.isArray(data.linked.steps) || data.linked.minimumContributors !== 50) {
    throw Error('Incomplete website funnel response; no substitute counts rendered.');
  }
  const count = value => {
    if (value === null) return 'Unknown / absent observations';
    if (!Number.isInteger(value) || value <= 0) throw Error('Invalid website count.');
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
    { title: 'Website funnel — web channel', definition: `${data.startDay} through ${data.endDay}. ${data.definition}`,
      rows: [
        ...Object.entries(data.stages).map(([label, value]) => ({ label, value: count(value) })),
        ...data.steps.map(step => {
          const numerator = data.stages[step.to], denominator = data.stages[step.from];
          if (step.rate !== null && (numerator < 50 || denominator < 50 || step.rate !== numerator / denominator) ||
              step.rate === null && step.reason !== 'events_below_50') throw Error('Invalid thresholded event conversion.');
          return { label: `${step.from} → ${step.to} (event conversion, not unique visitors)`, value: rate(step.rate) };
        }),
        ...Object.entries(data.sources).map(([label, value]) => ({ label: `Landing source: ${label}`, value: count(value) })),
        ...Object.entries(data.architectures).map(([label, value]) => ({ label: `Download: ${label}`, value: count(value) })),
      ] },
    { title: 'Separately consented account-linked web cohort', definition: data.linked.definition,
      rows: [
        ...Object.entries(data.linked.stages).map(([label, value]) => ({ label, value: linkedCount(value) })),
        ...data.linked.steps.map(step => ({ label: `${step.from} → ${step.to}`, value: rate(step.rate) })),
        { label: 'Store channel', value: 'Reserved / unavailable; not zero' },
      ] },
  ];
}
