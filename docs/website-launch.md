# Public website launch checklist

Status: public-site UX and isolated collector evidence are implemented; **a full public launch is not approved or
verified**. This checklist does not supersede the installer, privacy, identity or deployment gates.

Owner decision: launch a useful, trustworthy app **without advertising in this launch**; monetization is deferred
until customer evidence. Advertising, supporter checkout and paid-tier expansion are outside this launch scope.

## Audience and conversion path

Initial audience: adults using Windows who want a small routine alongside their working day, without streak
pressure. The page explains a concrete routine/action example, shows a labeled synthetic app screenshot, and
uses one primary action: go to the Windows download. It discloses 64-bit Windows, required sign-in, ages 16+,
the unsigned limited-preview status and no payment step beside the download.

Both hero and closing download-intent links enter the existing `primary_cta_click` website event; identical
intent observations are deduplicated within the consented page epoch. The closing link is **not** a new
experiment exposure or an experiment-secondary outcome. The download links use `download_click`.
No schema, account identity join or successful-download claim was added.

Optional consent is now discoverable from the hero and beside downloads, remains unchecked, and explains
subsequent-only collection. No earlier click is replayed on opt-in. DNT/GPC, memory-only choice, withdrawal,
no-JavaScript download access and service-outage independence are preserved. Privacy details remain linked.

## Initial demand hypothesis (owner action, not publication)

Use **one unpaid LinkedIn post** from the owner's existing profile, targeted in its wording to adults who use a
Windows PC. Explain one concrete tiny routine and the honest limited-preview boundaries; link to the current
canonical site using:

```text
?utm_source=linkedin&utm_medium=social&utm_campaign=tiny_habits
```

Append these allowlisted labels to the `origin` in `site/customer-config.json`; do not invent a campaign
containing names, email addresses or arbitrary audience details. No post was published, message sent, ad bought
or new account created. Confirm launch gates before creating demand for the downloadable app.

Hypothesis: a concrete Windows routine example will attract people who want to try one habit and make the
download path understandable. Review a fixed 14-day window after owner publication. The website report can
show opted-in page/button event counts and separate first/last page-touch margins for LinkedIn/social/tiny_habits;
publication floors below 50 remain suppressed. Campaign dimensions are marginal counts, not joined people,
qualified leads, installs or attributed app activations.

Treat stage ratios as descriptive event ratios, not visitor conversion probabilities or a causal test.
Account recipe -> first positive check-in and exact-day retention remain separate opt-in AARRR evidence.
The foundation's additive `linked.activation` report separately supports explicitly imported website receipt
download -> saved recipe -> first positive same-habit completion, with 50-account suppression and unknown
install/launch timing. It is not a campaign-level join or an anonymous visitor denominator; neither report can
be attributed to that post without a supported consented campaign link. Use voluntarily submitted in-app
feedback to identify specific obstacles, never infer rejection from missing telemetry. If evidence is sparse,
record insufficient data; do not promote variants, run experiments or broaden collection.

## Contact and qualified leads

A download click is intent, **not a qualified lead**. There is no lead count or website contact form. For an
initial free self-service preview, a mailing list is not essential to the product funnel. In-app private feedback
is now explicitly discoverable in the FAQ, but it requires successful sign-in and has no response-time guarantee.

The shared homepage privacy notice identifies Sampath Kumar's personal project, lists actual services and
processing purposes, and distinguishes verified active-store TTLs and backup configuration from unresolved
restore behavior without universal legal-basis guarantees. The owner-approved account-content policy is
retention until the user deletes the records, with no automatic inactivity expiry. The owner-approved
public support/privacy contact is `store-developer@outlook.com`, linked on the homepage and releases page
without requiring sign-in. Mailbox delivery has not been tested; no response deadline is promised.
Private in-app feedback requires sign-in; public GitHub issues are for non-sensitive bugs, not privacy requests. No web contact
form or lead-capture flow was added, and no response time is guaranteed. If the owner wants lead capture later,
first agree purpose, qualification, fields, consent, access, storage, retention/deletion, response ownership
and abuse protection. Existing aggregate telemetry cannot substitute for that agreement.

## Gates and owner decisions

