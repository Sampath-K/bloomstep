# Free-tier deployment and authentication checklist

Do not deploy from a corporate directory or a development-credit subscription.
The operator chooses a personal production-eligible subscription. All CLI
resource commands must include its explicit `--subscription`; do not rely on the
global default. Identifiers and secrets belong in operator environment/state,
not committed config. Creation is authorized separately from enabling public use.

## Infrastructure

- Resource group in the chosen location.
- Cosmos NoSQL account: `--enable-free-tier true`, standard/manual throughput,
  automatic failover off, one region; shared database <=1000 RU/s, no autoscale.
  One `data` container partitioned `/userId`, default TTL enabled (`-1`),
  individual event/audit records 13-month TTL, transient rate-limit records 120s.
- SWA: SKU **Free**, managed HTTP API. Site root `site`, API root `api`,
  no separate paid Functions plan/storage/account. Node 22.
- External ID: customer tenant **Standard/A0**, not Premium; verify current
  free MAU allowance and federated provider capabilities.
- Budgets $1/$5 with appropriate alert receiver, operational kill switch,
  volume/storage quotas and no automatic upgrade. Budgets alone do not cap spend.
- No required Application Insights purchase. Required diagnostics/ingestion
  design stays a launch gap until a real free ingestion cap is verified.

## Identity

External tenant ARM resource:
`Microsoft.AzureActiveDirectory/ciamDirectories@2023-05-17-preview`,
location `Asia Pacific` (operator can choose before creation),
SKU `{name: Standard, tier: A0}`, tenant display name and country code.
If the tenant creation API requires human consent, use Entra admin center:
Entra ID > Overview > Manage tenants > Create > External; choose the personal
subscription/resource group, geography and domain. Then sign in to that
**customer** tenant before registering applications.

Register an API exposing delegated `Garden.ReadWrite`. Use v2 tokens and an
explicit audience. Add an application role `Bloomstep.Admin`, assigned explicitly
to product team users, never inferred from email or display name.

Register a public desktop client (no secret) with system-browser redirect:
`http://127.0.0.1:43821/callback`; verify this exact registered IP-loopback redirect
is accepted on the provider. The Flutter client uses PKCE S256, random state and
nonce, loopback-only HTTP listener with three-minute expiry and signature checks.
Grant only the API scope plus openid/profile/email/offline_access.
Associate the app with a sign-up/sign-in flow configured for email OTP.

Google: provider OAuth project, published consent settings, exact broker
federation redirect; credentials supplied **directly** to Entra provider settings.
Microsoft work/school: documented custom Entra OIDC federation; consent rules
can require organizational approval. Microsoft personal account federation is
not assumed from the built-in provider table; use a supported validated OIDC
configuration or explicitly report it unavailable. No silent email merging.

API app settings (deployment secret store only):
`COSMOS_CONNECTION_STRING`, `OIDC_ISSUER`, `OIDC_API_AUDIENCE`,
`OIDC_JWKS_URI`. The issuer and JWKS must be the tenant's exact discovery values,
not a generic `common` endpoint. Keys restricted to RS256. Every API checks
signature, issuer, audience, expiry, subject and delegated scope; admin checks role.

Client build defines are public identifiers, not secrets:
`OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_API_SCOPE`, `API_ORIGIN`.
Never ship a client secret. Default unconfigured builds are sign-in-gated previews.
Native credentials use OS secure storage; offline access expires after 30 days
since verified authentication. A refresh never resets that authentication deadline.

## Deployment and operational verification

SWA deployment token goes only in a GitHub Actions secret, not terminal output,
release assets or source. SWA deployment publishes site + API from the tested
commit. Check unauthenticated `/api/sync` returns 401 (or 503 when unconfigured),
then validate real login, two-account isolation, retries, second-device union,
feedback submit/status/reply, private ratings and account deletion.

Console is a deployment-verification tool accepting a short-lived product-team
token in page memory; no native tokens are exported automatically, no browser
token persistence, no public feedback. CORS for a preview operator origin must
be explicitly allowed in the service; same-origin SWA is the production default.

Before production: adversarial JWT/role tests, deletion-concurrency integration,
full provider flows, legal/privacy review, notification Focus/settings behavior,
install/upgrade/uninstall, artifact SHA-256, accessibility and cold-start/latency
measurements. Release status must stay honest until all MVP loops are observed.
