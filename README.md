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

## Status

**Engineering preview, not the complete MVP.** The persistent garden and core
widget flows are implemented. Public builds are sign-in gated until real personal
identity/cloud services are provisioned and verified; there is no fake login.

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

The small static website lives in `site`; authenticated Functions live in `api`.

## Production two-account isolation acceptance

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