| Gate | Current evidence / remaining action |
| --- | --- |
| Value proposition / audience | Concrete Windows routine, labeled app illustration; no clinical or efficacy claim. Owner approves initial audience/channel. |
| Responsive / keyboard / static download | Isolated real-browser 1280/390/320 reflow, skip link, keyboard FAQ, no-JS links; customer-site CI checks Lighthouse, both entry pages and warning/help surfaces. |
| Acquisition / intent | Real browser -> HTTP -> disk confirms allowlisted campaign, footer/hero dedup, consent-off zero writes, withdrawal and small-cell suppression. Synthetic proof only. |
| Privacy | Default-off preserved; owner-approved public contact `store-developer@outlook.com` is linked without sign-in (mailbox delivery untested; no response deadline). **Owner decisions:** product owner to confirm applicable jurisdiction-specific obligations. **Evidence gaps:** service/project owner to confirm provider log/identity retention; coordinating project session `b3eaa24c-99fa-4b3f-b6e8-d0601e0b6ea8` owns future isolated restore-marker verification coordination. Synthetic file-backed app/API restart tests do not establish cloud-restore behavior. Public issues accept non-sensitive bugs only. |
| Production collection / console | Local synthetic preview is usable. **Unverified:** approved live deployment, Functions/OIDC/Admin roles, deployed collector/readback, retention/erasure operations and hosting logs/billing facts. No new paid resources provisioned. |
| Download / install / first launch | The configured CTA points to the hosted internal dogfood installer `https://budlark.com/downloads/Budlark-0.1.0-windows-universal-setup.exe` (22,392,273 bytes; SHA-256 `b53767c405fa9b704fb828d221f883b81d14231e3ebf65dd8820d3812fd42a2c`). The owner confirmed HEAD 200, matching downloaded bytes and Authenticode `NotSigned`. It is labeled unsigned and designated-testers-only, not a general release. Legacy `v0.1.0-preview.14` ARM64/x64 GitHub files remain separate troubleshooting links. Owner manual installation and first-launch verification remain pending; publication does not prove install, launch or safety. The withdrawn PR26 `b58ba7fc` candidate was Defender-quarantined (`Behavior:Win32/DefenseEvasion.A!ml`) and remains excluded; this does not characterize every artifact on PR26. See the artifact-specific evidence below. |
| App activation / retention | Existing separate account reports, not website or campaign conversion. Revenue and referral-delivery/attributed activation remain unsupported. |
| Experiments | Public OFF; no sufficient customer evidence or deployment authorization. Existing isolated loop proof is not live efficacy. |
| Public demand / deployment | Owner conditionally approved production promotion after exact-head functional, security and privacy gates. This does not waive contact disclosure, installer acceptance or authorize outreach. No merge, deploy, release or outreach was performed. |

## Conditional production change order

The owner has authorized production only after functional app, installer and website analytics validation.
Use the composed revision, not separate cherry-picked dashboard or collector files. A passing synthetic
fixture is a prerequisite, not customer acceptance. Keep third-party analytics sandboxes and public
experiments disabled; monetization is outside this launch.

1. Freeze the composed source revision and the intended installer filename/full SHA-256. Preserve exact-head
   API, customer-site, telemetry, console-preview and composed-loop receipts and hosted artifacts. The owner
   manually verifies the exact installer and records the tested machine/architecture and observed outcomes.
   Hosted CI does not install or launch it; a result applies only to the tested artifact and machine.
   Missing feedback blocks customer promotion.
2. Verify the owner-approved public contact is rendered as `mailto:store-developer@outlook.com` on both
   customer entry pages before merging. Publication approval does not establish mailbox delivery or a
   response deadline; no mailbox was created. Verify applicable provider retention/recovery boundaries and actual customer
   authentication/explicit operator roles. Public GitHub issues remain a non-sensitive bug alternative,
   not a private rights-request route.
3. Record the existing production revision, public site hashes/download manifest, approved runtime settings
   and resource metadata before change, without exporting credentials or customer data. Build the approved
   revision with production operator configuration through `azure.yml`; never upload the loopback preview
   bundle or its synthetic token/store. The separate keyless analytics staging site is not this deployment
   candidate and its SDK trials do not authorize production vendors.
4. Coordinate one composed merge to `main` only after those gates. The existing `azure.yml` triggers on that
   merge and deploys the built site plus managed API to the existing Free SWA. It is not a deploy-later merge:
   do not merge while a gate is pending. Do not dispatch the static-only `site.yml` as a substitute for the
   API deployment. Verify the complete staging/composed artifact before this production-triggering change.
