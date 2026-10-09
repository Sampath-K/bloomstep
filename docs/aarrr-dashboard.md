# Private AARRR observation dashboard

The existing private `site/console.html` now defaults to a dark executive
overview, with keyboard-operable definition, denominator, cohort and observed
gap drilldowns. **Load private AARRR overview** uses the existing authenticated
`GET /api/team/metrics?days=1..30`. No private request happens on page load.
`Bloomstep.Admin`, same-origin HTTPS, memory-only tokens, bounded reads and
explicit operator sign-in remain required. The separate website window includes
today; account reports use completed UTC dates. Neither silently substitutes
for the other.

**Load website funnel** uses the separately authorized existing
`GET /api/team/website?days=1..30`. Its source/referrer/campaign drilldowns show
first and last touch independently for landing, primary CTA and download
events. `scope: consented_page_epoch` is a single explicit page-consent epoch:
first/last are not cross-visit acquisition. Each field is an independent
marginal count, not a joint user segment. A whole dimension is withheld when
an observed cell is below 50; missing and all-null dimensions are explicitly
unknown/absent or suppressed, never zero. Legacy responses without attribution
get an explicit not-instrumented panel. The shared website loader clears
old data before requests and again on errors or malformed reports.

## Report contract and source of truth

`api/src/aarrr.mjs` computes additive, on-demand `dashboards.aarrr` version 1.
Its only join boundary is the server's pseudonymous account key. The backend
uses its existing bounded events scan and active-account / deleted-habit
ledger filter. Deleted owners and deleted-habit evidence are excluded before
computation; identity rotation never joins. No free text, account keys,
event UUIDs, habit IDs or raw records are returned in the report.

The input source is independently opted-in app events, including explicitly
confirmed receipt imports. Native `createHabit` saves the habit before
`recipe_created`; check-in events are saved in the check-in transaction.
This reports client-observed saved activity, not independent installation
attestation, payment verification, or proof of complete event capture.
The server does not infer event consent from absence or add a new consent
store. Local consent revocation/queue cleanup uses the existing app path;
already synchronized facts follow existing retention and deletion rules.

The durable SQLite/outbox -> authenticated sync -> Cosmos events path remains
the source of truth. On-demand computation indexes the bounded observations
by account and original timestamp, reuses immutable retry/conflict
normalization, and publishes only aggregate projections. Late/offline
observations can revise a later read. Persisted worker snapshot contracts
are unchanged: historical worker snapshots do not contain this new report,
and missing/stale worker records remain unavailable.

| Dimension | Measured unit and definition | Deliberate boundary |
| --- | --- | --- |
| Acquisition | Separate anonymous website event counts / allowlisted touch margins in `/api/team/website` | Not unique visitors or account attribution. Page-consent first/last touches are not a cross-visit journey. |
| Activation | Ordered distinct accounts: `signin_succeeded` -> `recipe_created` with habit UUID -> positive `first_checkin` after creation of that same habit | All stages must be observed in the selected completed UTC window. A click, recipe form view or another habit's check-in does not activate this chain. |
| Seven-day conversion | Numerator = eligible-stage accounts with next stage within seven elapsed days; denominator = all observed eligible-stage accounts | Partial opt-in observation fraction, not all customers or proof of abandonment. Cumulative bars include later observed conversions within the selected window, so they need not equal seven-day success counts. |
| Observed gap partitions | `convertedAccounts`, `pendingAccounts`, `censoredAccounts`, `laggedAccounts` sum to `eligibleAccounts` | Pending deadline is at/beyond UTC observation cutoff; censored deadline is outside selected historical window; lagged means no next observation within seven days. Missing/unlinked/capped facts may explain any gap. |
| Retention | First observed ordered saved activation in bounded history; D1/D7/D30 effective positive practice on exactly reported local cohort date + offset | Not lifetime acquisition, rolling retention, timezone-adjusted population maturity or guaranteed complete capture. Latest timestamp/UUID per habit/local day wins, including undo/notToday. Target date must close before UTC observation cutoff; device offset is unavailable. |
| Referral | Independent distinct-account share intent, imported invitation-link view, invitation redemption | Intent != sent/delivered; link opening != accepted. Sent invitation and sender-to-referred-activation join are unsupported. Populations are not divided into a fabricated referral rate. |
| Revenue | Unsupported / null | No verified payment receipts; no revenue zero, customer LTV or reserved purchase-event conversion. |

Publication requires at least 50 distinct contributing accounts. Small positive
disjoint stage complements suppress the cumulative chain; small positive
transition partitions suppress all its counts and rate. Small mature retention
subsets or their complements suppress the whole cohort row. Zero can describe
an observed mature eligible subset only; absent stage observations remain
unknown. `unknown`, `suppressed`, `pending` and `unsupported` are distinct UI
states. Invalid responses throw and clear prior results, never render success
zeros. There is no all-customer ingestion watermark. `observedThrough` is the
UTC observation cutoff, **not a completeness watermark**. Historical experiment
eligibility remains false without separately verified exposure/guardrail
evidence.

