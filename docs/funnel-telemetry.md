# Funnel telemetry foundation (increment 1)

This is an implemented, independently testable collection foundation, not a
complete customer conversion census. Dashboard/AARRR and autonomous experiment
increments build on these contracts separately. No installer, website download
pointer, release guard, provider authentication or production resource is changed.

## Source-to-sink trace

| Boundary | Actual source/control | Persistence, transport and readback |
| --- | --- | --- |
| Website acquisition | `site/index.html` unchecked `website-consent`; `site/customer.mjs` observes consented landing, `primary-cta` and actual `[data-download]` click handlers | Same-origin `POST /api/web/events`, omit credentials/referrer. `api/src/functions.mjs` registers guarded `createWebsiteHandlers` from `website-funnel.mjs`. Cosmos `bloomstep/data` `/userId` partitions `__website_counts` / `__website_synthetic`, daily UTC count vectors and transactional budget/retry ledger. Admin `GET /api/team/website?days=1..30`, private `site/website-panels.mjs` in `console.html`. |
| Voluntary browser handoff | Separate unchecked `receipt-consent`, `receipt-export`, `receipt-clear` | Page-memory schema-v1 website receipt; `site/measurement.mjs` validates export. No attribution, URL, session/device ID or account in receipt. Exported event UUIDs are opaque observation IDs, not proven visitor/journey identity. |
| Main installer observations | Existing unchecked interactive installer observation control in `packaging/bloomstep.iss`; silent/default-off collects nothing | Owned local `installer-receipt.json` and installation marker; `lib/services/installer_measurement.dart` records matching launch/sign-in view. No automatic server upload. Main-derived source only; held PR26 changes this surface. No installer was run for this increment. |
| Explicit account handoff | Settings, **Optional acquisition/install receipts**, **Link my exported website receipt** / **Link my pending installer receipt**, then **Link observations to this account?** / **Link to this account** | `lib/features/garden/measurement_controls.dart` checks current account/generation before and after confirmation. `MeasurementReceipt.parse` and `GardenStore.importMeasurementReceipt` preserve original UUID/time/source, require independent current app product-event consent, reject expired/private/conflicting observations and other local account ownership. No auto browser-to-auth matching or anonymous denominator. |
| Real app practice | `GardenStore.plant`, `checkIn`, reflection/graduation and garden UI handlers | Private owner SQLite habit/check-in records and consented `events` UUID/name/original UTC time/strict metadata, using `shared/event-registry.json` and generated Dart/API validators. Habit/feedback text stays in private product records, not telemetry. Positive actual practice emits `first_checkin`; rest/undo is not activation. |
| Sign-in/session | `lib/app/bloomstep_app.dart`, `SessionEvents.entered`, `AuthObservations` | Consent-gated session UUID and bounded attempt outcomes. Restored session is not fresh sign-in; auth attempt started is not success. Fresh user's pre-consent sign-in can be unobserved. Auth observations are not installation evidence. |
| Durable app upload | `lib/services/sync_service.dart`, `GardenStore.syncPayload` and `sync_state` fingerprints | Authenticated `/api/sync` via `X-Bloomstep-Authorization` avoids SWA token replacement. Pending events keep original IDs/times across offline/lost-ack retries. Acknowledgement uses the submitted snapshot, not subsequent edits. API immutable event documents `events:<uuid>` partitioned by hashed issuer/subject account key, retention anchored to event time (13 months). Existing first write wins on duplicate immutable API IDs; conflicting normalized report envelopes are excluded. |
| Account reports/history | `/api/team/metrics` and daily worker `/api/internal/aggregates` | Explicit `Bloomstep.Admin`, bounded scans/account deletion/record tombstone filtering, `dashboards.mjs`/`goals.mjs`/support/auth/reminder summaries. Daily snapshot worker and readback are distinct from on-demand values. `normalizedEvents` orders original UTC timestamps (microsecond-aware), UUID tie-break, duplicate union/conflict exclusion. Effective check-ins apply latest habit/localDay result including undo. |
| Deployment/config | `.github/workflows/azure.yml`, `aggregates.yml`, `website-live.yml`, `infra/`; static `/config.json` | Main-only existing Free SWA/managed Functions and personal Cosmos. Test/feature branches do not deploy. Aggregate worker role cannot read customer/admin records. This increment invokes no model endpoint or new service/resource. |

## Collection contract

Existing payload fields remain accepted:

