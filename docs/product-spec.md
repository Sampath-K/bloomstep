# Bloomstep product contract (Flutter v0.4)

This is the public, implementation source of truth for the approved Windows-first
MVP. The older PWA/Tauri install, push and AI proposals are superseded. No private
account details, subscription identifiers, identity secrets or Store research
belong in this repository.

## Outcome and trust

Help people make one tiny behavior natural and eventually graduate it. The north
star is habits graduated per activated user at 30/60/90 days, not time in app.
Notification opt-out, pushy feedback, early uninstall, shame-related feedback and
account deletion are guardrails. Ages 16+. Not medical advice.

Tiny first (less than 30 seconds); celebration first; autonomy; privacy by
default; coming back is a success. Plants never wilt, die, or lose a stage.
No punishment, loss-aversion streak mechanics, leaderboards, ads or AI in MVP.
Content is original, with factual attribution to behavior design research.
Do not use a third party's trademark in the product name or marketing headline.
No copied book exercises or validated questionnaire wording without verified
licensing. Self-reflection wording must not be described as clinically validated.

## Platforms and budget

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
| Habit | Sign in; aspiration; five starter recipes; custom anchor/tiny behavior/celebration; practice celebration; choose among three species; plant; persistent SQLite; prompt to practice now. First habit target <90s, first check-in same session. Recommend one habit initially; soft cap three with explicit override. |
| Check-in | Did it / Did more / Not today; optional forgot/too hard/anchor absent/motivation reason; no response is no data. Personal celebration within 300ms; persistent client event IDs; one effective result per habit per **local** date; edits and undo append events; sync retries idempotent. |
| Garden | Five stages: seed, sprout at 3, sapling at 10, budding at 21, bloom at 30 practice days plus score >=4/7. No negative stage changes after rest or corrected data. Permanent Grove after graduation. Deterministic species/plant variation, vector visuals, screen-reader labels and reduced motion. Optional day/night, seasons, decor, pollinators and return celebration, never a penalty. |
| Reminders | Real Windows local toasts and tray actions; opt-in permission/context; optional autostart; chosen local time, quiet hours default 21:30-07:30; <=1 prompt/habit/day and <=3 notifications/app/day; snooze/fewer/off. Three ignored halves frequency, seven pauses with in-app explanation. Device scheduling, not paid service. Respect OS settings/Focus; never use urgent bypass. Re-evaluate local time/DST/travel. Median of last 14 check-in times after five samples, rounded 15m. |
| Identity | Real OIDC broker with Microsoft account/work-school, Google and email OTP; system browser authorization code + PKCE, unpredictable state and nonce; validate token signature/issuer/audience/expiry/nonce. Never embedded browser or fake sign-in. Provider/platform capabilities verified, not assumed. Refresh credentials in OS secure storage. Authenticated offline sessions; per-account isolation; sign-out clears device data with unsynced-data warning. No silent email-based linking. |
| Sync | Functions JWT verification on **every** endpoint, server-derived partition `/userId`, Cosmos persistent records, retry, append-event union and last-writer-wins recipe/settings with deterministic conflicts. Never accept client-selected account identity. Two-device verification including offline edits/restarts. |
| User learning | Weekly reflection under 60s; four 1-7 naturalness items every 14 days; explain deterministic Recipe Doctor based on check-in reasons (specific/reliable anchor, smaller behavior, reconsider aspiration/celebration). Two consecutive naturalness scores >=5.5 plus practice >=60% of last 28 days graduates, not a fixed day count. Original content; no AI. |
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
