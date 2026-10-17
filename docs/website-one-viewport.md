# Approved one-viewport website and staged copy trials

Owner approval on 17 October 2026 selected **A as the baseline**, with B and C tried through real staged experiments. The production implementation is `site/index.html`, not the static proposal selector. The original `proposals/one-viewport/` directory is retained as historical design-review material, not the deployed page.

## Website contract

At 1920×1080 and 1366×768 CSS viewports, the first screen includes the Windows habit-app value proposition, routine → tiny action → celebration example, garden/no-broken-streak distinction, download-intent button, owner-test restrictions and optional measurement control. Narrow/zoomed/short windows reflow and scroll; content is not clipped to force a fold.

The download-intent button goes to the existing `#download` preview details, not directly to an installer. Only the subsequent designated-owner-test link starts a download. This preserves two distinct funnel stages: **intent to review preview details** (`primary_cta_click`) and **click on an actual release file** (`download_click`). Neither is completed transfer, installation, activation, satisfaction or habit success. No general-customer release is authorized. Preview.14 URLs/checksums/size, unsigned status, sign-in/age requirements, installation warnings, privacy/support details and receipt export remain unchanged.

Below the first screen: source-linked B=MAP, Anchor–Behavior–Celebration and a bounded discussion of context/repetition research. The original illustrative UI is labeled a concept, not shipped-app screenshot evidence or customer data. No testimonials, counts, endorsement, fixed habit deadline or app-efficacy claim.

## Copy and trial order

| Stage | Control | Candidate |
| --- | --- | --- |
| `hero-pair-b-v1` | A: “Build a habit small enough to start today.” / “Download Windows preview” | B: “A tiny habit. A little more you.” / “Get the Windows preview” |
| `hero-pair-c-v1`, only after the first concludes | Same A, never the winner of the first trial | C: “Make room for one small habit.” / “Try the Windows preview” |

These test **whole copy pairs**, not independent headline/CTA effects. Exactly one experiment can be active. The original three catalog entries remain readable for audit/build compatibility but cannot be newly selected. There is no customer variant selector, URL override or simultaneous A/B/C.

Nonconsenting, privacy-signaled, disabled, killed, no-active-experiment, failed-definition and unavailable-exposure visits retain/restore A. A statistical “promote” result is evidence only (`evidence_only_baseline_a_retained` in production), not a public fallback change. Build-time pair promotion is explicitly rejected. Another owner-reviewed change would be required after both trials to replace A.

## Enrollment and integrity

Existing consent stays default-off and memory-scoped, but its explicit label is now discoverable on the first screen. DNT/GPC still disable sending. A reload/new tab is another visit, not a stable person.

The v2 definition includes both strings and the frozen statistical design in its hash. Both nodes must match a complete reviewed pair before either is changed; mixed/stale markup fails without a partial mutation. The client verifies the entire instance against the bundled catalog, including exact horizon/looks/environment. Server hashing independently verifies the arm.

After a rendered animation frame, **both headline and CTA text must be fully in the visible viewport** before exposure is submitted. A hidden tab or offscreen copy is not counted as an exposure. On mobile, opting in below the hero does not itself certify the heading was read: the visitor must return to the visible pair within 15 seconds or the enrollment is cancelled and A restored. No forced scroll or outcome backfill. This deliberately excludes unexposed visits rather than manufacturing exposure.

No outcome is accepted before the server persists exposure. CTA/download outcome writes are serialized to avoid concurrent count-CAS conflicts. Application/exposure failures restore A, attempt removal of an unconfirmed visit record and show an explicit status; confirmed `applied:false` records remain eligible for the application-error safety guardrail (never outcomes) until explicit withdrawal. Downloads remain ordinary independent links. Consent withdrawal aborts pending enrollment, restores A and tombstones/removes the visit contribution, blocking late exposure/outcome writes. Page navigation resets local state without treating normal navigation as explicit withdrawal of already committed evidence. No cookies, local/session storage or fingerprinting are introduced.