```json
{
  "channel": "web",
  "event": "landing_view",
  "source": "campaign",
  "architecture": "unknown",
  "eventId": "00000000-0000-4000-8000-000000000001",
  "synthetic": false,
  "observedAt": "2026-10-09T04:00:00.000Z",
  "attribution": {
    "firstTouch": {
      "source": "campaign",
      "referrerDomain": "none",
      "campaignSource": "newsletter",
      "campaignMedium": "email",
      "campaignName": "launch"
    },
    "lastTouch": {
      "source": "campaign",
      "referrerDomain": "none",
      "campaignSource": "newsletter",
      "campaignMedium": "email",
      "campaignName": "launch"
    }
  }
}
```

`api/src/website-attribution.mjs` is the single deployed allowlist source,
also imported and bundled by the customer website. Event enum is
`landing_view|primary_cta_click|download_click`; architecture is
`arm64|x64|unknown` and only downloads accept non-unknown. Channel `store`
remains unsupported. Strict payload/attribution objects reject extras.
`observedAt` is UTC millisecond ISO; attribution requires it and source must
match last touch. No timestamp or attribution is required for legacy clients.

| Field | Allowed values |
| --- | --- |
| source | search, referral, direct, campaign, unknown |
| referrerDomain | google.com (including bounded co.uk/co.in mapping), bing.com, duckduckgo.com, search.yahoo.com, search.brave.com, ecosia.org, github.com, linkedin.com, none, same_origin, other, unknown |
| campaignSource / utm_source | newsletter, google, bing, github, linkedin, community, unknown |
| campaignMedium / utm_medium | email, organic, social, referral, cpc, unknown |
| campaignName / utm_campaign | launch, tiny_habits, garden, unknown |

The browser classifies locally. Unknown/malformed/duplicate/unsupported UTM
fields make campaign labels and source unknown, never persist arbitrary strings.
Arbitrary other query parameters and full referrer URLs/credentials are not
transmitted. Referrer domains outside the list become `other`; missing referrer
is `none`/direct, which can include browsers suppressing referrers. This is not
proof of typed/direct traffic. Google search query terms and private referral
domains are unobservable.

First/last touch are **one consented page epoch**, presently identical on this
static page. No cross-visit first acquisition or person-level attribution is
claimed. No cookies, local/session storage, visitor IDs, fingerprints, IPs or
account identities. Reload/pagehide/revocation clear page observation state;
reconsent creates fresh event IDs. DNT/GPC block collection; a newly encountered
privacy signal cancels the active epoch, and removing it never restores consent.
Abort cannot recall an HTTP observation already committed by the server.

Timestamped observation retries use the same in-memory payload/UUID, including
after a failed upload. In-flight and accepted same-stage/architecture clicks
deduplicate. There is no autonomous retry storm or cross-reload offline queue.
The server accepts timestamps younger than five minutes and at most 60 seconds
in the future. SHA-256 fingerprints of random event UUID and bounded canonical
content, expiry and counts commit together using the budget/daily Cosmos CAS
transaction. A cross-host/restart retry returns 204; conflicting reuse returns
400; racing transactions return 429 without a second increment. At the exact
five-minute age, retries are rejected. The ledger is capped at 180 entries;
expired hashes are logically inactive and physically removed on a subsequent
accepted upload or Admin read, not by an invented background cleanup. Residual
hashes in an idle lifetime budget are not visitor identifiers. Legacy untimed
clients retain only five-minute process-memory dedup, not distributed exact-once.

## Report/query contract

`GET /api/team/website?days=N` ends on today's UTC date, includes at most 30 days,
and returns existing `stages`, `sources`, `architectures`, `steps`, withheld
`daily` and separate `linked` fields. This is intentionally not the
completed-day app cohort watermark. `?synthetic=true` reads only the synthetic
partition and never links account observations. Real and synthetic count caps
remain independent.

Additive `acquisition` is:

```text
schemaVersion: 1
scope: consented_page_epoch
firstTouch / lastTouch:
  landing_view / primary_cta_click / download_click:
    source / referrerDomain / campaignSource / campaignMedium / campaignName:
      each allowlisted label -> number | null
definition: string
```

Daily persistence `attributionCounts` keys are
`<touch>:<stage>:<field>:<allowlisted-value>`. These are marginal event
dimensions, not joint identities/campaign paths. Report cells derive from
persisted selected UTC dates only. A marginal field dimension is withheld
entirely if any observed cell is below 50; missing labels remain null. Legacy
events do not get fabricated attribution. No small daily drilldown, visitor
counts, attribution-to-account join or per-campaign retention ratio is exposed.
Reports validate stored daily vectors before computing rather than replace
invalid data with zeros. Unknown, absence and suppression never mean zero.

Anonymous stage event ratios can exceed 100% and are not same-person conversion.
Linked receipt funnels are ordered distinct accounts with correct source
receipts and 50 contributors in numerator/denominator, not an anonymous visitor
denominator. Missing installation prevents downstream linked-chain conversion
even when a separately observed app check-in exists.