5. After deployment, read back actual served source/assets and protected-route rejection, then perform a
   bounded consent-off/on/withdrawal proof and authenticated operator load using isolated synthetic records.
   Preserve real-traffic/synthetic segregation and verify erasure. `website-live.yml` supplies existing public
   readback; supplement it with exact route/config and report evidence rather than treating deployment success
   as analytics success. Verify schedules/worker roles and spend/volume caps before enabling any existing worker.
6. Change the public download manifest only to the accepted exact installer after the app/API compatibility
   proof. Verify served links and checksums. If an asset is blocked or harm/security/privacy errors appear,
   stop promotion, restore the prior accepted manifest and redeploy the prior compatible site/API revision
   through the same reviewed path. Disable optional collection/worker execution with existing operational
   controls as necessary; keep export/deletion available. Never restore a database as a UI rollback or erase
   deletion markers. A prior revision is not an acceptable rollback if it reintroduces the identified defect.

Live readback may expose missing production configuration. Resolve only verified dependencies; do not weaken
authentication, enable broad experiments, provision paid resources, or present a pending gate as complete.
Public demand starts after accepted download/support paths exist, not during this change order.

### Composed-candidate requirement traceability

| Requirement | Implemented surface / evidence | Candidate boundary |
| --- | --- | --- |
| Website measurement is optional, consented, bounded and revocable. | `site/customer.mjs`, `api/src/website-funnel.mjs`, `site/verify-telemetry.mjs`; default-off and real browser-to-persisted synthetic acceptance. | No visitor/account denominator or live customer readback is inferred. |
| Acquisition remains separate from account activation. | `api/src/website-funnel.mjs`, `site/website-panels.mjs`, `docs/backend-contracts.md`; source/referrer/campaign event margins and explicit linked-activation contract. | Marginal website events are not unique people, qualified leads or campaign-attributed accounts. |
| AARRR outcomes use supported account evidence and explicit unknown states. | `api/src/aarrr.mjs`, `site/aarrr-panels.mjs`, `site/verify-aarrr.mjs`; synthetic 150/100/50 oracle and withheld unsupported revenue. | Retention, referral delivery and revenue remain unavailable where the source contract does not support them. |
| Website experiments cannot infer outcomes from clicks or repeatedly peek at active cohorts. | `api/src/experiment-policy.mjs`, `api/src/experiments.mjs`, `site/experiment-panels.mjs`, `tool/experiment_acceptance.mjs`; fixed-horizon evaluation, exposure ordering, withdrawal, harm rollback and kill acceptance. | Isolated synthetic loop only; production/public experiments remain OFF. |
| Customer isolation and free-tier spending controls survive composition. | `api/src/backend.mjs`, `site/isolation-check.mjs`, `site/operational-review.mjs`, `.github/workflows/production-isolation.yml`; route/API contracts and bounded acceptance. | Local candidate tests do not replace exact-head hosted checks or authorize deployment. |
| Public privacy/support claims match verified facts. | `site/index.html#privacy-notice`, `site/test/launch.test.mjs`, `site/verify-launch.mjs`, this launch checklist. | Owner-approved public contact is linked without sign-in; mailbox delivery untested. Provider retention and Azure restore limitations remain disclosed, not passed technical gates. |

### Measurement availability at this handoff

| Dimension | Implemented evidence | Production claim permitted now |
| --- | --- | --- |
| Acquisition | Consented allowlisted website event/touch margins, suppression; real HTTP/disk synthetic proof. | Live deployment/readback unverified; not unique visitors, leads or campaign-attributed accounts. |
| Activation | Separate account recipe/completion reports and optional explicitly linked receipt journey, tested 150/100/50. | Synthetic acceptance only; installation and first-launch timing unobservable. |
| Retention | Opted-in exact-local-day account retention with pending/censored/suppressed states. | No customer retention result or completeness claim without actual eligible data. |
| Referral | Separate invitation/support evidence where observed. | Delivery and attributed recipient activation unsupported; not viral conversion. |
| Revenue / ARR | No monetization in launch scope. | Unavailable, not measured zero; no paid flows or full-AARRR claim. |
| Optimization | Fixed-horizon finite variants, audit/promotion/rollback/kill proven in isolation. | Public OFF; no customer efficacy or autonomous production promotion claim. |

### Installer evidence is artifact-specific

Per the coordinating owner's evidence update:

