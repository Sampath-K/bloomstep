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

The owner-authorized public support/privacy contact `store-developer@outlook.com` is published as a `mailto:`
link in the shared homepage privacy notice and referenced on the releases page. The notice identifies
Sampath Kumar's personal project, lists actual services and processing purposes, and documents verified
active-store/backup retention without universal legal-basis guarantees. The in-app private feedback route
requires sign-in; public GitHub issues remain for non-sensitive bugs, not privacy requests. No web contact
form or lead-capture flow was added, and no response time is guaranteed. Email/provider retention and
mailbox handling are not verified or promised. If the owner wants lead capture later, first agree purpose,
qualification, fields, consent, access, storage, retention/deletion, response ownership and abuse protection.
Existing aggregate telemetry cannot substitute for that agreement.

## Gates and owner decisions

| Gate | Current evidence / remaining action |
| --- | --- |
| Value proposition / audience | Concrete Windows routine, labeled app illustration; no clinical or efficacy claim. Owner approves initial audience/channel. |
| Responsive / keyboard / static download | Isolated real-browser 1280/390/320 reflow, skip link, keyboard FAQ, no-JS links; customer-site CI checks Lighthouse, both entry pages and warning/help surfaces. |
| Acquisition / intent | Real browser -> HTTP -> disk confirms allowlisted campaign, footer/hero dedup, consent-off zero writes, withdrawal and small-cell suppression. Synthetic proof only. |
| Privacy | Default-off preserved; owner/purpose/processor/active-store/backup facts documented; the owner-authorized public support/privacy email is linked from the homepage notice and releases page. **Unresolved:** provider log/identity/email retention, jurisdiction-specific obligations and verified backup recovery/deletion-marker preservation. |
| Production collection / console | Local synthetic preview is usable. **Unverified:** approved live deployment, Functions/OIDC/Admin roles, deployed collector/readback, retention/erasure operations and hosting logs/billing facts. No new paid resources provisioned. |
| Download / install / first launch | Existing preview.12 pointer unchanged. **Blocked:** protected acceptance of the intended composed artifact and unresolved launch CI. The withdrawn PR26 `b58ba7fc` candidate was Defender-quarantined (`Behavior:Win32/DefenseEvasion.A!ml`) and remains excluded; this does not characterize every artifact on PR26. See the artifact-specific evidence below. |
| App activation / retention | Existing separate account reports, not website or campaign conversion. Revenue and referral-delivery/attributed activation remain unsupported. |
| Experiments | Public OFF; no sufficient customer evidence or deployment authorization. Existing isolated loop proof is not live efficacy. |
| Public demand / deployment | Owner conditionally approved production promotion after exact-head functional, security and privacy gates. This does not waive contact disclosure, installer acceptance or authorize outreach. No merge, deploy, release or outreach was performed. |

## Conditional production change order

The owner has authorized production only after functional app, installer and website analytics validation.
Use the composed revision, not separate cherry-picked dashboard or collector files. A passing synthetic
fixture is a prerequisite, not customer acceptance. Keep third-party analytics sandboxes and public
experiments disabled; monetization is outside this launch.

1. Freeze the composed source revision and the intended installer filename/full SHA-256. Preserve exact-head
   API, customer-site, telemetry, console-preview and composed-loop receipts and hosted artifacts. Obtain
   protected install/launch acceptance for that exact installer on each advertised architecture; a prior
   owner's ARM64 trial does not cover another build or x64. Failed or missing runtime evidence blocks promotion.
2. Close privacy/contact and identity gates before merging: the owner-authorized public support/privacy
   email is now published and no mailbox was created. Verify applicable provider retention/recovery
   boundaries and actual customer authentication/explicit operator roles. Public GitHub issues remain a
   non-sensitive bug alternative, not a private rights-request route.
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
  **not executed**, and no protected install/launch acceptance. Hash consistency is not a safety guarantee.

The prefixes above identify the owner's update, not complete checksum values to use for file verification.
No acceptance transfers between revisions; no candidate was promoted by this website work. Do not bypass
Defender, browser warnings or device policy. Require exact-artifact protected acceptance before changing the
public download pointer or describing a candidate as independently safety-accepted.

### Privacy evidence (read-only, 10 October 2026)

`site/index.html#privacy-notice` is the shared public draft notice; the releases page links to it and
references the same support/privacy address. The owner explicitly authorized publishing
`store-developer@outlook.com` as Bloomstep's public support and privacy contact. No new mailbox, account,
mailing list or binding terms were created.

Verified Azure metadata for the existing personal `bloomstep-free` resource group:
`bloomstep-free` Static Web Apps, `bloomstep-free-261004` Cosmos DB, `bloomstepcustomers261004` External ID
directory and separate `bloomstep-analytics-staging` Static Web Apps. Cosmos readback: active region Central India,
analytical storage disabled, Periodic backups, interval 240 minutes, retention 8 hours, Geo redundancy;
`bloomstep/data` has `/userId` partitioning and default TTL `-1` (individual event/audit records supply TTL).
No secrets, user records or access policies were read or changed.

Source facts: app event TTL 34,214,400 seconds (396 days), audits/snapshots 2,592,000 seconds (30 days);
other garden/feedback/settings records do not automatically expire. Account and record deletion retain
minimal replay-protection markers. Anonymous counts cannot be individually located; revocation is not
retroactive deletion of aggregate counts. Active deletion does not remove exports, identity-provider accounts
or existing backups instantly. Exact log/identity/email retention and tested recovery are unknown.

PR35 owner confirms current production has no third-party vendor code; separately deployed keyless staging
loads none of GA4/Clarity/Cloudflare/PostHog and has no API. GA4 proposed save/configuration and vendor retention
are not verified; Aptabase/Sentry are gated debug prototypes, not enabled release processors. Do not list six
vendors as active processors or infer live first-party collector success from staging SDK tests.

## Reproduce the public UX/collector evidence

With existing API/site dependencies installed and trusted Edge installed (or `CHROME_PATH` configured):

```powershell
npm --prefix site run build
$env:EVIDENCE_DIR = Join-Path $env:TEMP 'bloomstep-public-launch-evidence'
node site\verify-launch.mjs
```

The source-bound `launch-receipt.json` and desktop/mobile/no-JS screenshots label the run synthetic. Real
download navigation is prevented; no installer is downloaded or executed. Production download pointers,
experiment configuration and account/website denominator contracts are unchanged.
