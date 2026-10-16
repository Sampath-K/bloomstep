# Bloomstep product contract (Flutter v0.4)

This is the public implementation contract for the approved Windows-first
Flutter v0.4 MVP, with the customer outcome and product priorities below clearly
identified as hypotheses where they have not been validated. The older PWA/Tauri
install, push and AI proposals are superseded. No private account details,
subscription identifiers, identity secrets or Store research belong in this
repository.

## Origin and decision status

The initial requests combined helping people build habits with the owner's
separate learning about application distribution. On 3 October, the assistant
expanded those requests into a broad capability specification; on 4 October,
the owner requested a Windows-first implementation and one complete,
verifiable customer job per iteration. This repository's current implementation
contract is Flutter v0.4. These decisions explain how the spec evolved; they do
not establish customer demand or behavior change.

On 12 October 2026, the owner approved this first-customer hypothesis, central
job and spec-first refinement direction: adults who have abandoned habit
trackers because goals felt too large, tracking felt burdensome, or missed days
felt like failure. This is a hypothesis for validation, not a researched
customer segment, medical diagnosis or therapeutic promise. Screen wording,
journey details and proposed research are review inputs, not claims about the
current build or newly approved implementation requirements.

Developer distribution research (installer, Store and platform choices) is a
separate workstream. It must not add unnecessary steps to or substitute for
validating the customer journey.

## Habit-first profile

The first plant-a-habit screen is the only profile/account entry point. There is
no separate sign-in screen or garden Back navigation. Planting stays primary.
Signed-out users can save into `device-guest.sqlite`, scoped to the installing OS
user, with analytics disabled and no cloud sync. This is a local device garden,
not a fabricated authenticated identity. It is not encrypted account storage;
anyone with access to the same OS user can see that device garden.
Legacy installers' separately opted-in, expiring local receipts may still record
the first rendered signed-out sign-in affordance as `signin_view`; this is not
guest/account analytics, authentication success or automatic account linking.
No receipt means no measurement. The receipt can be cleared in profile Settings.

Sign-in keeps the configured Microsoft personal/Google/other hosted choices in
the trusted system browser. The signed-in profile shows an avatar and Sign out,
not identity text. Validated token claims supply initials/accessibility or an
existing HTTPS OIDC picture; absent claims are not invented. No extra photo
scopes, account connection or persistent photo storage are added.
The profile also owns the Settings/privacy entry for export and deletion.
Existing account-hash SQLite ownership, authenticated offline deadline,
consent and sync boundaries remain unchanged. Sign-out warns about unsynced
account data and clears account-local data/authentication before returning to
the separate device garden. Session expiry preserves the saved account garden
but removes access and returns to the device garden.

**First-pass boundary:** device habits remain separate when signing in; a one-time
notice states that nothing was transferred. No import, linking or migration
occurs. A future "Bring them / Keep separate" flow needs explicit consent,
idempotent local import, rollback and failure tests before enabling it. This
contract does not itself establish released-build or installed-launch acceptance.

## Human-centered garden design and validation

**Purpose:** Help people practice useful tiny habits voluntarily, eventually with
less app support. Engagement is useful practice and autonomy, not time in app,
compulsive checking, streak preservation or guilt. A prettier screen or higher
expert score is not evidence of improved retention or habit outcomes.

**Principles and guidelines (all existing and new surfaces):**

- Give each view one clear primary decision/action. Use short welcoming labels,
  consistent navigation and accessible progressive disclosure for secondary
  explanation. Never hide permissions, recipients, shared fields, irreversible
  effects, data boundaries or recovery actions behind illustration or disclosure.
- Use original garden/plant imagery and existing semantic design tokens. Reuse
  `PlantArt`; decorative growth is not earned practice/progress. Compact prominent
  image-and-text actions retain readable labels, meaningful tooltips, hit areas
  and discoverability; do not replace task names with ambiguous icons.
- Use purposeful finite micro-animation for orientation/action feedback, never
  ambient motion that competes with a task. Respect both app and OS reduced-motion
  settings with an equivalent static state. Loading, hover, focus, pressed,
  disabled, success and failure must remain understandable without animation.
- Preserve keyboard order, visible focus, Enter/Space activation, Escape/cancel
  and focus restoration; provide headings, names, roles and live feedback for
  assistive technology. Check Narrator, light/dark/high contrast, 200% text,
  small windows, Windows snap/resize and mixed-monitor DPI. Color, motion,
  hover and decoration are never the sole carrier of meaning. Scroll must keep
  all content/actions reachable without horizontal clipping.
