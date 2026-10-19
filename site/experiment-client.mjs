import { ARMS, applyVariant, assignArm, verifyInstance } from '../api/src/experiment-policy.mjs';

const off = Object.freeze({ active: false, arm: null });

/** Consented per-visit experiment client. The subject id lives only in page memory: a reload or new tab is a new
 * visit (not a person), it is never stored in cookies/localStorage, and withdrawing consent deletes it server-side. */
export function createExperimentClient({ fetchJson, document, uuid = () => crypto.randomUUID(), allowed = () => true }) {
  let visit = null, pendingStart = null, generation = 0, pendingForget = null;
  const forgotten = new Set();
  const restore = current => {
    try { applyVariant(document, current.instance.surface, current.instance.arms.candidate.value, current.instance.arms.control.value); } catch { /* standard markup remains */ }
  };
  const forget = current => {
    if (current.cleaned) return Promise.resolve(false);
    forgotten.add(current);
    if (pendingForget) return pendingForget;
    const work = (async () => {
      let deleted = false;
      for (const item of forgotten) {
        // A rejected response can still mean a committed exposure. Delete after it settles.
        await item.request?.catch(() => {});
        await fetchJson('/api/web/experiments/forget', { subjectId: item.subjectId });
        item.cleaned = true;
        forgotten.delete(item);
        deleted = true;
      }
      return deleted;
    })();
    pendingForget = work;
    return work.finally(() => { if (pendingForget === work) pendingForget = null; });
  };
  return {
    get state() { return visit ? { active: true, arm: visit.arm, experimentId: visit.instance.experimentId } : off; },
    async start() {
      if (!allowed()) return off;
      if (pendingStart) return pendingStart;
      if (visit) return this.state;
      const epoch = generation;
      const current = () => epoch === generation && allowed();
      const work = (async () => {
        let enrollment = null;
        try {
          for (const item of forgotten) await forget(item);
          if (!current()) return off;
          const config = await fetchJson('/api/web/experiments');
          if (!current() || !config?.enabled || !config.active) return off;
          const instance = config.active;
          // Only text from the bundled reviewed catalog may be shown; server-supplied copy is never trusted.
          if (!await verifyInstance(instance)) throw Error('Experiment definition failed verification; showing standard page.');
          if (!current()) return off;
          const subjectId = uuid(), arm = await assignArm(instance, subjectId);
          if (!current()) return off;
          if (!ARMS.includes(arm)) throw Error('Experiment assignment failed.');
          enrollment = { instance, subjectId, arm, exposed: false, request: null };
          applyVariant(document, instance.surface, instance.arms.control.value, instance.arms[arm].value);
          visit = enrollment;
          enrollment.request = Promise.resolve().then(() => {
            if (!current()) return;
            return fetchJson('/api/web/experiments/exposure', { experimentId: instance.experimentId,
              definitionHash: instance.definitionHash, subjectId, arm, applied: true });
          });
          await enrollment.request;
          if (!current() || visit !== enrollment) {
            if (visit === enrollment) { visit = null; restore(enrollment); }
            await forget(enrollment);
            return off;
          }
          enrollment.exposed = true;
          return this.state;
        } catch (error) {
          if (enrollment) {
            if (visit === enrollment) { visit = null; restore(enrollment); }
            // Keep unsuccessful cleanup queued for stop/retry; never keep serving a failed exposure.
            await forget(enrollment).catch(() => {});
          }
          if (epoch !== generation) return off;
          throw error;
        }
      })();
      pendingStart = work;
      try { return await work; }
      finally { if (pendingStart === work) pendingStart = null; }
    },
    /** Outcomes are sent only after the exposure write succeeded. */
    async outcome(event) {
      if (!allowed() || !visit?.exposed) return false;
      await fetchJson('/api/web/experiments/outcome', { experimentId: visit.instance.experimentId, subjectId: visit.subjectId, event });
      return true;
    },
    /** End this page's collection without withdrawing already completed consented observations. */
    async end() {
      generation++;
      pendingStart = null;
      const previous = visit;
      visit = null;
      if (previous) {
        restore(previous);
        if (!previous.exposed) return forget(previous);
      }
      return false;
    },
    /** Consent withdrawal: restore the standard page and delete the visit (server keeps a content-free tombstone). */
    async stop() {
      generation++;
      pendingStart = null;
      const previous = visit;
      visit = null;
      if (previous) { restore(previous); return forget(previous); }
      for (const item of forgotten) return forget(item);
      return pendingForget ?? false;
    },
  };
}