## Gates are not loosened

The production loop remains **OFF unless all existing evidence/settings gates are met**. New policy v2/hash means a v1 receipt cannot authorize enrollment.

- Existing `BLOOMSTEP_EXPERIMENTS_PRODUCTION=enabled`, matching `BLOOMSTEP_EXPERIMENTS_ACCEPTANCE_SHA256`, admin-verified isolated acceptance receipt, operational permission and kill-state checks remain mandatory.
- The last 28 completed UTC days must publish both website funnel steps: at least 50 events in each relevant stage. Unknown/suppressed cells do not become zeros.
- Each trial still has a fixed **14-day** horizon, **400 exposed visits/arm minimum**, at least 10 observed/expected successes/failures, 50/50 deterministic assignment and no early efficacy decisions.
- The two planned comparisons now each use **two-sided alpha .025** (Bonferroni family bound .05). This tightens, not weakens, the original .05 per-trial gate. Three harm-only looks remain at fractions .25/.5/.75, one-sided .001 each; they cannot declare benefit.
- The returned `ci95` remains an **unadjusted descriptive per-comparison 95% interval**, not a family-adjusted decision boundary. Decisions use the registered .025 p-value threshold.
- Private console/Admin reports retain active-count withholding, low-count privacy suppression, audit limits and separation from account AARRR. Visits are not people; repeated visits and opt-in selection limit causal/general-population interpretations.

At 100 visits/week, these gates will normally prevent launch or yield insufficient data. Do not shorten the horizon, lower sample/privacy floors, silently extend enrollment or select the biggest percentage. The owner approved trying all variants **when eligible**, not forcing a winner or weakening consent.

## Acceptance and activation

```sh
npm ci --prefix api --ignore-scripts
npm ci --prefix site
npm --prefix api run check
npm --prefix api test
npm --prefix site test
npm --prefix site run build
CHROME_PATH=/usr/bin/google-chrome EVIDENCE_DIR=/tmp/approved-website node site/verify-one-viewport.mjs
CHROME_PATH=/usr/bin/google-chrome node tool/experiment_acceptance.mjs --out /tmp/staged-copy-acceptance
CHROME_PATH=/usr/bin/google-chrome EVIDENCE_DIR=/tmp/public-launch node site/verify-launch.mjs
```

Use a fresh external output directory for source-bound acceptance. `verify-one-viewport` runs real isolated experiment handlers and file-backed persistence, exercises both arms of both staged pairs at both desktop sizes/themes, verifies pre-consent A/no API calls, actual visible exposure, outcomes after exposure, withdrawal, DNT/GPC, mobile/zoom reflow and no-JavaScript links. It never contacts production or downloads an installer. `experiment_acceptance` additionally simulates sufficient cohorts through HTTP, restart persistence, final evidence, harm rollback, kill, privacy suppression, segregated production-off state and real private-console readback. Synthetic evidence is not customer efficacy. The Customer acquisition site workflow preserves the rendered evidence as an artifact; existing composed acceptance remains in CI.

**Exact next action if blocked:** satisfy all required PR/protected-runner checks without bypass, merge the approved website implementation only when permitted, let the existing main deployment complete, then verify the served baseline, preview.14 links and public experiment config. Before any activation, run the acceptance tool on the exact deployed source, retain the new policy-bound receipt/hash, configure/verify it through the existing admin gate, review and update the off-state disclosure, and confirm qualifying real consented traffic and operational permission. Then a worker tick may launch A/B; A/C follows its terminal result. If sufficient traffic or verified policy evidence is absent, deploy/retain A with trials **pending**, not falsely “running.”

The website release must not change the preview15 branch/PR48, installer promotion rules, protected runner gate, or the separate default-off GrowthBook app adapter. No cloud settings or new services are introduced by this change.
