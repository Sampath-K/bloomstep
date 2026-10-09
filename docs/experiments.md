# Guarded website experiment loop

Status: **implemented, isolated acceptance passing, production OFF.** No live efficacy claim is made: no real
customer cohort exists, and every result below comes from synthetic or labeled fixture inputs in an isolated store.

## What the loop does

`POST /api/internal/experiments/tick` (worker role `Bloomstep.AggregateWriter`, same token as the daily aggregates
step in `.github/workflows/aggregates.yml`) runs one bounded step:

1. **Observe** – reads the foundation `website_daily` counts (`/api/team/website` source) for the last 28 completed UTC days.
2. **Block** – `no_data`, `insufficient_data` (any step rate unpublished below 50 events), unobservable or error states
   launch nothing.
3. **Prioritize** – picks the weakest published step (`landing_view→primary_cta_click` or
   `primary_cta_click→download_click`) and the first never-run catalog entry targeting it.
4. **Launch** – writes an immutable, hashed experiment instance (hypothesis, primary metric, control/candidate IDs,
   start/end, minimum sample per arm, harm-look schedule, allocation, attribution version, policy hash).
5. **Evaluate** – only at pre-registered looks: up to 3 interim **harm-only** looks (Bonferroni-bounded, one-sided
   α=0.001 each, can only stop for harm, never promote) and one fixed-horizon two-sided α=0.05 final analysis after
   `endAt` (efficacy is never tested before then).
6. **Conclude** – `promote` (candidate artifact), `retain_control`, `rollback_harm`, or `insufficient` (cells below
   the minimum count are reported, never tested); then the next eligible experiment may launch.

## Unit, assignment and consent

- Unit: **one consented page visit** (random `subjectId` created after consent; a reload or new tab is a new unit).
  It is not a stable person, so results are about visit-level CTA/download clicks only. Repeat visits by the same
  person make any user-conversion causal claim invalid; reports say so.
- Assignment: `sha256(experimentId | subjectId)` bucket against the frozen allocation; recomputed independently in
  acceptance. No fingerprinting, no PII, no cookies beyond the existing consent flag, DNT/GPC block all requests.
- Exposure must be persisted before any outcome is accepted; outcomes without exposure are rejected.
- Consent withdrawal calls `/api/web/experiments/forget`: the visit record is deleted and replaced with a tombstone
  so late queued exposures/outcomes return 410 instead of recreating it. Subject records expire after 90 days.
- Caps fail visibly: 120 admissions/minute, 429/503 surfaced; client falls back to the standard page.

## Catalog (finite, curated, low-risk)

Truthful copy/layout variants only: `download-heading-v1`, `hero-cta-label-v1`, `hero-note-position-v1`. No
auth, installer, security, consent, payment, pricing, urgency, streak or scientific-claim changes; a banned-claims
lint enforces this in tests. Growth utility is measured by downstream download intent, not clicks alone; the
account AARRR report (`docs/aarrr-dashboard.md`) remains the activation oracle and is never joined to visits.

## Isolated acceptance (the runnable proof)

```powershell
node tool/experiment_acceptance.mjs --out <dir>
```

Real Edge/Chrome (puppeteer-core) → real HTTP handlers → file-backed store → restart → evaluation → build-time
promotion artifact → next experiment → harm rollback → kill switch → production-segregation and audit export.
Writes `acceptance-receipt.json` (hash printed as `RECEIPT`), `acceptance-gate-check.json`,
`acceptance-report-export.json`, `candidate-promotions.isolated.json` and screenshots. Exit code is nonzero on any
failure.

Honest input labeling: the foundation caps synthetic ingestion at 100 lifetime events, below the 50-per-step
publication floor, so the tool (a) proves real HTTP synthetic ingestion is blocked as `insufficient_data`, then
(b) prioritizes from a separately labeled `__website_acceptance_fixture` partition. Visit outcomes for the
statistical scenarios are simulated with known rates through the public HTTP endpoints. None of this is customer
data, and no paid or billable resource is used.

## Promotion boundary

Winners never change the live site directly. Production promotion status is `pending_build_via_draft_pr`: a
reviewed draft PR edits `site/experiment-promotions.json`, which `site/build.mjs` validates and applies to
`index.html` at build time (idempotent). Isolated runs only write `candidate-promotions.isolated.json`.

## Enabling production (not done)

1. Run the acceptance tool on the exact deployed SHA; keep its receipt.
2. Set app settings `BLOOMSTEP_EXPERIMENTS_PRODUCTION=enabled` and
   `BLOOMSTEP_EXPERIMENTS_ACCEPTANCE_SHA256=<receipt hash>`.
3. An admin POSTs the receipt to `/api/team/experiments/acceptance`; the server parses it against a fixed schema
   (isolated, synthetic-only, ≥6 passing scenarios, zero costs, matching policy hash) and recomputes the hash.
4. Update the `#experiment-disclosure` paragraph in `site/index.html`, which currently says page tests are off.
5. The daily aggregates workflow already calls the tick; while disabled it returns `status: disabled`.

Kill switch: `BLOOMSTEP_EXPERIMENTS_DISABLED=1` (no storage access) or admin
`POST /api/team/experiments/kill {"killed":true,"reason":"..."}`.

## Audit, retention, export

`GET /api/team/experiments` (admin): settings/gate state, active definition (counts withheld while running), last
50 concluded results, and up to 500 audit entries (`launch`, `harm_look`, `promote`, `rollback`, `retain_control`,
`no_launch`, `kill`, `acceptance_verified`) with no visit identifiers. The dashboard's `dashboards.aarrr.experiment`
stays `eligible:false` until verified exposure evidence exists.

## Known limitations

- No real traffic has been randomized; nothing here demonstrates real-world lift.
- The PR26 zero-click installer candidate was Defender-quarantined (`Behavior:Win32/DefenseEvasion.A!ml`) and
  withdrawn; real install/launch validation remains blocked and is excluded from this loop and its acceptance.
