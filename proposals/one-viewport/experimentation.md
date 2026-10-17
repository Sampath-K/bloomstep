# What website experimentation actually does

**Inspected 17 October 2026, main `a778a66560b8a7b3ee9449d8e00af876c41461ec`. Production experimentation is implemented but OFF, not a running optimization service.** This proposal does not enable it.

## Evidence and scope

The named branches are not three separate live systems. The web funnel work merged in [#16](https://github.com/Sampath-K/bloomstep/pull/16) and [#25](https://github.com/Sampath-K/bloomstep/pull/25), the telemetry foundation in [#32](https://github.com/Sampath-K/bloomstep/pull/32), and the web experiment loop in [#34](https://github.com/Sampath-K/bloomstep/pull/34). Their implementation is present on inspected main.

The same experiments branch now has open [#49](https://github.com/Sampath-K/bloomstep/pull/49), a **default-off GrowthBook app adapter**, not a replacement already deployed on the website. Its description explicitly defers web migration and hosted GrowthBook analysis. Do not conflate that work with today's custom web evaluator.

The latest completed daily aggregate run inspected, [16 October run 38865984064](https://github.com/Sampath-K/bloomstep/actions/runs/38865984064), at the inspected main SHA, records:

```text
2026-10-16T07:15:00.3292836Z Experiment tick status: disabled (production_not_enabled)
```

The current source disclosure also says page comparisons are off. A fresh direct GET to the public SWA hostname failed DNS resolution from this environment, including an independent fetch attempt. Therefore the run is timestamped production evidence, **not a fresh live API assertion or an assertion about all current cloud settings**. Anonymous website collection is implemented and opt-in; no private real counts were accessed. Static release configuration remains preview.14.

## Capability, assignment, outcomes and readback

| Question | Actual implementation |
| --- | --- |
| What varies? | Only a finite reviewed catalog: download section heading (`Current preview status` / `Preview limits and owner-test files`); hero CTA label (`Check preview availability` / `View preview details`); first hero note before/after the CTA. No arbitrary editor, hero-headline testing, visual builder, broad layout search or AI-generated copy. |
| What cannot vary? | Download destinations, installer/security guidance, sign-in, consent, pricing/payment, privacy or scientific claims. These are not allowed surfaces; a claims lint adds a second guard. This proposal's headlines are **not** registered variants. |
| Who enters? | Explicit per-visit website-measurement opt-in only. DNT/GPC block collection. The consent checkbox is currently in the lower download section, so most no-scroll visitors would never be eligible; do not treat opt-in traffic as a representative census. No experiment requests before opt-in. |
| Randomization unit? | One consented page visit, not a person. A random UUID lives in page memory. Reloads/new tabs create new units. Assignment is `sha256(experimentId + ":" + definitionHash + ":" + subjectId)`, first 8 hex digits modulo 10,000; buckets below 5,000 get control. Allocation is approximately 50/50, not guaranteed exactly balanced. No cross-visit sticky assignment or fingerprinting. |
| Exposure? | Catalog definition/hash verified against bundled policy; attempted variant application is recorded, including its `applied` flag. Server exposure must persist before outcomes are accepted. Applied failures contribute to operational guardrails; “exposure” is not proof a human read the content or that it was in view. |
| Visit outcomes? | `primary_cta_click` (secondary diagnostic) and `download_click` (primary intent metric), each counted at most once per enrolled visit. Footer primary CTA enters the anonymous funnel but only `#primary-cta` sends the experiment primary-CTA diagnostic. Home-page release-link clicks count; `/releases/` clicks are not instrumented. Not download completion, installation, first launch, satisfaction, activation or retention. |
| Other website observations? | `landing_view`, `primary_cta_click`, `download_click` go to `/api/web/events`: anonymous daily UTC event counts, bounded source/referrer/campaign labels and download architecture. A stage/architecture is deduplicated within a page epoch. These counts are not unique visitors or linked transitions; a ratio may exceed 100%. |
| Attribution? | First/last touch are currently identical within one consented page epoch. Only allowlisted referrer labels and UTM values persist; not arbitrary URLs, search queries, cross-visit acquisition or account matching. Older categories-only documentation is superseded by the telemetry foundation. |
| Later app activity? | Separate default-off app telemetry and explicit export/link of a voluntary website receipt can show ordered account-level `website_receipt_download → recipe_created → first_completion`. Requires account consent and privacy thresholds. This is **not joined to experiment assignments**, and cannot certify install/launch success or variant-level habit outcomes. |
| Where stored? | Existing Cosmos store: real/synthetic website partitions separated; experiment production/isolated partitions separated. Consented visit records expire after 90 days. Withdrawal removes that visit's experiment count contribution and replaces its record with a content-free tombstone against queued re-creation; anonymous website aggregate observations already accepted cannot be individually removed. |
| Where seen? | Private authenticated `console.html`, “Load website funnel” and “Load experiment status and history”. Admin APIs `/api/team/website?days=1..30` and `/api/team/experiments`. Website totals, steps and bounded acquisition breakdowns; experiment gate/active definition, concluded comparisons, promotion artifacts and audit trail. Running arm counts are withheld. The report retains 50 concluded results and 500 audit entries (UI shows the latest 50 audit entries). It is not a public dashboard or GrowthBook-hosted results view. |

Source: [`site/customer.mjs`](../../site/customer.mjs), [`site/experiment-client.mjs`](../../site/experiment-client.mjs), [`api/src/experiment-policy.mjs`](../../api/src/experiment-policy.mjs), [`api/src/experiments.mjs`](../../api/src/experiments.mjs), [`site/experiment-panels.mjs`](../../site/experiment-panels.mjs), [`docs/funnel-telemetry.md`](../../docs/funnel-telemetry.md). [`site/measurement.mjs`](../../site/measurement.mjs) also contains an older local-storage helper, but the current home page uses `customer.mjs`'s separate in-memory receipt flow; it is not evidence of current visitor-ID storage.

## How the loop is gated

The daily workflow requests a bounded tick. Enabling production requires `BLOOMSTEP_EXPERIMENTS_PRODUCTION=enabled`, a configured acceptance SHA-256, and an admin-submitted receipt whose hash and policy binding the server verifies. Operational pause and kill switches still apply. The isolated acceptance runner demonstrates software behavior with synthetic data, not customer efficacy.

When enabled, the tick examines the last **28 completed UTC days**, blocks if either funnel step is unpublished, then selects the weakest published step and the first unrun eligible catalog entry. Anonymous step ratios require **at least 50 events in both stages**, not 50 landings alone. Low counts, missing dates and suppressed cells are unknown, not zeros; small breakdowns are suppressed too.

A launched definition freezes a **14-day horizon**, **400 exposed visits per arm minimum**, 50/50 allocation, and a fixed-horizon two-sided two-proportion test at alpha 0.05. Both observed and expected success/failure cells must be at least 10. It checks three scheduled **harm-only** looks at days 3.5, 7 and 10.5 (one-sided alpha 0.001 per look); these cannot establish benefit or promote. There are assignment-ratio and variant-application error guardrails. Ticks are daily, so a look is processed on the next eligible tick, not necessarily at the exact half-day.

A positive final decision produces `pending_build_via_draft_pr`; it does **not** deploy the winner. A reviewed PR must edit [`site/experiment-promotions.json`](../../site/experiment-promotions.json), currently empty, for build-time application. New surfaces/copy require coordinated reviewed policy/client/API/build/test changes and a new matching acceptance receipt. Moving to this proposal's single direct CTA would also change stage semantics: one click must not be presented as two independent conversion decisions.

## Seven days, 100 visitors: what actually happens

**As configured today: nobody is randomized, no comparison runs, no winner is picked.** Some visitors may voluntarily generate anonymous website events. The 100 external visitors are not a number this implementation can independently verify as 100 unique people.

For planning only, suppose all 100 visits are independent, eligible, fully observed and in the intended audience. These are illustrative download-*click* rates, **not benchmark rates or forecasts**:

| Assumed intent rate | Expected download clicks / 100 visits | Expected / arm in a hypothetical 50/50 split |
| --- | --- | --- |
| 2% | 2 | 1 |
| 5% | 5 | 2.5 |
| 10% | 10 | 5 |
| 20% | 20 | 10 |

Expectations are averages, so a fractional expected count is not a fractional person. Completed downloads, installs and first habits would generally be fewer but are unknown; there is no measured drop-off with which to estimate them. If only 30% opted in, at a 10% click rate roughly **30 observed visits and 3 observed clicks** would be expected, not 100 and 10. Actual consent and return-visit patterns could bias that subsample.

Even if the loop were enabled:

1. With only these 100 visits and 2–20 download events, the 50-download publication floor blocks launch from a fresh history. Historical qualifying counts could change this, but none were read or assumed here.
2. If an experiment had already launched from qualifying history, 7 days is only halfway through its 14-day horizon. About 50 eligible exposures/arm is an upper-bound expectation at 100% consent, not the required 400. The day-7 look is harm-only; the likely small cells are not testable.
3. If traffic stops after those 100 visits, the day-14 final decision is **insufficient; retain control**. Do not declare “no effect.” At the same traffic rate, 14 days gives roughly 200 visits total, still only 100/arm before opt-outs. Reaching 800 total exposures takes about 56 days at 100% eligibility, but today's experiment ends after 14 days; it does not silently extend itself. Merely meeting 400/arm is an eligibility floor, not guaranteed statistical power.

To see uncertainty concretely: even a perfectly observed single-page **10/100** rate has an approximate **95% Wilson interval of 5.5%–17.4%**, before selection/repeat-visit bias. A hypothetical split of **5/50 vs 10/50** looks like a doubling, but intervals are roughly **4.3%–21.4%** and **11.2%–33.0%**; the current evaluator refuses the low cells and cannot promote. These intervals are explanatory calculations, not dashboard output or inferential evidence about actual customers.

For scale, a conventional independent two-arm plan to detect **10% → 20%** needs roughly **200 visits/arm**; **10% → 15%** roughly **686/arm** (two-sided alpha .05, 80% power, normal planning approximation, before loss/bias/multiple comparisons). At 100/week those totals take about 4 and 14 weeks at full eligibility. The current 400/arm floor would override the smaller plan, and the current 14-day cap fits neither at this traffic. No arbitrary 7-day A/B/C split or “pick the highest percentage” rule is defensible.

## Recommended design at this traffic

**Week 1 should be a single owner-approved baseline and comprehension/usability study, not an efficacy contest.** Keep today's live preview and safety gates until explicitly approved; this proposal is not permission to recruit general installers.

After visual approval and release readiness, use copy A with one clear CTA. In a future separately reviewed implementation, put a compact, equal-choice, default-off measurement control where no-scroll visitors can actually find it, without delaying or conditioning download. Keep DNT/GPC and distinguish missing measurement from abandonment. Predeclare the intent event and denominator; for a single direct CTA, measure download intent per consented page visit, not CTA-to-download as if they were independent actions. Today's proposal deliberately adds no measurement.

Recruit 5–8 consenting intended users for short task-based sessions: after five seconds, can they say who it is for, describe routine → tiny action → celebration, find the Windows CTA, and understand preview restrictions? Record misunderstandings and observed failures, not just preferences; this is qualitative evidence, not a population conversion estimate. Fix blockers and wording confusion before spending scarce visitors on statistical comparisons.

Review week-1 counts descriptively where privacy floors permit. Do not weaken privacy thresholds or enable the autonomous loop to force a result. Choose only **one** later A/B hypothesis (for example CTA clarity, with the headline fixed), pre-register baseline, minimum useful lift, sample size, duration and safety stops, and approve any policy/horizon/provider changes before enrollment. Avoid simultaneous headline+CTA changes if you need attribution to either. Do not promise in-app success from website clicks. Consider a GrowthBook web migration only as a separately coordinated decision, not something already provided by the app adapter.
