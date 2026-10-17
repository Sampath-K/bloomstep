# Bloomstep

Grow tiny habits into a flourishing garden. Inspired by the behavior design research of Dr. BJ Fogg.

Bloomstep is a Flutter app: Windows first (direct download, then Microsoft Store), then iOS/iPadOS, Android and macOS from the same code.

## Develop

```powershell
flutter pub get
flutter test --dart-define=BLOOMSTEP_TEST_BUILD=true
flutter run -d windows
flutter build windows --release
```

Before submitting a UI change, use the canonical
[design and validation bar](docs/product-spec.md#human-centered-garden-design-and-validation):
inventory affected surfaces/states; write failing behavior/accessibility contracts;
inspect synthetic-labelled actual renders at small windows/200% text, light/dark
and reduced motion; exercise keyboard/focus, errors/recovery and privacy;
record per-dimension/per-surface baseline/after scores and exact checks with
evidence. Preserve any higher evidenced baseline. Identify telemetry necessity
without adding unconsented events, and mark native/Narrator/performance/real-user
conditions **NOT OBSERVED** until actually checked. Scores are expert heuristics,
not measured engagement or certification. The current
[visual review](docs/visual-quality-review.md) records results and open gates.
Use the [app experiment policy](docs/app-experiments.md) for the selected,
replaceable GrowthBook adapter; source wiring is not hosted setup or activation.

## Status

For a private self-service dependency/evidence view (separate from the app and
public site), see [local project status](docs/project-status.md). It reads GitHub
with the existing `gh` login and never equates merge or publication with verification.
Run `node tool\project-status\status.mjs serve --poll-seconds 60` for bounded local
source polling; browser snapshot refresh and unavailable agent APIs are labeled separately.

**Engineering preview, not the complete MVP.** The persistent garden and core
widget flows are implemented. The first garden screen has a compact profile;
signed-out users can plant into a separate device-only garden without sync or
analytics. Real provider sign-in opens the account-owned garden; there is no fake
login or automatic transfer of device habits. Provider/cloud acceptance remains
an independent gate.

An empty device or account garden opens the dismissible first-habit flow
automatically, once per garden per app launch. Each step accepts typed Anchor, Action and Celebration
values or suggestions. After saving, a brief seed-to-sprout preview explains
growth; reduced motion shows a static plant. Existing habits and other active
routes are not interrupted; cancellation does not loop in the same launch.

See [product contract](docs/product-spec.md), [iteration/edge ledger](docs/status.md)
and [deployment prerequisites](docs/deployment.md). The current
[MVP exit matrix](docs/mvp-exit-matrix.md) records observed evidence and exact
remaining acceptance gates. Unattended non-provider engineering checks are
separate from deferred provider, actual Windows delivery and public-launch
acceptance; adapter acknowledgments are not delivery evidence.

The [synthetic acceptance harness](docs/synthetic-automation.md) is test-only;
it is not a production sign-in path or proof of provider, Cosmos, notification,
accessibility or population acceptance.

[Authentication observability](docs/auth-observability.md) documents the bounded,
account-consented session/token stages and explicitly unknown pre-auth/provider
coverage; it is not a complete sign-in funnel.

The [free analytics sandbox](docs/analytics-sandbox.md) is staging-only,
default-off and independently consented. It includes owner signup/key steps and
the offline browser check; production has no third-party analytics enablement.

The small static website lives in `site`; authenticated Functions live in `api`.

## Production two-account isolation acceptance

**Preferred automated path:** dispatch **Production two-account isolation
acceptance** (`production-isolation.yml`). Dedicated `bloomstep-test-a`,
`bloomstep-test-b` and `bloomstep-test-admin` local customer accounts use only the
separate `bloomstep-test-email-password` flow and assignment-required
**Bloomstep automation test client**. Production OTP, Google and MSA providers
are unchanged. The test client is a native public client with a localhost
callback; headless Chromium uses hosted sign-in plus authorization-code PKCE,
never ROPC, saved browser sessions or owner credentials.

The workflow obtains credentials from the six `BLOOMSTEP_TEST_*` GitHub secrets,
and the public client ID/provisioning receipt from repository variables.
`infra/provision-automation.mjs` is the source provisioning contract: approved
cached customer-tenant Graph access creates a temporary confidential principal
with only EventListener.ReadWrite.All, IdentityProvider.Read.All and Policy.Read.All;
its credential lives in memory for at most 45 minutes. All temporary role
assignments, SP and app are deleted in `finally`, with application readback.
Passwords go to GitHub through `gh secret set` stdin only after genuine hosted
sign-in and API verification. No credentials are printed, committed or saved
to disk. Security defaults remain on and customer policies are never modified.
Any extra-verification/MFA prompt fails the helper; it is not bypassed.

The acceptance run writes colliding habit/feedback IDs with different fixture
content into A and B's own partitions, verifies each account's own readback,
rejects peer selectors in both directions, requires 403 on ordinary team routes,
and requires 200 for Admin metrics. It saves server isolation receipts, then
deletes only its own test fixtures via the existing sync deletion contract and
verifies removal. Normal quota reservations and bounded deletion tombstones
remain; it does not delete accounts or directly write Cosmos. Cleanup failure
fails acceptance. The readable `production-isolation-evidence` artifact contains
only labels, outcomes, audit IDs and sanitized provisioning/cleanup metadata,
not tokens, emails, subjects, user hashes, content, screenshots or browser traces.
GitHub secrets/variables and the tagged directory test objects are the persistent
automation source of truth; no reusable login credential is stored in scripts.
Provider acceptance is pending until a real workflow run and its receipts pass.

**Optional owner-driven path (no credentials handed over):**
In the production `/console.html`, open two tabs, sign in once in each
(1081c6f4 ordinary MSA in A; 067a5c60 ordinary MSA in B).
Click **Show my account hash** in each. Exchange only those displayed hashes
between tabs using the **Other signed-in account's userId hash** field, then click
**Verify my data isolation** in each tab. Never copy tokens or credentials.
Both tabs must report verified with different own hashes and audit IDs.
Optionally repeat customer sync checks with 159a21cf Google Admin; that account
is intentionally permitted to read/reply to other accounts' team feedback.

The Admin-free `GET /api/account/isolation` returns only the verified caller's
hash. Its `POST` invokes the existing own-data sync handlers using the same
authenticated request headers: own GET and empty POST, then attempted peer
selection in GET query and POST payload. Both peer selectors must be rejected
before store access (400). An ordinary account must also be denied team feedback
(403). Admin team feedback access is intentionally authorized, not an isolation
failure. Private customer feedback is `voice` data in the own sync partition.
The response contains only own counts, own hash, outcomes and audit ID.
No habit or feedback is created, edited or deleted; normal sync bookkeeping,
account initialization and bounded quota reservations still apply.

Successful evidence is an `audit` document in the caller's own Cosmos partition,
with `action = "data_isolation_check"`, `userId = partition`, `checks`, `ts` and
a 30-day TTL. It contains no content, peer hash, subject, token or credentials.
Audit creation failure fails the request rather than claiming success.
The source of truth is these Cosmos receipts, not browser storage; the console
clears all displayed hashes/results on sign-out and does not index personal data.
Use existing read-only Cosmos access to verify the two returned audit IDs:

```sql
SELECT c.id, c.userId, c.partition, c.checks, c.ts
FROM c
WHERE c.type = "audit" AND c.action = "data_isolation_check"
  AND c.id IN (@auditA, @auditB)
```

Require two receipts for distinct own hashes, `userId = partition`,
`ownRead = ownEmptySync = 200` and `foreignRead = foreignWrite = 400`.
Each ordinary-account receipt must have `teamFeedback = 403`; an optional
Admin receipt must say `admin-authorized-not-tested`. Each outcome is generated server-side,
not accepted from browser claims. Peer selection is rejected, never queried.
This is bounded live partition-boundary acceptance, not an exhaustive security
audit. Production acceptance remains pending until both genuine account runs
and their persisted receipts are observed; synthetic JWT tests do not replace it.

CI tests and packages per-user unsigned Windows ARM64 and x64 preview installers
using Inno Setup. Tag releases are explicitly prereleases with checksums.

```powershell
cd api
npm ci
npm run check
npm test
```
