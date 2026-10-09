# Free analytics staging sandbox

This is an isolated, prelaunch learning sandbox, not a production enablement,
launch approval or proof of acquisition effectiveness. No vendor accounts were
created: the account owner must sign in and accept the vendors' terms themselves.
Do not enter a credit card, start a paid plan or enable automatic upgrades.
Pricing and settings below were checked against vendor pages on 9 October 2026;
confirm the free plan still exists before signing up.

## Local configuration and output boundaries

Create **`.env.analytics.local` at the repository root** (gitignored), with
only the vendors you want to try. Missing/empty keys disable that vendor.
Environment variables of the same names override the local file.

```dotenv
GA4_ID=
CLARITY_ID=
CLOUDFLARE_TOKEN=
POSTHOG_KEY=
POSTHOG_REGION=EU
APTABASE_APP_KEY=
SENTRY_DSN=
```

These are client-side project identifiers/ingest keys, not administrative API
tokens. They become visible in the staging browser bundle or app binary; never
paste vendor personal/admin keys. Keep the local file and generated output out
of Git, screenshots and PR descriptions.

After `npm ci --prefix site --ignore-scripts`, build the configured site with:

```powershell
node tool\analytics_site_build.mjs
```

Output: **`build\analytics-site\`**, entirely separate from `site\`. Serve that
directory with an existing static server, or upload only that directory to a
separate staging host. Do not upload it to production. Both pages have a noindex
meta tag, robots denies all crawlers, and the Azure Static Web Apps configuration
adds `X-Robots-Tag` on every response. Other hosts must set that header themselves.
Noindex is not access control: use restricted staging access when necessary.

The existing `site\build.mjs` remains the production builder. It imports no
sandbox module. A test scans production HTML, JS, MJS, JSON and CSS recursively
for vendor code/domains (excluding Node tooling manifests/dependencies and tests).
No production HTML, telemetry, AARRR, aggregate or experiment logic is changed.

## Accounts the owner must create

| Vendor | Exact owner setup | Free choice and ID to paste |
| --- | --- | --- |
| Google Analytics 4 | Open <https://analytics.google.com/>; **Admin > Create > Account**, name `Bloomstep staging`; turn off account data-sharing options. Create a GA4 property, select your reporting timezone/currency, then **Data streams > Add stream > Web** with the staging origin and enhanced measurement OFF. | Standard GA4 (not Analytics 360). Copy the web stream **Measurement ID** (`G-...`) into `GA4_ID`. Do not paste a Measurement Protocol secret. |
| Microsoft Clarity | Open <https://clarity.microsoft.com/>; sign in; **Add new project**, name `Bloomstep staging`, enter only the staging website URL. Open **Settings > Setup**. | Free Clarity. Copy the **Project ID** from the tag URL `https://www.clarity.ms/tag/PROJECT_ID` into `CLARITY_ID`. |
| Cloudflare Web Analytics | Open <https://dash.cloudflare.com/sign-up>; create the free account; in **Web Analytics** (sometimes under Analytics & Logs), **Add a site**, enter the staging hostname and choose manual JavaScript installation. | Free Web Analytics; do not buy a domain, proxy production or use automatic beacon injection. Copy the UUID **token** from the `data-cf-beacon` snippet into `CLOUDFLARE_TOKEN`. |
| PostHog | Open <https://app.posthog.com/signup>; choose **EU Cloud** before creating `Bloomstep staging` (US is an explicit alternative); skip billing/card setup. Open **Project settings > Project API key**. | [Free, no-card tier](https://posthog.com/pricing). Copy only the public **Project API key** (`phc_...`) into `POSTHOG_KEY`, and set `POSTHOG_REGION=EU` or `US` to match the project. No personal API key. |
| Aptabase | Open <https://eu.aptabase.com/auth/register> (recommended EU), or <https://us.aptabase.com/auth/register>; create an app named `Bloomstep staging`, select Flutter, then copy its App Key. | [Free plan: 20,000 events/month, no card](https://aptabase.com/pricing). Copy `A-EU-...` or `A-US-...` into `APTABASE_APP_KEY`. Exceeding the free limit pauses analytics; do not upgrade. |
| Sentry | Open <https://sentry.io/signup/>; choose EU data storage when creating the organization if offered; select the **Developer/free plan**, skip/decline paid trial upgrades and card entry. **Projects > Create project > Flutter**, name `bloomstep-staging`; open **Settings > Projects > bloomstep-staging > Client Keys (DSN)**. | [Developer/free](https://sentry.io/pricing/). Copy the public **DSN** into `SENTRY_DSN`, not an auth token. Keep all optional paid add-ons, Seer/AI, profiling, logs and replay off; disable spend/overage upgrades. If the signup does not offer a lasting free plan, leave the DSN blank. |

