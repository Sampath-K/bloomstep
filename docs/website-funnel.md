# Customer acquisition and website funnel contract

The customer site explains Bloomstep without presenting operator tooling as a
product feature. `/releases/` preserves the release evidence and checksums;
`/console.html` is a separate noindex operator surface. Downloads remain ordinary
links and work without JavaScript, analytics, authentication, or the API.

## Behaviour and privacy contract

- First-party, anonymous website observations: `landing_view`,
  `primary_cta_click`, `download_click` with `channel: web` (`store` is reserved,
  not accepted yet), source category and download architecture.
- Website collection is unchecked/default-off. Only explicit per-visit consent
  starts a consented landing observation; it is not retroactive. Consent stays
  in page memory and resets on reload. Revocation stops uploads; earlier
  anonymous aggregate counts cannot be individually located.
- Source uses only the referrer hostname: known search hosts, other external
  hosts (referral), same-origin (unknown), absent referrer (direct/unknown in
  practice). Allow-listed bounded UTM presence selects campaign; values are
  discarded before persistence. No referrer URL or hostname is transmitted.
- No cookies, browser storage, visitor identifiers, IPs, full URLs, habit data,
  fingerprints or third-party analytics. Random per-event retry IDs exist only
  in memory. DNT or GPC disables sending, including consented receipt export.
- Only bounded daily UTC count vectors are stored. Repeated clicks on a stage
  in the same page are ignored. Transient server retry deduplication is bounded;
  across restarts/instances exact-once and unique visitors cannot be proved.
- Anonymous counts are observations, not people. Per creator decision, event
  conversion is available only with at least 50 events in both stages in the
  window. Label it "event conversion — not unique visitors; repeat visits and
  bots may be counted". Never describe it as user conversion. Low-count daily
  cells and subtractable small breakdowns are not returned. Ratios can exceed
  100%; never clamp. Clicks do not prove successful downloads, nor same-person
  transitions. Missing dates/opt-outs are unknown, never inferred zeros.
- Existing voluntary website/installer receipts may be exported in memory and
  explicitly linked in app Settings under separate default-off app consent.
  Existing authenticated ordered receipt cohorts are shown separately, never
  divided by anonymous counts. Web attribution requires a linked website
  receipt; installer-only and other app cohorts remain unknown channel.
- Admin API and panel require the existing `Bloomstep.Admin` JWT authentication.
  Linked counts and rates require 50 distinct contributing accounts in each
  relevant numerator and denominator. No anonymous-to-account matching.
- Synthetic readback has a distinct count document, small caps, an admin-only
  readback mode, and never enters real totals. Its receipt contains no real
  subject, URL, IP or user identifier.

## Edge / error matrix (tests precede implementation)

| Input / situation | Required result |
|---|---|
| Empty or invalid JSON | 400, no count |
| Unknown keys, stage, channel, category, architecture | 400, no count |
| Oversized body / declared body length | 413 before JSON parsing |
| UTM abuse: unknown field, >48 chars, URL/control characters | 400; browser discards abusive values |
| Missing / malformed referrer | direct / unknown; no URL sent |
| DNT=1, Sec-GPC=1 or browser GPC | no upload, server 204 without store access |
| Bot header, burst, shared quota / spending pause | reject 429 / 503; no download impact |
| Duplicate retry or repeated stage click | transient dedup / page-memory dedup; no persistent IDs |
| Concurrent store update | CAS failure 429; no blind increment or retry storm |
| Midnight / timezone | server-owned UTC day; browser dates never accepted |
| API outage | download proceeds immediately; quiet explicit privacy status |
| Absent day, opted out, <50 anonymous events / linked contributors | null / unknown / insufficient data, not zero |
| Synthetic production round trip | isolated daily aggregate only; excluded from real metrics |
| Store channel | reserved, rejected until a real Store integration exists |

## Free-tier limits and deployment

Reuse `bloomstep/data`; no new Azure resources. A transactional lifetime budget
and per-day count documents keep at most 90 UTC days. Daily TTL is anchored to
the server UTC date, so expiry does not need another visitor or a timer.
Limits: 400 accepted events/day, 10,000 lifetime accepted events, and a
global persisted 30/minute cap and 100/day/source cap. Synthetic caps: 20/day,
100 lifetime, 10/day/source. A bounded
per-process admission gate rejects excess traffic before database work; this
is not a distributed perimeter or a guarantee against malicious cold-start
traffic consuming free request allowances. Existing operational pause is
honoured. Fail closed at caps; downloads remain independent. Admin reads are
also process-rate-limited. Platform access/security logs are outside these
application aggregates and may contain standard request metadata.

`site/customer-config.json` is the source of truth for canonical origin,
current release assets/checksums and empty search verification placeholders.
Build inserts verification meta tags only for bounded valid tokens supplied
through deployment variables or that config. The owner must sign into Bing
Webmaster Tools and Google Search Console to obtain/verify those values and
submit `/sitemap.xml`. No real verification secret is committed. The current
website download is the already-published `v0.1.0-preview.12` unsigned
universal installer (21,542,145 bytes); ARM64/x64 links are collapsed troubleshooting
options only. The owner explicitly authorized this website pointer update before
manual acceptance so the complete website-to-installer journey can be tested.
Launch after Finish and the full owner journey remain unverified; no customer-ready
or safety claim follows from publication. `site/build.mjs` keeps the home and
releases pages aligned. The customer-site contract test pins both exact release
URLs and SHA-256 values. Preview.8 remains historical release evidence, not a
current download. Customer-provided preview.8 warning images retain their explicit
historical provenance and are not evidence of a warning on preview.12.

TODO(owner): supply controller identity, privacy contact, applicable legal basis
and processor/backup retention details. These facts are not invented by code.

CI verifies API schemas/type safety, site contracts and bundled assets; a
separate lightweight Lighthouse job measures the public pages against 90 for
performance, accessibility, best practices and SEO. Deployment packages the
customer pages, releases, console, robots, sitemap and original social image.
Production evidence belongs in session artifacts, not customer source.

`Website live readback` is a manual main-only GitHub workflow using the existing
`bloomstep-operations` federated aggregate-worker identity, not a new Azure
resource or paid service. Its isolated `/api/internal/website-proof` route
accepts only that worker role and returns lifetime accepted counters, never
customer data or real daily cells. The worker remains rejected by all customer
and Admin routes. The workflow downloads (never installs) the exact public
assets, verifies checksums and persists its anonymous synthetic before/after
proof as an artifact.