## Launch funnel (website → first completion)

Stage status for the minimal launch funnel at this head. "Synthetic proof" means
the isolated functional command below exercised the real code path; it is not
customer evidence.

| Stage | Source/sink | Status |
| --- | --- | --- |
| Visit | `landing_view` after explicit page consent → `POST /api/web/events` → daily aggregate | Implemented; real browser + persisted readback (synthetic proof). Event count, not visitors. |
| Primary CTA | `primary_cta_click` from the hero `#primary-cta` **and** footer `[data-primary-cta="footer"]` | Implemented; footer CTA was previously uncounted (fixed, browser-proven). |
| Download | `download_click` on home-page `[data-download]` links | Implemented. Click ≠ completed transfer. `/releases/` page downloads have no consent UI and are **not counted** (known undercount). |
| Install / first launch time | none | **Unobservable.** Installer receipts are withdrawn (PR26 quarantine); reported as `unobservable`, never zero. |
| Attributable app use | Explicit in-app link of an exported website receipt (Settings → Optional acquisition/install receipts) → account events via `/api/sync` | Implemented (headless app + real HTTP, synthetic proof). Proves later app use by that account, not install/launch time. |
| First habit planted | `recipe_created` after the receipt's download click | Implemented in `linked.activation` (additive). Habits planted before app analytics consent are never captured, so such users stay at the earlier stage (undercount, not zero). |
| First completion | first `checkin` with `did`/`didMore` on a habit planted in that journey | Implemented in `linked.activation`; a first skip does not hide a later completion. |

Additive report key `linked.activation` (schemaVersion 1):
`stages.{website_receipt_download, recipe_created, first_completion}` (distinct
accounts, number ≥ 50 or null), `steps[].{from,to,rate}`, `minimumContributors: 50`,
`unobservable: [download_completed, install_completed, first_launch_time, signin_succeeded]`.
The existing installer-ordered `linked.stages/steps` are unchanged. Anonymous
website counts and linked accounts are never joined; the linked funnel covers only
people who opt into both app analytics and receipt linking, so it is a
self-selected subset.

Owner actions before a public launch: supply the privacy-notice controller
identity/contact and legal basis (site `TODO(owner)` block), choose launch UTM
values from the allowlist (`utm_campaign=launch`, sources newsletter/github/linkedin/
community), and keep production website measurement gated per existing operations.
Smallest customer validation: one owner-run real visit with consent on the live
site, confirm the `/api/team/website?days=1` readback moves (counts publish only at
50 events, so verify via the private synthetic-free budget `realAccepted`), then a
handful of pilot users who opt in, export and link a receipt, plant and complete a
habit. Below 50 linked accounts the activation report stays null by design; pilot
learning must come from qualitative follow-up, not these aggregates. Retention and
coaching metrics are follow-up work.

## Remaining gap matrix / next increments

| Stage/goal | Observable today | Remaining gap/owner |
| --- | --- | --- |
| Acquisition | Consented page/CTA/download event counts; allowlisted first/last page-touch margins | Unique visitor/cross-visit acquisition is intentionally absent. Dashboard increment2 renders separate acquisition coverage, no joins. |
| Download -> install -> launch | Explicit historical source receipts on main, if an owner supplies and links them | Download click is not transfer success. No installer executed here; held PR26 disables new installer observations and its exact candidate was withdrawn after quarantine. A future trusted installer explicit handoff requires a separate reviewed consent/ownership contract, not a renamed/bypassed candidate. |
| Journey identity handoff | Explicit account import keeps original website/installer event IDs/time/source | No automatic session token across browser/download/installer/broker. Exported receipts can be self-selected/incorrectly linked; not attestation. Installation/channel remains unknown without appropriate source evidence. |
| Activation/retention | Actual consented recipe/check-in records, strict event metadata, goal/retention APIs | New account pre-consent sign-in/history may be missing. Account dashboard increment2 computes ordered saved same-habit activation, horizons, maturity and censored/unknown states. |
| Referral | Sharing/redemption/practice server receipts where real invitation features enabled | Share != sent/delivered; clicked invite != redemption; missing verified delivery remains unsupported. |
| Revenue | Registry explicitly marks purchase/trial/paywall unobservable | No payment/Store integration. Revenue unavailable, never zero or achieved. |
| Health | Bounded opt-in Dart errors and reminder preferences | No native-death/full crash-free census or complete OS delivery census. |
| Experiments | Existing static config/registry; exposures unobservable and experiments OFF | Autonomous engine is dependent increment3. No arbitrary code/copy rollout, dark pattern, consent bypass or self-enabled customer experiment in this unit. |
| Customer acceptance | Source/isolated browser/SQLite/real HTTP/persisted report proof | Genuine customer identity/provider auth, live Admin readback, trusted packaged install and population coverage are separate gates. |

