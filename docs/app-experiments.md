# App experience experiments: GrowthBook

**Owner decision:** "lets use growthbook and make it easy to switch out in the future".
GrowthBook is the selected provider, superseding the initial custom app assignment/evaluator proposal.
Status: **default OFF, production-ineligible; hosted GrowthBook integration/analysis pending**.
Capability-building is not collection consent or permission to activate variants.

## Small replaceable boundary

The UI uses `ExperienceResolver`: `resolve(surface)`, `rendered(assignment)`, `outcome(assignment, outcome)`,
`followup()`, `changes` and `remainingEnrollment`. `ExperienceCopy` owns post-frame exposure and
`builder(context, copy)`/`onAssignment(assignment?)`; callers retain semantic headings, layout and actions.
`ExperienceExperiments` adapts existing consent/storage/outbox. Its `ExperienceAssignmentProvider` dependency
is replaceable; the default `GrowthBookExperienceProvider` contains all SDK-specific mapping.
Provider-switch tests use a fake; changing providers within an existing consent epoch fails closed instead of
rebucketing an exposed unit. There is **no custom app bucketing/statistical promotion fallback**.

Dependency: official [`growthbook_sdk_flutter`4.4.0](https://pub.dev/packages/growthbook_sdk_flutter),
MIT, from [`growthbook/growthbook-flutter`](https://github.com/growthbook/growthbook-flutter).
Package/docs explicitly list Windows, Linux, macOS, mobile and web. The lockfile pins resolved transitive
dependencies, including Dio, equatable, json_annotation, pointycastle, shared_preferences, tuple, quiver
and logger. Generated platform registrants reflect shared_preferences. Local Windows Dart/Flutter tests
exercise the real SDK evaluator; this is not a packaged-installer or live hosted compatibility claim.

The adapter uses the SDK's public `GBContext`, `GBExperiment.fromJson`, `GBUtils.initializeEvalContext`
and `ExperimentEvaluator` with bucketing hashVersion2. It evaluates a finite, frozen inline configuration
locally. It does **not** initialize SDK CDN fetching, remote evaluation, cache, streaming, sticky store or
tracking plugins. Only a random consent-scoped subject is supplied; never account/email/habit content.
SDK tracking callback is a required no-op: **evaluation is not actual-render exposure**.
No client secret, project/key, new account, vendor upload or network request is introduced.

## Supported slice and safe lifecycle

`shared/experience-experiments.json` is the hash-bound catalog/design; generated Dart/Node modules agree.

| Surface | Control | Candidate |
| --- | --- | --- |
| Invitation heading | A little growth, together | Share a small beginning |
| Garden prompt | A little is enough. | One tiny step is enough. |

The visual workstream owns invitation/chrome UI wiring; this foundation does not claim app-wide coverage.
GardenStore records task completion after a real planting save. Invitation callers may record link copied,
QR rendered or composer/panel requested as task completion, **not delivered**. Existing `share_initiated`
is unchanged. Closing normally does not imply burden. Other surfaces, notifications, cross-device joining
and delivery measurement are deferred. Consent/security/destructive/privacy choices and accessibility fixes
are invariant, not variant dimensions.

Every change assesses telemetry coverage: necessary allowlisted observations, or justified **no new events**.
No blanket mandatory collection. Optional product telemetry remains OFF until explicit consent.
Guests are ineligible. The unit is a random **consented installation inside one account/consent epoch**,
not a person. Scope state is local, never synced or joined to guest/web identity. SDK assignment stays stable
across SQLite reopen using the same subject/frozen seed. One study/config/provider per epoch avoids competing
assignments. Missing/invalid/stale/future/expired config, clock regression, kill or missing provider result
returns noncollecting control. Transport/provider exceptions surface and the widget restores control.
Enabled production config requires a source-reviewed checksum, currently empty; test configuration requires
`BLOOMSTEP_TEST_BUILD=true`.

Resolve creates no event. Mounted visible post-frame render persists exposure before returning an outcome
handle. Offstage/noncurrent route/nonresumed lifecycle/disabled ticker/outside-viewport do not qualify.
This is not eye-tracking/full occlusion detection. Outcomes are idempotent per category; generic `track`
cannot forge experience observations. Consent/account/config changes invalidate old handles and restore control.
The closed event contains study/arm/policy/config version, random cohort/epoch, bounded outcome and platform;
no name/email/recipient/habit/free text. Existing SQLite outbox, `SyncService`, authenticated Azure Functions
`/sync` and account-partitioned Cosmos storage are reused.

## Useful outcome and evidence policy (analysis not yet configured)

Primary proposed metric: effective saved voluntary did/didMore practice within7days after actual exposure.
Not clicks, dwell time, planting count, invitation volume or addictive retention. Followup is observed only
on a return at day7–14; absence is **unobservable**, not abandonment. Original saved timestamps and latest
effective habit/local-day results are used; undo/notToday is not practice. No private habit identifier is
included in experience events. This client-derived indicator is not independent server proof.

The frozen plan requires28day enrollment +7day followup +7day lateness, one day42 final efficacy look, no
interim winner selection and multiplicity accounting for the two finite studies. The50-owner display floor
is privacy suppression, **not power**. Proposed minimum2000/arm comes from maximum Bernoulli variance.25,
alpha.025/study and normal approximation ceil1902/arm for80% power to reject zero lift at true5point lift.
It does not provide80% power to prove a5point practical lower bound; roughly10points true lift would be
needed for comparable power under those assumptions. Missingness/clustering can invalidate the approximation.

Before activation, configure/verify these choices in GrowthBook's analysis, including uncertainty and
task/error/burden/opt-out/accessibility guardrails. Proposed practical primary bound>5points; task no worse
than-2points; error/burden/opt-out no worse than+1point, with simultaneous uncertainty accounted for.
Missing/stale/late/duplicate/unexposed/withdrawn/contaminated records must not enter eligible denominators.
Multiple installation units per account are not independent people. Missing followup and incomplete guardrail
capture block a winner. In particular current opt-out/burden capture is not an unbiased complete remote
denominator; telemetry is not sent after withdrawal. These are **unmet production gates**, not implemented
GrowthBook statistical settings.

The API reports only privacy-suppressed observation status: `provider=growthbook`, `decision=inconclusive`,
`growthbook_analysis_not_connected`. It runs no custom app efficacy test/promotion.
Future decisions must retain provider/config/plan/input/evidence provenance and reversible control rollback,
and pass existing reviewed build/release gates. No automatic production deployment or release is authorized.

## Withdrawal and retention

Turning optional telemetry OFF invalidates handles, removes local scope/queued observations, and queues
`experienceEvents` deletion for the random epoch. Existing authenticated deletion-first sync runs even while
telemetry is OFF. Only that account's experience events in that epoch are purged; unrelated telemetry/garden
records are preserved. Reconsent creates a new random epoch.
The existing server deletion ledger commits a minimal replay marker before bounded cleanup, invalidates
aggregate snapshots and suppresses stale/offline replay. Lost acknowledgments retry the same marker after
restart. Offline withdrawal cannot promise immediate remote purge. Existing ledger caps, minimal audit/replay
evidence and raw-event396day physical retention remain; full account deletion is unchanged.
Approved production disclosure/configuration is still required. Any future warehouse/export must propagate
withdrawal/tombstone filtering; local purge alone is not a promise to erase future third-party copies.

## Hosted setup and data-source blockers

No GrowthBook project/environment/client configuration exists in this change. Local SDK evaluation is real;
**hosted flags, ingestion, statistical analysis and winner promotion are not connected**.
Required setup, with separate scope/approval as applicable:

1. Owner-approved GrowthBook deployment/project/environment and client-side feature configuration, with fixed
   IDs/variation keys/seed/allocation matching this contract. Add validated, bounded-expiry configuration
   transport behind the adapter, keep last-known expired/malformed/network-failed config control, and preserve
   the source kill switch. A public SDK client key is not a server/admin secret; no privileged credential in app.
2. An approved analysis data source and read-only exposure/outcome queries. Map random epoch+cohort to unit,
   study/config to experiment, arm to variation, `rendered` to exposure timestamp, `followup` to observed
   denominator, `practice` to seven-day useful outcome and task/error/burden to guardrails. Apply withdrawal
   ledger, account deletion, dedup, attribution/window and contamination rules before export/analysis.
3. Configure GrowthBook metric definitions, stopping/multiplicity/uncertainty, power and guardrails; obtain
   source-bound auditable decision evidence before any best-kept change through reviewed promotion.

[GrowthBook warehouse docs](https://docs.growthbook.io/warehouses) list SQL/analytics connectors, including
SQL Server, but **not a verified Cosmos DB connector**. Existing Cosmos data/report JSON does not magically
become a GrowthBook warehouse. A separately designed approved export/connector or managed warehouse would be
needed; none is provisioned, no credentials/transfers authorized, no zero-cost assumption made.
Current account aggregates suppress small cells and lack unit-level exposure/outcome joins; they cannot
substitute for the analysis input. [Metric/fact-table setup](https://docs.growthbook.io/app/metrics) is pending.

## Existing website boundary

The deployed default-off web visit framework in [experiments.md](experiments.md) remains unchanged.
Its page-visit subject, exposure-before-outcome HTTP ledger, tombstones, scheduled worker, finite web catalog
and build-time promotion artifacts differ from the app contract. Replacing only its hash would create
competing assignment/analysis systems and invalidate existing acceptance. Web migration is **deferred**, not
claimed complete: replace `site/experiment-client.mjs` plus API config/assignment/policy/worker and analysis
input mapping together, version visits/receipts, preserve consent/forget/kill boundaries, and rerun composed
browser→HTTP→restart→outcome validation before separate reviewed deployment. No web deploy is included.

## Runnable isolated evidence and decision history

```powershell
pwsh -NoProfile -File tool\verify_app_experiments.ps1 -EvidenceDir <fresh-directory>
```

Real official SDK local fixture evaluation and fake-provider swap tests; SQLite/service/outbox→authenticated
loopback HTTP→file-backed store/restart; actual-render widget callbacks; effective saved practice; epoch purge,
lost acknowledgment and retry. Receipts bind source/policy/evidence hashes and explicitly label synthetic
identity/timestamps. No statistical fixture, customer efficacy, hosted GrowthBook, installer or release proof
is implied. Visual owner supplies composed invitation/chrome evidence separately.

Historically no formal build-vs-buy ADR or owner custom-platform decision was recorded. Custom code grew from
reuse/$0/privacy/review-gate constraints; those never proved vendors unsuitable. The owner has now selected
GrowthBook. Preliminary vendor research is no longer a selection ambiguity. We still own consent/retention,
data-source correctness, statistical plan/missingness, SDK lifecycle, auditability and operational rollback.
The small interfaces isolate replacement; no homegrown analytics/promotion platform is being expanded.
