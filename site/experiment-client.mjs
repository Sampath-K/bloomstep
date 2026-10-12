import { ARMS, applyVariant, assignArm, verifyInstance } from '../api/src/experiment-policy.mjs';

const off = Object.freeze({ active: false, arm: null });

/** Consented per-visit experiment client. The subject id lives only in page memory: a reload or new tab is a new
 * visit (not a person), it is never stored in cookies/localStorage, and withdrawing consent deletes it server-side. */
export function createExperimentClient({ fetchJson, document, uuid = () => crypto.randomUUID() }) {
  let visit = null, pendingForget = null;
  return {
    get state() { return visit ? { active: true, arm: visit.arm, experimentId: visit.instance.experimentId } : off; },
    async start() {
      if (visit) return this.state;
      const config = await fetchJson('/api/web/experiments');
      if (!config?.enabled || !config.active) return off;
      const instance = config.active;
      // Only text from the bundled reviewed catalog may be shown; server-supplied copy is never trusted.
      if (!await verifyInstance(instance)) throw Error('Experiment definition failed verification; showing standard page.');
      const subjectId = uuid(), arm = await assignArm(instance, subjectId);
      if (!ARMS.includes(arm)) throw Error('Experiment assignment failed.');
      let applied = true;
      try { applyVariant(document, instance.surface, instance.arms.control.value, instance.arms[arm].value); } catch { applied = false; }
      visit = { instance, subjectId, arm, applied, exposed: false };
      await fetchJson('/api/web/experiments/exposure', { experimentId: instance.experimentId, definitionHash: instance.definitionHash,
        subjectId, arm, applied });
      if (visit?.subjectId === subjectId) visit.exposed = true;
      return this.state;
    },
    /** Outcomes are sent only after the exposure write succeeded. */
    async outcome(event) {
      if (!visit?.exposed) return false;
      await fetchJson('/api/web/experiments/outcome', { experimentId: visit.instance.experimentId, subjectId: visit.subjectId, event });
      return true;
    },
    /** Consent withdrawal: restore the standard page and delete the visit (server keeps a content-free tombstone). */
    async stop() {
      if (!visit) return pendingForget ?? false;
      const { instance, subjectId } = visit;
      visit = null;
      try { applyVariant(document, instance.surface, instance.arms.candidate.value, instance.arms.control.value); } catch { /* standard markup remains */ }
      pendingForget = fetchJson('/api/web/experiments/forget', { subjectId }).then(() => true).finally(() => { pendingForget = null; });
      return pendingForget;
    },
  };
}