- Withdrawn PR26 candidate `b58ba7fc`: Defender quarantine; excluded from downloads, execution and acceptance.
- Candidate `f7552cf` (SHA-256 prefix `8a438`): owner verified it on their own ARM64 machine only. This is not
  x64 acceptance or evidence for another revision.
- Latest composed profile-fix candidate `ce47ccb` (SHA-256 prefix `03ccac`): locally downloaded and hash-verified,
  **not executed**, and no owner installation/launch feedback. Hash consistency is not a safety guarantee.

The prefixes above identify the owner's update, not complete checksum values to use for file verification.
No acceptance transfers between revisions; no candidate was promoted by this website work. Do not bypass
Defender, browser warnings or device policy. Require exact-artifact owner manual verification before changing
the public download pointer or describing a candidate as owner-verified.

### Privacy evidence (read-only, 10 October 2026)

`site/index.html#privacy-notice` is the shared public draft notice; the releases page links to it.
The owner explicitly authorized publication of `store-developer@outlook.com` as Budlark's support and
privacy contact. Both customer entry pages link that exact address without sign-in. The parent coordinator
confirmed the scoped publication approval and owner monitoring, relayed on 12 October 2026.
Rendered-link verification is not mailbox-delivery testing. No mailbox,
account, mailing list, response deadline or binding terms were created.

Verified Azure metadata for the existing personal `budlark-free` resource group:
`budlark-free` Static Web Apps, `budlark-free-261004` Cosmos DB, `budlarkcustomers261004` External ID
directory and separate `budlark-analytics-staging` Static Web Apps. Cosmos readback: active region Central India,
analytical storage disabled, Periodic backups, interval 240 minutes, retention 8 hours, Geo redundancy;
`budlark/data` has `/userId` partitioning and default TTL `-1` (individual event/audit records supply TTL).
No secrets, user records or access policies were read or changed.

Source facts: app event TTL 34,214,400 seconds (396 days), audits/snapshots 2,592,000 seconds (30 days);
other garden/feedback/settings records do not automatically expire. Account and record deletion retain
minimal replay-protection markers. Anonymous counts cannot be individually located; revocation is not
retroactive deletion of aggregate counts. Active deletion does not remove exports, identity-provider accounts
or existing backups instantly. Exact log/identity/email retention and tested recovery are unknown.

PR35 owner confirms current production has no third-party vendor code. A separate, noindex staging site loads
GA4 only after opt-in; an authenticated GA4 standard report on 12 October 2026 verified ingestion from test
visits. This proves staging collection only, not production collection, customer adoption, artifact attribution
or conversions. Clarity/Cloudflare/PostHog remain unconfigured there; Aptabase/Sentry are gated debug
prototypes, not enabled release processors. Do not list those vendors as active processors or infer production
collection from staging evidence.

Account garden, feedback and settings records are retained until the user deletes them, with no automatic
inactivity expiry (product-owner decision, 12 October 2026). App raw events expire 396 days after their
original timestamp; website daily counts and visit-test records expire within 90 days; API audit records and
daily aggregate snapshots expire after 30 days. Account/record deletion removes active content but keeps
minimal replay-protection markers. The verified Cosmos backup configuration (four-hour interval, eight-hour
retention setting, geo-redundant storage) does not establish backup deletion timing, restore-point availability,
or deletion-marker survival. Synthetic file-backed adapter tests prove tombstones persist across app/API
restart; they do not test the configured Azure backup restore. Restore-marker preservation and resurrection
risk remain unknown, V1 has no guaranteed recovery service or deadline, and no live-customer deletion
acceptance or cloud restore test has been run. Coordinating project session
`b3eaa24c-99fa-4b3f-b6e8-d0601e0b6ea8` owns future isolated restore-marker verification coordination;
no restore, new resource, customer-data access or expenditure is authorized by this notice work.

## Reproduce the public UX/collector evidence

With existing API/site dependencies installed and trusted Edge installed (or `CHROME_PATH` configured):

```powershell
npm --prefix site run build
$env:EVIDENCE_DIR = Join-Path $env:TEMP 'budlark-public-launch-evidence'
node site\verify-launch.mjs
```

The source-bound `launch-receipt.json` and desktop/mobile/no-JS screenshots label the run synthetic. Real
download navigation is prevented; no installer is downloaded or executed. Production download pointers,
experiment configuration and account/website denominator contracts are unchanged.
