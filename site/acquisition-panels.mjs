const stages = { landing_view: 'Landing views', primary_cta_click: 'Primary CTA clicks', download_click: 'Download clicks' };
const fields = ['source', 'referrerDomain', 'campaignSource', 'campaignMedium', 'campaignName'];
export function acquisitionPanels(data) {
  if (data === undefined) return [{ title: 'Page attribution coverage', definition: 'Historical report predates optional allowlisted enrichment.',
    rows: [{ label: 'First / last touch', value: 'Unavailable / not instrumented; never zero' }] }];
  if (data?.schemaVersion !== 1 || data.scope !== 'consented_page_epoch' || typeof data.definition !== 'string') {
    throw Error('Invalid acquisition attribution report.');
  }
  return touchNames.map(touch => {
    const rows = [];
    for (const [stage, label] of Object.entries(stages)) {
      if (!data[touch]?.[stage] || Object.keys(data[touch][stage]).length !== fields.length) throw Error('Invalid acquisition stage coverage.');
      for (const field of fields) {
        const values = data[touch][stage][field];
        if (!values || Array.isArray(values) || typeof values !== 'object' || Object.keys(values).length === 0) {
          throw Error('Invalid acquisition marginal dimension.');
        }
        const missing = [];
        for (const [value, count] of Object.entries(values)) {
          if (!attributionFields[field].includes(value) ||
              count !== null && (!Number.isInteger(count) || count < 50)) throw Error('Invalid acquisition marginal cell.');
          if (count === null) missing.push(value);
          else rows.push({ label: `${label} · ${field} · ${value}`, value: `${count.toLocaleString()} events` });
        }
        if (missing.length) rows.push({ label: `${label} · ${field} · unavailable labels`,
          value: `Unknown / absent or privacy suppressed (${missing.join(', ')})` });
      }
    }
    return { title: `${touch === 'firstTouch' ? 'First touch' : 'Last touch'} · page-consent attribution`, collapsed: true,
      definition: `${data.definition} Independent marginal counts, not people, joint attribution or channel-to-account conversion. Whole small dimensions are withheld. Missing/suppressed cells are unknown. First/last touch scope is one consented page epoch, not cross-visit acquisition.`,
      rows };
  });
}
import { attributionFields, touchNames } from '../api/src/website-attribution.mjs';