Held draft PR26-31 are not merged/composed: PR26 installation/onboarding/profile
removes new installer collection; PR27 automatic update discovery lacks a
registered update-success funnel; PR28 first-habit/profile changes need fresh
actual display/success instrumentation review; PR29 weekly story is local
presentation, not an observed growth-story conversion; PR30 recovery guidance
is not a guaranteed recovery/practice success; PR31 profile/identity refinement
needs fresh session-entry acceptance. Existing saved recipe/check-in emitters
remain the reliable downstream boundary, not those held UI intentions.
No telemetry changes are silently copied from their worktrees.

Revoking app product-event consent purges local events/outbox fingerprints and
linked observations, not already accepted server facts. Current server API trusts
the consent-scoped authenticated client; it is not server-issued consent
attestation. Settings export/deletion and account DELETE (explicit confirmation)
remove private account events and invalidate snapshots; account tombstones
prevent offline resurrection. Anonymous aggregates cannot be individually located
or deleted, disclosed before consent. Source/exported receipt deletion is a
separate owner action.

## Automated acceptance and evidence

Prerequisites: Node >=22, installed trusted Chrome/Edge, Flutter 3.47.6, existing
API/site dependencies and resolved Flutter packages. Restore only when missing:
`npm --prefix api ci`, `npm --prefix site ci`, `flutter pub get`.
No native installer or owner garden/auth profile is used. The headless Flutter
test uses `--no-pub` and does not build a native installer; on Windows machines
without symlink capability, native build/Developer Mode remains a separate
environment prerequisite, not something this script changes.

Exact single functional command (fresh absolute artifact directory):

```powershell
.\tool\verify_telemetry.ps1 -EvidenceDir "$env:TEMP\bloomstep-telemetry-evidence-20261009"
```

It builds the actual customer bundle, drives real browser controls against
loopback HTTP production handlers with disposable file-backed Cosmos semantics,
then reads persisted outputs and Admin summaries. Browser fixture time is
controlled solely in the isolated harness to traverse minute budgets without
waiting 50 real minutes. Downloads are never fetched/executed. It tests 49 -> 50
stage publication, exact 51/50/50 stage counts (reconsent adds a landing),
ratio 50/51 and 1, complementary suppression, default-off, DNT/GPC/new signal,
revoke/reconsent, offline navigation, restart/conflicting/stale retries,
synthetic partition isolation and forbidden private fields.

The **actual browser-exported website receipt** is then imported through real
Flutter `GardenStore` SQLite APIs under independent app consent, actual positive
check-in saved, production HTTP sync committed, response deliberately lost and
retried, original UUID/time/persisted count independently read from disk,
consent revoked/regranted and server account deletion/resurrection checked.
Separate report assertions consume only those persisted events, verify
suppression and unknown install/launch/downstream chain. Normal test-suite runs
use an explicitly labeled isolated receipt fixture; the functional harness
requires `receiptOrigin: browser_export` so fixtures cannot substitute for the
browser-to-app scenario.

Outputs: `default-off.png`, `consented-observations.png`, browser and app receipts,
`computed-reports.json`, `app-events.json` (synthetic fixed metadata only),
`app-computed-results.json`, and `functional-acceptance.json` binding component
artifacts and actual tested source SHA-256 hashes/revision. All are outside
customer source; tokens/secrets/private habits/database files are not retained.
Every isolated database/profile/process is closed/deleted on completion.
The new manual/PR `telemetry.yml` workflow retains the same synthetic artifacts
without Azure/provider credentials or installer execution.

TDD: new browser classification/reset/retry tests failed before implementation;
after restoring missing API dependencies, all three initial API contract tests
failed against the old schema/dedup/report. Subsequent scenario tests add exact
five-minute and concurrent collector boundaries. Local complete functional run
passed with 33 app tests plus independent persisted-report assertions. No genuine
customer conversion, provider authentication, safe installation, hosted
deployment or unlimited free usage is inferred from these synthetic results.

Existing free architecture limits still apply: 400 real/day, 10,000 lifetime,
30 persisted/minute, 100/day/source, 90-day UTC daily TTL; synthetic 20/day,
100 lifetime, 10/day/source; bounded Admin reads and linked scans. Attribution
increases bounded document bytes, not the accepted-event budget. The sample
51/50/50 is isolated test traffic, never production quotas/population. Reuse
Free SWA/Cosmos/Actions allowance is not a promise of unlimited hosting or a
verified zero bill. No new paid resource, resource upgrade, AI endpoint or
spending-limit change was made; actual billing remains independently unknown.