- Keep typography, spacing and hierarchy consistent. Never block the UI on
  network/storage work; show honest pending/error/retry/offline states and
  distinguish queued/requested/cached from received/delivered/fresh. Destructive
  actions require explicit informed confirmation; cancellation has no side effect.
- Use native capabilities only when they improve the current task and are
  supported by the packaging. Share/composer/file-picker/deep-link actions remain
  explicit; reminders/tray/startup retain opt-in, quiet hours and exit semantics.
  Missing integrations are named gaps, not a reason to request new permissions.

### Anchored quality scores and minimum bars

Use the same five dimensions for **every affected surface and state**:
discoverability/next action (D), hierarchy/cognitive load (H), coherent garden
imagery/emotional tone (G), accessibility/responsiveness (A), and feedback,
recovery/trust (T). Each score is an **expert heuristic assessment**, with source
and rendered evidence, not a numeric usability certification.

| Score | Anchor, applied separately to each dimension |
|---|---|
| 1 | Unusable, misleading or critical task blocked. |
| 2 | Major friction or a material accessibility/trust defect. |
| 3 | Usable for observed conditions, with notable documented gaps. |
| 4 | Polished within the declared matrix and meets the defined checks. |
| 5 | Exceptional refinement supported by independent task/accessibility evidence, not author opinion alone. |
| NOT OBSERVED | No reliable rendered evidence for this condition; an open gate, not a pass or an averageable zero. |

**Target bar:** each applicable dimension on every changed surface is >=4/5;
there is no compensating average. A critical accessibility, privacy, data-loss
or core-task blocker fails regardless of other scores. Preserve any evidenced
baseline >4; lower scores require an explicit, reviewed tradeoff (never a
waiver of a safety/privacy blocker). Unknowns remain open acceptance gates.
Scores must name viewport/text scale, motion, input method and state; do not
generalize a desktop screenshot to Narrator, DPI or 200% text.
The current per-surface scores, evidence and gaps are maintained in
[`visual-quality-review.md`](visual-quality-review.md), not declared achieved
by this policy. State-specific acceptance is in
[`invitation-dialog-contract.md`](invitation-dialog-contract.md).

### Mandatory per-change validation / Definition of Done

1. Inventory affected routes, dialogs, transient and empty/loading/error/offline/
   success states; include native handoffs and cancellation, not just happy paths.
   Capture measurable interaction/layout contracts and failing regression tests
   **before** implementation.
2. Compare actual rendered before/after surfaces where baseline is observable.
   Record source revision, synthetic versus real data, viewport/text scale,
   motion/input conditions, exact checks/results and limitations. Never award an
   unobserved state an inferred grade. Inspect the images, not just file counts.
3. Exercise keyboard/focus, labels/live regions/targets, 200% text and short/narrow
   windows; light/dark/high contrast and reduced motion; error/retry, cancellation,
   destructive consent and privacy boundaries. Run the smallest relevant
   interaction/accessibility tests plus static analysis, extending coverage for
   the real risk. Narrator and native DPI/OS behavior need actual native evidence.
4. Preserve existing measurable performance targets: check-in celebration
   **<300ms**, desktop cold start **<2s**, vector rendering **<16ms** (see
   Nonfunctional below). Record hardware/build/method and measured results before
   claiming attainment. Widget pump durations do not establish device latency,
   frame budgets, cold start or release-build performance. Missing measurements
   are explicit gates; do not invent achieved numbers.
5. Maintain per-dimension/per-surface no-regression scores and evidence links in
   the review. Explain any lower baseline or unresolved target; separate heuristic
   assessment, functional tests, synthetic rendered evidence, native observation
   and real-user/experimental outcomes. Assess telemetry necessity for each
   change: reuse approved consented events or justify no new events; no ad-hoc
   identifiers/free text. Experiment policy is owned separately in
   [`app-experiments.md`](app-experiments.md); proposed/disabled experiments are
   not measured outcomes.
   The selected app experiment provider is **GrowthBook**, behind a replaceable
   vendor-neutral resolver/adapter. UI code depends only on the existing
   resolve/rendered/outcome contract, never vendor SDK/configuration types.
   Consent, privacy, expiry, control fallback, actual-visible-render exposure and
   quality bars are provider-independent invariants. Selection/source wiring is
   not a configured hosted integration or permission to activate a study.