### Privacy and residency before inserting keys

* **GA4:** Admin > Data collection and modification > Data retention: choose
  **2 months** and turn off reset-on-new-activity. Turn off Google Signals,
  advertising personalization, user-provided data collection, enhanced
  measurement and cross-domain tracking. GA4 automatically anonymizes IPs; there
  is no Universal Analytics `anonymize_ip` toggle to configure. GA4 does not offer
  the same selectable EU-only project residency guarantee as PostHog/Aptabase.
  Leave its ID blank if that is a requirement.
* **Clarity:** Settings > Masking: select **Strict**, save before testing.
  The whole staging body also has `data-clarity-mask="true"`. Do not unmask
  inputs or include personal/account/habit content. Masking hides page content,
  not every metadata field or URL. Do not test invitation/private-token URLs
  with real keys. The loader removes the URL query/fragment before loading any
  vendor. Confirm Microsoft's current processing locations and standard
  retention; this project does not provide selectable EU-only residency.
* **PostHog:** EU projects use `https://eu.i.posthog.com`; US projects use
  `https://us.i.posthog.com`. Region is not interchangeable after project
  creation. Disable autocapture, session replay, user profiles, IP/geolocation
  enrichment (use the project's ingestion transformations if required), and
  automatic feature-flag requests. The loader uses memory persistence and
  sanitized explicit events only. Set billing limits to $0/no paid upgrade.
  Create funnels for `sandbox_page_view` -> `sandbox_download_click` if desired.
  Flags/experiments may be configured in the UI, but automatic flag loading and
  application behavior changes remain OFF in this PR; do not turn on production
  experiments or claim an experiment result.
* **Cloudflare:** use manual installation so the beacon cannot load before
  consent. Review the vendor's current location/retention policy; no
  customer-selectable EU-only analytics processing is assumed. Web Analytics is
  cookie-free, but third-party network handling is still covered by this choice.
* **Aptabase:** select EU/US at signup; the App Key encodes the endpoint.
  SDK system metadata includes OS/version, locale and app version, plus random
  session IDs. Only fixed sandbox session/referral events are added.
* **Sentry:** enable server-side data scrubbing and sensitive-data scrubbing in
  Settings > Security & Privacy/Data Scrubbing. Use EU storage when available;
  verify the DSN region agrees with your organization. Client PII is disabled,
  integrations/native crash collection/replay/tracing/logging are disabled.
  A final allowlist transport strips SDK contexts, user, breadcrumbs, text,
  stacks, attachments and trace data. Only event ID/time, error level,
  `sandbox_dart_error` and `analytics-sandbox` environment are sent. Consequently
  this is a Dart/Flutter category-only crash plumbing test, not native crash
  reporting, detailed debugging or a crash-free-rate claim.

All website vendors are behind a separate unchecked checkbox using the existing
visit-scoped consent pattern. Nothing starts by default or on a persisted prior
consent. Do Not Track/Global Privacy Control disable the sandbox choice.
Unchecking reloads the page, destroys SDK execution and leaves the choice off.
Requests already in flight and data already delivered cannot be recalled.
Vendor cookies already created are not deleted automatically: use a fresh
browser profile, clear vendor/site storage and use vendor deletion controls after
real-key trials. Vendor code may collect metadata beyond the wrapper's explicit
events; inspect actual traffic before deciding whether any vendor is acceptable.

## Desktop staging and the referral bridge

Run a **debug** Windows sandbox, never a release/installer:

```powershell
node tool\analytics_app_run.mjs
```

This reads the same local keys, writes gitignored
`build\analytics-defines.json`, and invokes Flutter with
`BLOOMSTEP_ANALYTICS_SANDBOX=true`, empty default app keys and debug mode.
Flutter Windows prerequisites include Visual Studio desktop C++ tools and
Windows Developer Mode (plugin symlink support). Do not change the production
installer or install this sandbox over a customer app. Use a disposable test
account/profile: existing first-party behavior and storage are not replaced.

Even with the define, `kReleaseMode` prevents all sandbox initialization and UI
in release builds. In Settings, enable the existing **Share product event
counts** and then the **separate unchecked staging Aptabase/Sentry choice**.
Closing Settings, revoking either choice or signing out disables sending;
reopening requires fresh staging consent. Missing keys initialize no SDK.
Aptabase has no public shutdown API: the sandbox supplies an in-memory queue
that checks current account consent before queuing or releasing any batch and
clears pending data on revoke. Its inert empty-queue timer may remain in process.

Website CTA/download links receive bounded `utm_source`, `utm_medium` and
`utm_campaign` tags, defaulting to `sandbox/test/prelaunch`. A tagged GitHub
download does **not** forward UTM data into the executable. The staging website
and first sign-in screen show the shared code **`BS-SANDBOX`**. Enter it in
Settings after opting in: Aptabase gets `sandbox_referral_entered` with the fixed
campaign `prelaunch`. It deliberately provides only a manual campaign-level
bridge, not an individual click/install/account join, invite redemption or proof
that an installation occurred.

## Verification without accounts

```powershell
node tool\analytics_sandbox_check.mjs
```

Requires restored site dependencies and installed Chrome/Edge (or `CHROME_PATH`
pointing to Chromium). The check starts a loopback-only server/browser, builds
no-key and fake-key EU/US variants, records **zero** external requests before
consent, checks vendor loader URLs and queued settings after consent, checks GPC
and revocation, and enforces the production scan. Every external request is
intercepted with an empty response, so no vendor gets traffic, no fake project
ingests data, and no downloaded vendor code runs. It restores a keyless staging
output afterward. This proves our loader/init contracts, not real vendor SDK
behavior, privacy, dashboards or ingestion.

Evidence: **`analytics-evidence\`** (gitignored) contains `network.json` and
before/after full-page screenshots for all four scenarios. Override with
`EVIDENCE_DIR`. Never use the offline check to claim live vendor acceptance.

Additional checks:

```powershell
node --test test\analytics_sandbox_test.mjs
flutter test --no-pub test\analytics_sandbox_test.dart
flutter test --no-pub test\analytics_aptabase_sdk_test.dart
```

Flutter tests cover no-key/dual-consent/disabled gating, EU/US Aptabase endpoint
selection, memory-queue revocation, Sentry scrubber settings and the real Sentry
HTTP transport using a fake client. A separate offline test runs the actual
Aptabase SDK initialization against an overridden HTTP client and asserts its EU
endpoint, App-Key header and consented batch, with no real requests. The existing CI Flutter suite includes these
tests. The offline website workflow retains the browser evidence.

## Daily GitHub acquisition snapshots

`analytics-acquisition.yml` supports manual dispatch and runs daily at 02:20 UTC
**only once the workflow exists on the default branch**. This draft PR does not
merge or activate it. It uses the default `GITHUB_TOKEN` to read all published
release asset counts and attempt the four traffic endpoints (views, clones,
popular referrers and paths). Traffic access may be denied with 403/404: that is
saved as **unavailable/unknown**, never as zero. Unexpected failures fail the
workflow. No PAT/secret is added.

Traffic endpoints generally require repository administration/read access:
if the default token is insufficient, an owner may separately authorize a
fine-grained PAT scoped only to this repo with **Administration: read** and
**Contents: read** (or a classic token with `repo` for private repositories).
Review its security/rotation first. This workflow deliberately does not reference
an absent PAT secret; wiring one requires a separately reviewed configuration
change. Release counts still work without it. Branch protection/org token
policies may also block the durable snapshot write; that failure is explicit.

Source of truth: dated JSON files on the separate **`analytics-snapshots`**
branch under **`data/acquisition/YYYY-MM-DD.json`**, with captured UTC time,
cumulative download counts, raw rolling traffic windows and availability flags.
The workflow creates this data branch from default HEAD if absent and changes
only dated data files, not main or app/site source. Same-day reruns replace that
day's file; Git preserves prior versions. Artifacts retain a secondary copy for
90 days. Snapshots do not belong in a personal wiki or analytics account:
downstream dashboards should index the dated files, use differences of release
asset counts and deduplicate overlapping daily traffic windows. GitHub traffic
only covers the previous 14 days; scheduling cannot backfill older data.
Counts are not unique people, successful installs or attributed conversions.
