import { ARMS, applyVariant, assignArm, verifyInstance } from '../api/src/experiment-policy.mjs';

const off = Object.freeze({ active: false, arm: null });

/** Consented per-visit experiment client. The subject id lives only in page memory: a reload or new tab is a new
 * visit (not a person), it is never stored in cookies/localStorage, and withdrawing consent deletes it server-side. */
export function createExperimentClient({ fetchJson, document, uuid = () => crypto.randomUUID(), waitForExposure = async () => {} }) {
  let visit = null, pendingForget = null, generation = 0, starting = false, enrollment = null, outcomes = Promise.resolve();
  const restore = current => {
    if (current.applied) applyVariant(document, current.instance.surface, current.instance.arms[current.arm].value, current.instance.arms.control.value);
  };
  return {
    get state() { return visit?.exposed ? { active: true, arm: visit.arm, experimentId: visit.instance.experimentId } : off; },
    async start() {
      if (visit || starting) return this.state;
      const epoch = ++generation;
      enrollment = new AbortController();
      const signal = enrollment.signal;
      starting = true;
      let current = null;
      try {
        if (pendingForget) await pendingForget;
        const config = await fetchJson('/api/web/experiments');
        if (epoch !== generation || !config?.enabled || !config.active) return off;
        const instance = config.active;
        // Only reviewed bundled pairs can render, never server-supplied arbitrary copy.
        if (!await verifyInstance(instance)) throw Error('Experiment definition failed verification; showing standard page.');
        const subjectId = uuid(), arm = await assignArm(instance, subjectId);
        if (epoch !== generation) return off;
        if (!ARMS.includes(arm)) throw Error('Experiment assignment failed.');
        current = { instance, subjectId, arm, applied: false, exposed: false, persisted: false };
        visit = current;
        let applicationError = null;
        try {
          applyVariant(document, instance.surface, instance.arms.control.value, instance.arms[arm].value);
          current.applied = true;
        } catch (error) { applicationError = error; }
        if (!applicationError) await waitForExposure(signal);
        if (epoch !== generation) return off;
        await fetchJson('/api/web/experiments/exposure', { experimentId: instance.experimentId, definitionHash: instance.definitionHash,
          subjectId, arm, applied: current.applied });
        current.persisted = true;
        if (applicationError) throw applicationError;
        if (epoch !== generation) return off;
        current.exposed = true;
        return this.state;
      } catch (error) {
        if (epoch === generation) {
          if (current) restore(current);
          visit = current?.persisted ? current : null;
          if (current && !current.persisted) {
            try { await fetchJson('/api/web/experiments/forget', { subjectId: current.subjectId }); }
            catch { throw Error(`${error.message} Unconfirmed comparison record deletion; it expires automatically.`); }
          }
        }
        throw error;
      } finally {
        if (epoch === generation) starting = false;
      }
    },
    /** Outcomes are sent only after the exposure write succeeded. */
    async outcome(event) {
      if (!visit?.exposed) return false;
      const current = visit;
      const send = async () => {
        if (visit !== current || !current.exposed) return false;
        await fetchJson('/api/web/experiments/outcome', { experimentId: current.instance.experimentId, subjectId: current.subjectId, event });
        return true;
      };
      outcomes = outcomes.then(send, send);
      return outcomes;
    },
    end() {
      generation++;
      enrollment?.abort();
      starting = false;
      if (visit) restore(visit);
      visit = null;
    },
    /** Consent withdrawal: restore the standard page and delete the visit (server keeps a content-free tombstone). */
    async stop() {
      generation++;
      enrollment?.abort();
      starting = false;
      if (!visit) return pendingForget ?? false;
      const current = visit, { subjectId } = current;
      visit = null;
      restore(current);
      pendingForget = fetchJson('/api/web/experiments/forget', { subjectId }).then(() => true).finally(() => { pendingForget = null; });
      return pendingForget;
    },
  };
}

/** Actual visible post-paint copy, not just successful DOM mutation, defines eligible exposure. */
export function waitForVisibleCopy(document, window, signal) {
  return new Promise((resolve, reject) => {
    let frame, timer;
    const finish = error => {
      window.cancelAnimationFrame(frame);
      window.clearTimeout(timer);
      signal.removeEventListener('abort', aborted);
      if (error) reject(error); else resolve();
    };
    const aborted = () => finish(Error('Page comparison enrollment cancelled.'));
    const visible = () => {
      if (signal.aborted) return aborted();
      const targets = ['#intro', '#primary-cta-copy'].map(selector => document.querySelector(selector));
      const shown = document.visibilityState === 'visible' && targets.every(node => {
        if (!node) return false;
        const r = node.getBoundingClientRect(), style = window.getComputedStyle(node);
        return r.width > 0 && r.height > 0 && r.top >= 0 && r.bottom <= window.innerHeight &&
          r.left >= 0 && r.right <= window.innerWidth && style.visibility === 'visible' && style.display !== 'none';
      });
      if (shown) return finish();
      frame = window.requestAnimationFrame(() => { frame = window.requestAnimationFrame(visible); });
    };
    signal.addEventListener('abort', aborted, { once: true });
    timer = window.setTimeout(() => finish(Error('Page comparison was not exposed in view; standard copy restored.')), 15000);
    frame = window.requestAnimationFrame(visible);
  });
}