6. Review only when changes are persistent, related documentation is updated,
   required checks pass and remaining gates are explicit. An unobserved native
   capability or missing real-user result cannot be relabelled "verified" merely
   by documenting it. No release, flag activation or Store certification follows
   from a visual PR.

Authoritative platform references (guidance, not certification):
[Windows accessibility](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview),
[responsive design](https://learn.microsoft.com/en-us/windows/apps/design/layout/responsive-design),
and [motion in practice](https://learn.microsoft.com/en-us/windows/apps/develop/motion/motion-in-practice).

## First-habit invitation and planting

After authentication restoration and garden loading finish, an empty device or
account garden automatically opens the existing accessible, dismissible recipe
builder once per garden per app launch. Existing habits suppress the invitation;
previous visits and legacy dismissal settings do not suppress a new launch.
Cancellation does not loop within that launch.
Authentication initialization and another active route prevent interruption.
The "Plant a habit" button remains available for later visits and subsequent habits.

Anchor, Action and Celebration each have an always-visible custom text field
alongside suggestions, with the existing 200-character limit and trimmed,
nonempty validation. Keyboard Next/Done and Back preserve the current choices;
labels stay above typed values even during focus/value transitions. Cancel saves
nothing. Optional aspiration/species and celebration practice stay
optional. A successful SQLite save supplies the actual saved habit to "Your seed
is planted", which shows a 1.4-second seed-to-sprout growth preview. It never
changes the saved seed stage, blocks continuation, or appears on save failure.
App or platform reduced motion uses a static sprout with semantic success feedback.

## Outcome and trust

Help a person make one useful, tiny action fit an existing routine, feel
positive about trying it, and adapt when life interrupts. The central job is:
"When I want to change something but struggle to keep going, help me choose an
action small enough for a difficult day, attach it to a routine I already do,
and adjust it without feeling that I have failed." The action should be useful
even if the person never records it.

Product priority: success should eventually need less support from the app, not
more attention to it. This is an intended direction, not a validated or
implemented outcome.

The existing north star of habits graduated per activated user at 30/60/90 days
is a candidate outcome measure, not proof that the product is useful or that a
habit became automatic. Preserve its existing operational definitions below
until explicitly reviewed; do not treat a recorded check-in as proof of an
action, or silence as failure.

Keep evidence claims separate: implementation evidence names a revision;
usability and safety need direct functional, accessibility and privacy
acceptance; usefulness needs prospective customers using the product for their
own goals and explaining what helps or does not; effectiveness over time needs
longitudinal customer evidence with limitations disclosed. Launch gates,
identity, account separation, persistence, export/deletion, consent and the
numerical rules elsewhere in this spec remain unchanged by this product
refinement.

Before further feature implementation, review the end-to-end customer journey
screen by screen against the actual build, challenge the assumptions about
garden presentation, recording, routine anchors, sign-in, reminders and
self-reflection, and agree what evidence would change the design. This review
is the next product decision, not authorization to build proposed wording or
features, recruit participants, collect personal data, change launch gates or
spend money. No research recruitment or data collection is authorized here.

Notification opt-out, pushy feedback, early uninstall, shame-related feedback
and account deletion are guardrails. Ages 16+. Not medical advice.

Tiny first (less than 30 seconds); celebration first; autonomy; privacy by
default; coming back is a success. Plants never wilt, die, or lose a stage.
No punishment, loss-aversion streak mechanics or leaderboards. Habit text is
never sold or used for ads. AI features, if added, will be explained and optional.
Content is original, with factual attribution to behavior design research.
Do not use a third party's trademark in the product name or marketing headline.
No copied book exercises or validated questionnaire wording without verified
licensing. Self-reflection wording must not be described as clinically validated.

## Planned enhancement workstream: confident habit building

**Planned, not implemented and not part of the current owner-record-deletion
acceptance job.** Sequencing/product review is required before building this
experience. Success means useful habit-building skills and explicitly reported
confidence, not lesson completion, attendance, streaks or time in the app.

1. **Original reusable library:** author anchor moments focused on completed
   events/trailing edges, context-suitable tiny actions and optional celebration
   samples. For example, an original proposed completed-event anchor is
   "After I return my lunch container to the cupboard"; a matching tiny action
   is "I set one item ready for tomorrow"; celebration may be an optional
   quiet acknowledgment. Preserve freeform recipes and explain why specific
   completed events are easier to locate than vague times or ongoing activities.
   No copied book/course catalog, questionnaire, wording or illustration.
2. **Frictionless creation:** optional filter/prefill choices, clear editable
   previews, one small decision at a time, keyboard/screen-reader paths, and no
   forced starter or celebration performance. Original samples must receive
   contextual/safety/content review; no clinical promise or shame.
3. **Positive microanimations:** immediate action feedback and accessible
   recipe/growth/celebration transitions, without adding network work or waiting
   for animation to commit data. Reduced motion replaces movement with quiet
   static feedback; semantic success is independently announced. Default
   silent, no developer sounds; any future sound is explicitly user-controlled.
   No loss-aversion effects, manipulative attendance prompts or perf regression.
4. **Curated learning/bookmarks:** original short summaries plus author/date,
   canonical link, study type, evidence strength and limitations. Distinguish
   method claims from peer-reviewed evidence; causal/freshness claims need
   verified sources and review dates. Hosted inference and paid feeds require
   separate authorization; do not reproduce copyrighted article text.
   A "recent" label requires an actual verified
   publication date, not a generated summary.
5. **Adaptive optional education:** self-select "New to habits", "Tried habits
   before" or "Fine-tuning", with Skip/change-anytime and a manual/freeform
   route. Offer at most one optional contextual15-30-second concept/example/
   tiny application when useful, never a lesson on every launch or check-in.
   Beginner skills: identify completed-event anchor, size one action and select
   an optional celebration. Experienced skills: diagnose friction and adjust
   anchor/action/context. Advanced skills: compare timing/context and plan a
   small generalization experiment, while explaining evidence limitations.
   Progression uses demonstrated recipe skills plus optional explicit confidence
   feedback, not check-in counts or opaque personality/health inference.
   Remediation offers an explained smaller step or alternative example; inactivity
   is neutral, with no reset, shame or assumed loss of skill.

**Source-of-truth and integration:** Proposed reviewed content is a versioned
local app/source catalog (stable IDs, schema/content version, source citations,
review timestamp and suitability tags), not an isolated script. Recipe-library
entries link to learning concepts and optional bookmarks. Private account-scoped
learning preferences/progress must integrate the existing SQLite/sync/export/
owner-delete contracts, with explicit opt-in where appropriate; no inferred
health/personality data. An offline cache names its version/review age and
remains usable without claiming freshness. Remote updates require validated
schema/integrity and compatibility, preserving the freeform/offline path.
Dashboard learning events are limited reviewed enums, independently consented;
no recipe/bookmark text, confidence narrative or unconsented skill inference.

**Acceptance before shipment:** content originality/licensing/attribution and
name/trademark marketing review; stable catalog linkage/version/cache tests;
editable freeform/Skip/change-level journeys; no forced lesson or notification;
demonstrated-skill/confidence progression and neutral inactivity tests;
account/isolation/export/delete/offline/conflict tests for optional learning;
keyboard/screen reader/reduced-motion/silent behavior; measured action-feedback
latency and resource limits at least as good as existing product contracts;
telemetry consent/allowlist/revocation tests. Separately verify learning usefulness
without inventing outcome/clinical claims or a cohort.

Conceptual source pointers for later curation, not endorsements or proof of
every proposed feature: [Fogg Behavior Model](https://behaviormodel.org/) and
[Tiny Habits](https://tinyhabits.com/) describe the author's methods;
[Lally et al., 2010](https://doi.org/10.1002/ejsp.674) is an observational habit
formation study; [Gardner et al., 2012](https://doi.org/10.1186/1479-5868-9-102)
addresses habit measurement. Review exact source/licensing/evidence before
publishing any lesson, instrument or "recent research" claim.

## Platforms and budget

### Launch scope versus later enhancement scope

Launch readiness is tracked as nine finite packages in `docs/status.md`:
actual owner-only private-loop cleanup; original target-aligned metric/goal
contracts; session/native health coverage; approved multi-identity/device/
offline/recovery/erasure acceptance; selected-operator/team/referral acceptance;
authorized Windows surfaces; worker freshness/cron; production auth/legal/
controller/budget/unsigned trust; and exact release/deploy/rollback/security/
requirements/customer-UX sign-off. Package owners, next actions, dependencies
and definitions of done are authoritative there. Instrumentation/formula gaps
are engineering work, not only population blockers.

A separate elapsed-user evidence workstream retains genuine D7/D30/D90
hypotheses, original crash-free quality criterion and reviewed experiment
activation. No fabricated cohort, waived requirement or guaranteed90-day
launch wait; distinguish later hypothesis maturity from true launch safety/
quality gates and require explicit canary/production interpretation where
unresolved. New library/curated education/adaptive lessons/microanimations
remain planned outside this launch critical path. Permission for code completion
does not grant Admin, OS changes, real account erasure, another identity,
invitation sending or paid infrastructure.

Flutter Win32 first: unsigned per-user installer from the small website and
GitHub Releases, ARM64 and x64. Microsoft Store packaging later; iOS/iPadOS,
Android and macOS native builds later. No large new toolchains or paid purchases.
Unsigned downloads disclose SmartScreen/unknown publisher friction. Store
signing does not sign a web binary.

Azure Static Web Apps **Free**, managed HTTP Functions, Cosmos NoSQL free tier
(selected at creation, one per subscription, shared <=1000 RU/s and 25 GB
allowance), External ID basic free MAU allowance. No hosted model, Redis,
containers or paid notification service. No production in corporate tenants or
development-credit-only subscriptions. No automatic paid upgrade.
Budget alerts are not a hard spending cap; volume limits and a working spend
kill switch must be verified before production launch.

## Required complete loops

| Loop | Approved minimum |
| --- | --- |
| Habit | Plant without sign-in; empty device or account gardens open the dismissible three-step anchor, tiny-action and celebration picker once per garden per app launch. Five original suggestion recipes and visible custom text at each step; zero required typing; visible progress and live full-recipe preview; Back retains choices; optional aspiration and three species. Incomplete actions explain why. Celebration practice is optional, never a creation/edit gate. Plant into persistent SQLite, then show saved-recipe seed-growth feedback and a clear garden continuation, honoring reduced motion. First habit target <90s; first check-in is optional, not creation acceptance. Recommend one habit initially; soft cap three with explicit override. |
| Check-in | Did it / Did more / Not today; optional forgot/too hard/anchor absent/motivation reason; no response is no data. Personal celebration within 300ms; persistent client event IDs; one effective result per habit per **local** date; edits and undo append events; sync retries idempotent. |
| Garden | Five stages: seed, sprout at 3, sapling at 10, budding at 21, bloom at 30 practice days plus score >=4/7. No negative stage changes after rest or corrected data. Permanent Grove after graduation. Deterministic species/plant variation, vector visuals, screen-reader labels and reduced motion. Optional day/night, seasons, decor, pollinators and return celebration, never a penalty. |
| Reminders | Real Windows local toasts and tray actions; opt-in permission/context; optional autostart; chosen local time, quiet hours default 21:30-07:30; <=1 prompt/habit/day and <=3 notifications/app/day; snooze/fewer/off. Three ignored halves frequency, seven pauses with in-app explanation. Device scheduling, not paid service. Respect OS settings/Focus; never use urgent bypass. Re-evaluate local time/DST/travel. Median of last 14 check-in times after five samples, rounded 15m. |
| Identity | Real OIDC broker with Microsoft account/work-school, Google and email OTP; system browser authorization code + PKCE, unpredictable state and nonce; validate token signature/issuer/audience/expiry/nonce. Never embedded browser or fake sign-in. Provider/platform capabilities verified, not assumed. Refresh credentials in OS secure storage. Inline profile on the habit screen; separate device-only guest garden with no analytics/sync/migration. Authenticated offline sessions; per-account isolation; sign-out clears account-local device data with unsynced-data warning and returns to the device garden. No silent email-based linking. |
| Sync | Functions JWT verification on **every** endpoint, server-derived partition `/userId`, Cosmos persistent records, retry, append-event union and last-writer-wins recipe/settings with deterministic conflicts. Never accept client-selected account identity. Two-device verification including offline edits/restarts. |
| User learning | Weekly reflection under 60s; four 1-7 naturalness items every 14 days; explain deterministic Recipe Doctor based on check-in reasons (specific/reliable anchor, smaller behavior, reconsider aspiration/celebration). Two consecutive naturalness scores >=5.5 plus practice >=60% of last 28 days graduates, not a fixed day count. Original content. AI features, if added, will be explained and optional. |
| Reconnect | Gentle absence nudges at 3 then 7 days, maximum two per absence episode, then stop until return. Opt-out, ignored-reminder backoff, never guilt. Return earns a positive celebration. Windows background/tray/next-open delivery must actually be observed before claiming success. |
| Telemetry | Separate optional consent, off by default. Typed allowlisted funnel registry, offline batching/retry, no email/habit/feedback text, 13-month raw retention, deletion propagation. Acquisition/install/sign-in/activation/check-in/graduation/referral/feedback/rating/reminder health; four admin dashboards (funnel, retention, outcomes, reminder health); daily aggregates; minimum 50-user cohort. Required diagnostic/security data disclosed separately. |
| Feedback | Private in-app Idea/Bug/Question/Praise/This felt wrong form; optional diagnostic attachment consent; queued vs received distinction; my feedback statuses received/review/planned/in-progress/shipped/not-planned with reason; threaded private team responses visible after sync; role-protected audited admin console. No default public board or public free-text DMs. |
| Ratings | In-app 1-5 plus optional text, team response; prompt only first graduation/third comeback/30 practice days; <=one/120 days; never after a miss/error or gate Store reviews by rating. Store review integration only when Store-distributed. |
| Invite | Copy link, user's email client, QR, OS share sheet, opt-in recipe card; no private habit name by default. Validated web/native deep link, deferred install attribution, inviter/channel/acceptance, no spam or undisclosed automatic communication. Buddies later: private, encouragement-only, no free-text DMs, report/block. |
| Privacy | Honest trust page/processors/retention; JSON/CSV access/export; in-app local and server deletion confirmation; prevent deleted data resurrection from old devices; analytics deletion; optional exit survey. Account/provider deletion boundaries explained. Never publish exports/secrets. |
| Experiment | Versioned remote config, validated bounds, deterministic hash bucket, **one** reminder-copy A/B with guardrails, kill switch and human review before expanding. No "live" claim without deployed observed data. |
| Release | CI on every push; client and API tests/build; native installer install-launch-upgrade-uninstall evidence for both architectures; downloadable artifacts with checksum and changelog; update detection, signed/verified staged install later before automatic update claims; feedback closure linked in release notes. No shell/local demo called full MVP. |

## Architecture and implementation decisions

SQLite via `sqflite_common_ffi` replaces the proposed Drift generator: the app
uses parameterized transactions and explicit migrations without generated code.
Flutter `CustomPainter` provides original vector plant art instead of a Rive
asset/license dependency. These are implementation choices, not scope cuts.
Public account IDs are hashes of the **exact validated issuer and subject**,
not email. Check-ins retain local date independently of UTC audit timestamps.

Website is static HTML (landing, trust, invitation fallback, changelog,
role-protected API console). Temporary GitHub Pages hosting is permissible for a
clearly labeled preview; Azure SWA remains the production target. Native
credentials are never exposed to website JavaScript. No unauthenticated data API.

Future AI is on-device only behind a Dart interface, never a hosted fallback.
Future mobile stores, paid membership/cosmetic choices, buddy gardens, native
widgets, wearable surfaces, Growth Bites and seasonal content are deferred.
Free core remains independent of any monetization.

## Non-functional release gates

Check-in celebration <300ms; desktop cold start <2s; vector render <16ms target;
crash-free sessions >=99.5%; keyboard/screen reader/large text/reduced motion,
WCAG 2.2 AA; offline-first checks; TLS; real role checks; no secrets in git.
Localization structure from day one; English first, translations later.
Trademark/name, outside-activity, privacy/legal and Store policy review are
human launch gates, not assumed approvals from compiling code.

## Method and references

Fogg Behavior Model: motivation, ability and prompt. Tiny step anchored to an
existing routine, followed by celebration. Optional swarm/focus-map/curated
tiny-izer library grows beyond the five initial recipes later.
Criteria-based graduation acknowledges that habit development varies widely.

- Fogg, *Tiny Habits* (2019); https://behaviormodel.org
- Lally et al. (2010), *European Journal of Social Psychology* 40(6), 998-1009.
- Gardner et al. (2012), SRBAI research, *IJBNPA* 9:102 (licensing verification
  required before reproducing instrument wording).
- External ID identity methods: https://learn.microsoft.com/entra/external-id/customers/concept-authentication-methods-customers
- External tenant ARM contract: https://learn.microsoft.com/azure/templates/microsoft.azureactivedirectory/ciamdirectories

Implementation evidence and unresolved gates: [status.md](status.md).