## Runnable independent acceptance

Run from the repository root on Windows (Node >=22):

```powershell
npm --prefix api ci --silent
npm --prefix site ci --silent
node --test api\test\aarrr*.test.mjs site\test\aarrr.test.mjs
npm --prefix api run check --silent
npm --prefix site run build --silent
$env:EVIDENCE_DIR = '<absolute private artifact folder>'
$env:CHROME_PATH = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
node site\verify-aarrr.mjs
```

The independent fixed oracle writes **150 synthetic subjects only to a
disposable, loopback, file-backed acceptance store**, never the production API
or Cosmos. This harness is not registered in production Functions. It uses
ephemeral locally signed tokens, permits only synthetic subjects, and removes
its own named temporary directory after completion. No synthetic app-subject
convention is enabled on the production collector.

Fifty subjects save recipe + positive first practice + exact D1/D7 activity;
fifty save only a recipe; fifty only sign in. Real production sync handlers
persist the observations and actual garden records. An exact retry and disk
restart must produce cumulative **150 / 100 / 50**, seven-day activation
**50 / 100 = 50.0%**, and exact D7 **50 / 50 = 100.0%** for the activated
September 1 cohort, not 50/100 or 50/150. D30 is pending and revenue null.
Erasing the fifty activated owners via the real account-delete handler,
then reopening disk, must produce **100 / 50 / unknown** and no eligible
retention cohort. The same test first erases their saved habits through real
sync deletions, verifies **150 / 50 / unknown**, and replays old offline
records without reviving erased habit evidence. After retry, persisted raw
documents must contain exactly 400 events, 100 habits and 150 check-ins.
Missing worker snapshots stay unavailable.

The composed acquisition oracle additionally sends 150 observations through
the real anonymous collector in that same disposable store (50 events per
stage, separate bounded UTC days), using allowlisted search/Google/newsletter/
email/launch touches. Disk reopen and an Admin website read must produce 50
source/referrer/campaign marginal events per stage/touch. The shared production
website loader renders those values and keyboard-operable attribution
drilldowns. The subsequent account report must remain 150/100/50 with
100 eligible recipe accounts: anonymous events cannot alter that denominator.
`synthetic:false` here exercises the collector's real aggregate partition
**inside the isolated disposable store only**, never any production endpoint.
Foundation's separate synthetic-partition exclusion tests remain required.

The browser runner reads the authenticated real HTTP report through the same
`loadAarrr` orchestration used by the production Load button (with an isolated
HTTP requester, not a production authentication bypass), and uses the
production renderer in the private console shell, explicitly marked
**ISOLATED SYNTHETIC FIXTURE PREVIEW**. Screenshots cover populated/empty,
keyboard drilldowns, 390/320px mobile, dark/light and cleared error states.
The actual production Load button is also exercised without a configured
identity: it must clear prior fixture data and label failure. This is not
a bypass of production operator authentication or evidence of live identity
acceptance. An independently injected pipeline outage returns HTTP 503 and
the shared production loader clears stale output before rethrowing.
`aarrr-receipt.json` records source SHA-256 hashes, exact oracle, checks and
these limits without private tokens or raw garden data.

Unit oracles additionally exercise duplicates/conflicting UUIDs, out-of-order
arrival, identity isolation, same-habit ordering, seven-day microsecond
boundaries/cutoff equality, historical right censoring, complementary
suppression, undo, local/UTC cohort boundaries and malformed windows.

Existing API/site regression commands remain `npm --prefix api test --silent`
and `npm --prefix site test --silent`. The existing API CI job also runs the
browser acceptance after bundling and uploads explicitly isolated screenshots
and source receipts; this introduces no deployment step.
Build regenerates ignored assets and
normalizes generated customer download blocks; those outputs are not evidence
of deployment or authorization to promote any release.

## Cost and acceptance limits

This uses existing static hosting, Functions and Cosmos read/export paths;
there is no paid analytics dependency, new service or new billable resource.
Existing preview limits still apply (200 accounts, 10,000 combined metric
records, 12 daily / 120 lifetime private metric reads); Cosmos/hosting usage
is not universally free beyond the existing grant/caps. Caps/pauses fail
explicitly rather than return partial reports.

No public deployment, merge, customer-data access, installer execution,
download promotion or security-gate change is performed by this increment.
The withdrawn PR26 zero-click candidate and native security acceptance remain
separate blocked gates. Voluntary receipt handoff is not same-installer or
same-visitor proof; missing installation and unlinked attribution remain
unobservable. Live operator access, genuine cohorts and native/customer
acceptance require their separately authorized environment.
