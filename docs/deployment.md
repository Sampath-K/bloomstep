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

Google uses the documented built-in customer provider. Create an OAuth **web**
client in a personal Google Cloud project; billing and Gmail APIs are not needed.
Use only `openid profile email`. For testing, add the owner's Google account as
a test user; testing is not publicly available sign-in. Configure the authorized
domains/callbacks in the current
[Google federation instructions](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-google-federation-customers).
Treat the actual upstream authorization request's `redirect_uri` as authoritative,
not a guessed callback from a documentation template. Our isolated runtime
traversal observed the tenant-ID host with
`https://<tenant-id>.ciamlogin.com/<tenant-id>/federation/oauth2` for both
Google and MSA. Google's documented built-in OIDC variants can instead use
`/federation/oidc/accounts.google.com`; registering only those variants does not
authorize the observed OAuth2 callback. Add the exact observed HTTPS URI to
the existing Google web client's **Authorized redirect URIs**, preserving
existing entries. Never add a wildcard or the native app's loopback callback.
Paste credentials **directly** into Entra's built-in Google provider, never into
chat, source, native build defines or SWA settings. Enable Google in the existing
customer user flow. Public consent publishing/verification is a separate gate.

Microsoft **personal** Outlook/Hotmail accounts are explicitly supported by the
current [customer MSA federation instructions](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-microsoft-accounts-federation-customers).
Use a separate confidential federation registration (not the public desktop
client), multi-org + personal-account audience and v2 tokens. Its documented web
callbacks include `https://<subdomain>.ciamlogin.com/<tenant-id>/federation/oauth2`
and the equivalent `<subdomain>.onmicrosoft.com` tenant path. The deployed
tenant-ID issuer actually requested
`https://<tenant-id>.ciamlogin.com/<tenant-id>/federation/oauth2`; subdomain-only
registration failed with `invalid_request`.
`infra/configure-identity.ps1` prepares this registration without exporting a
secret, includes the observed canonical callback and reconciles existing
managed web callbacks additively with readback; the operator creates/pastes its secret directly in Entra's custom OIDC
provider and enables it in the user flow. The provider configuration is:

- Metadata: `https://login.microsoftonline.com/consumers/v2.0/.well-known/openid-configuration`.
- Provider issuer alias: **`https://login.live.com`**, exactly as Microsoft's MSA
  instructions prescribe. The consumer discovery document actually returns the
  consumer tenant's `microsoftonline.com/.../v2.0` JWT issuer; do not confuse this
  special broker-provider setting with the API's accepted token issuer.
- Code response, `openid profile email`, **Client Authentication: `client_secret`**
  in the current Entra UI, subject `sub`, display name `name`; no unnecessary
  required profile attributes. Graph represents this as
  `oidcClientSecretAuthentication`. Do not substitute unsupported
  `client_secret_basic` or `private_key_jwt` options.

No broker replacement is required for this documented path. Actual Google and
MSA sign-ins, consent, claims mapping and callback behavior must still be observed.
Before asking a customer to retry, traverse each option in a fresh isolated,
unauthenticated browser context and record only the public upstream `client_id`
and exact `redirect_uri`. Never inspect the customer's existing browser, persist
full authorization URLs/state/nonce/cookies or capture authentication screens.
Compare the observed URI with the selected web registration. After correction,
confirm that the isolated provider page offers credential entry rather than a
redirect mismatch, without entering credentials. This is registration proof,
not successful customer authentication or a token exchange.
Microsoft work/school federation is a different configuration and can need
organizational approval; `common` is not a substitute for personal-account setup.
Never merge gardens by email or treat resource-tenant ownership as an API role.

### Customer-visible Bloomstep branding

Product-owned names are **Bloomstep**: Windows window/file/product metadata and
original flower icon, native sign-in/callback/error text, invitation email
subject/body, website title/favicon/download controls and operator popup.
The executable, protocol, storage keys and package identifiers remain lowercase
machine identifiers; never rename authentication hosts or rewrite security errors
to hide their origin. Installer publisher remains the existing "Bloomstep
contributors" label. Scaffold copyright/company claims are removed; legal
controller/contact/copyright approval is still required, not invented.
`path_provider_windows` and secure-storage v4 derive their default data path from
executable company/product metadata. Before either storage or the instance lock
opens, Bloomstep pins their support/cache directory to the existing machine
namespace `com.bloomstep\bloomstep` under the corresponding Windows known folder.
Changing customer-visible branding therefore neither relocates gardens/DPAPI
credentials nor creates a second instance lock. No private file is copied,
decoded, migrated or deleted; the legacy folder name is a deliberate persistent
identifier, not a customer-facing legal company claim.
All three prior published previews pin `flutter_secure_storage_windows` 4.1.0.
Windows storage therefore disables that plugin's obsolete pre-v4 native migration
path, which independently derives directories from executable metadata. Other
platform options are unchanged. A Windows-only regression writes a synthetic
record using the actual v4 DPAPI backend in an isolated temporary preview.3 path,
reinitializes storage with the stable branded provider, and verifies the same
record/file survives unchanged. It never reads a customer credential store.

`tool/generate_brand_assets.py` generates the original flower ICO/PNG and
245-by-36 sign-in wordmark from the source drawing. Its optional `--font` selects
an available font; checked-in outputs need no image library during normal CI.
The generator uses Pillow, and default Windows Segoe UI Bold. Only the three
explicit public brand PNGs are tracked under `site/assets`; bundled auth/config
outputs remain ignored.

After explicit customer-branding authorization, run
`infra/configure-customer-branding.ps1 -TenantId <customer-id> -LogoPath
site\assets\bloomstep-wordmark.png -ConfirmCustomerBranding` with existing
customer-tenant Graph access. It verifies the tenant before mutations, creates
branding only if absent, preserves unrelated content keys/MFA strings, writes
only supported product text/banner/favicon, and verifies readback.
The parent `/branding` alias follows `Accept-Language`; actual default fallback
is `/branding/localizations/0`, distinct from `/localizations/en-US`.
The observed tenant returned500 for parent-alias PATCH, while both documented
localization writes succeeded. Do not waive service errors or claim English-only
branding covers other browser languages. Actual isolated English and French
fallback pages now show the Bloomstep wordmark and "Sign in to Bloomstep".
The fallback text is English, not a claim of fully localized product copy.

Company branding does **not** rename the address-bar `ciamlogin.com` hostname,
Google's destination-domain label, Microsoft's own account page, or the hosted
service's generic localized browser-tab title. Keep those trusted-service labels
truthful. The native login and website explain that Microsoft hosts Bloomstep's
secure sign-in at `ciamlogin.com`; passwords stay with the chosen provider.

Google's actual unauthenticated page currently says **"to continue to
ciamlogin.com"**. Existing-project operator action is at
[Google Auth Platform > Branding](https://console.cloud.google.com/auth/branding):
review/set App name **Bloomstep**, accurate approved home/privacy/support/contact
information, then review the actual draft/verification/published state.
For production app name/logo display, Google's current
[brand-verification requirements](https://developers.google.com/identity/verification/authentication-verification)
require verification and **Publish branding**, not merely Save or changing an
OAuth client's internal name. Google requires authorized-domain ownership
verification; shared Microsoft broker domains can need provider-specific review,
so no approval or displayed-name guarantee is inferred. Do not submit external
review, invent contacts, switch production audience or change credentials without
operator approval. No authorized Google management session is available to the
implementation agent; this surface remains a genuine branding gate.

Microsoft-hosted email OTP templates/sender are a separate provider surface,
not changed by invitation email copy or a sign-in heading. A custom OTP sender
requires a supported
[email OTP send extension and mail relay](https://learn.microsoft.com/en-us/entra/identity-platform/custom-extension-email-otp-get-started).
No relay, new credential-handling endpoint, sending service or paid add-on is
provisioned under the current $0 budget, and no email delivery/branding is claimed
without a genuine approved observation.

An owned `login.<product-domain>` address requires domain/DNS control and the
documented [custom URL domain infrastructure](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-custom-url-domain),
including Azure Front Door Standard/Premium. It is not a free display-name
setting and is outside the approved budget. No purchase, license upgrade,
issuer/callback migration or counterfeit sign-in page is performed.

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

Managed SWA replaces the standard `Authorization` header with its own backend
token ([Azure team's confirmation](https://github.com/Azure/static-web-apps/issues/34)).
Native sync/deletion and the same-origin operator console therefore carry the
real broker token in **`X-Bloomstep-Authorization: Bearer ...`**. The API validates
that token's exact issuer, audience, signature, expiry, subject, scope and role.
SWA's proxy token/client-principal header is never a substitute for app identity.
Missing or invalid client tokens fail closed; this is not an authentication bypass.

Do not use customer-tenant `client_credentials` for a scheduled worker: current
[External ID pricing](https://learn.microsoft.com/en-us/entra/external-id/external-identities-pricing)
classifies it as a paid M2M add-on, separate from the user MAU allowance. An
internal aggregation worker can instead use a tightly scoped real application
role/federated credential in the approved personal **resource** directory.
Its separate pinned issuer/audience is accepted only for internal aggregation,
never for customer garden or team feedback routes. Do not enable premium/SMS/M2M.

## Deployment and operational verification

## Production branch after engineering merge

The shared Free Static Web App now follows `main`. Align the existing resource
branch with the repository default branch without changing its Free SKU.
`.github/workflows/azure.yml` deploys only main, explicitly passes
`production_branch: main`, and serializes uploads to the one shared production
environment. Feature pushes run contracts/native CI but do not compete with
production deployments or consume preview-environment slots.

The first main release-link deployment exposed a stale feature-branch resource
binding (`No matching Static Web App environment`). The resource binding and
workflow were repaired, rather than treating a successful simultaneous feature
upload as a successful main deployment. Post-deployment gates require401 for
all protected sync/team/invitation/operational routes using their actual methods. and operational verification

### Browser operator console: real public-client PKCE

The operator console no longer accepts pasted bearer tokens. It uses locally
bundled official `@azure/msal-browser`, a distinct single-tenant customer **SPA**
registration and user-initiated popup sign-in. No secret is created/read/shipped;
no CDN or external analytics is used. Browser popup redirect is exactly
`https://<selected-SWA-host>/operator-callback.html`. The callback page contains
no token extraction/export/logging script; MSAL completes its popup flow.

`infra/configure-console-identity.ps1` requires:
CustomerTenantId, ResourceTenantId, explicit SubscriptionId, ResourceGroup,
SwaName, existing customer ApiClientId, AuthenticationEventsFlowId,
CustomerIssuer, Repository (`Sampath-K/bloomstep`) and
`-ConfirmPersonalSubscription`. Run only after explicit owner approval.
It validates enabled personal subscription/resource-directory binding, existing
Free SWA/repository API_ORIGIN, exact HTTPS customer ciamlogin issuer/discovery,
and Graph organization's selected customer tenant. Graph token acquisition is
tenant-only (no mutually exclusive subscription argument).

The script creates/reconciles the tagged `Bloomstep operator console (public SPA)`
app/SP with only the exact SPA callback and delegated Garden.ReadWrite permission
to the existing API; web/native fallback redirect platforms are cleared on that
dedicated managed app. Existing secrets, mismatched bindings, ambiguous apps or
broader consent grants fail for explicit review. Narrow AllPrincipals consent
is granted for Garden.ReadWrite only; it does **not** assign Bloomstep.Admin.

It preflights and associates the existing user flow via documented Graph v1.0:
`POST /identity/authenticationEventsFlows/{flowId}/conditions/applications/includeApplications`
with `{"@odata.type":"#microsoft.graph.authenticationConditionApplication","appId":"<SPA appId>"}`,
then verifies the association by reading it back. Unsupported/denied/conflicting
association is an explicit failure, never fake login/manual token fallback.
[Official association contract](https://learn.microsoft.com/en-us/graph/api/authenticationconditionsapplications-post-includeapplications?view=graph-rest-1.0).
The existing flow's provider settings are untouched. Partial provisioning remains
for idempotent rerun/review; no rollback/deletion or broad permission repair occurs.

Only public repository variables are persisted:
`CONSOLE_CLIENT_ID`, `OIDC_ISSUER`, `OIDC_API_SCOPE`. Existing `API_ORIGIN` must
already match the selected deployment. No operational IDs are committed.

**Owner build wiring (azure.yml remains owner-owned):**
`npm --prefix site ci`, `npm --prefix site test`, `npm --prefix site run build`
with all four public deployment environment variables:
CONSOLE_CLIENT_ID, OIDC_ISSUER, OIDC_API_SCOPE, API_ORIGIN. The build bundles MSAL
and console code into ignored `site/assets/console.js`, writes callback theme
CSS, and emits ignored `site/operator-config.json` containing only the public
client ID/issuer/scope. Deploy these generated files along with the site.
No source maps or secrets are emitted. All-unset builds emit an explicitly
unconfigured config (sign-in disabled); partial settings fail the build.
The source index now references the bundle: publishing without building is **not**
a ready console. Same-origin runtime config is fetched no-store; stale config
deployment/CDN caching must be reviewed by the owner.

MSAL credential/token cache is **MemoryStorage**; only temporary PKCE/interaction
state uses sessionStorage. Pagehide/local sign-out increments session generation,
clears MSAL cache/temporary state, aborts pending requests and erases private
feedback/dashboard DOM; late popup/token/request completion cannot revive private
data. Local sign-out clears the console but does not promise global identity-
provider SSO logout. Reload requires explicit sign-in; there is no raw token
field/clipboard/persistent credential cache or automatic interactive fallback.

Same-origin `/api/team/*` calls use only X-Bloomstep-Authorization with the actual
customer API access token; redirects are rejected. API 401 explicitly asks for
sign-in; 403 explicitly requires customer Bloomstep.Admin assignment. UI does not
infer privileges from email/subscription owner or treat ID-token roles as API
authorization. Founder/human customer identity must be explicitly selected and
assigned the existing API Admin app role. Browser registration association and
delegated consent do not supply that role.

Source tests cover pinned public configuration, popup failure, memory-state
clearing/late completion, custom-header transport, rejected roles/401/403 and
missing manual/CDN fallback. Source build/syntax and Node22 tests are **not**
live popup/PKCE/user-flow/role/API evidence. Owner provisions, builds/deploys,
observes actual browser sign-in, denied non-Admin and approved Admin response,
private feedback loop and pagehide/logout clearing before claiming readiness.

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

## Personal resource-directory daily worker (source-only provisioning)

`infra/configure-aggregate-worker.ps1` prepares the approved worker using cached
Azure/Graph and GitHub CLI credentials. It does not log in interactively, export
tokens, create passwords/certificates, create paid resources, change customer
apps/user flows/providers, or request customer-tenant M2M tokens. This script and
workflow are source contracts; an owner must separately authorize and run actual
provisioning and verify live FIC/token/API behavior.

Example (public identifiers supplied by the owner, not copied from another
directory):

```powershell
.\infra\configure-aggregate-worker.ps1 `
  -ResourceTenantId '<personal-resource-tenant-guid>' `
  -SubscriptionId '<explicit-personal-subscription-guid>' `
  -ResourceGroup '<existing-resource-group>' `
  -SwaName '<existing-free-swa>' `
  -Repository 'Sampath-K/bloomstep' `
  -Environment 'bloomstep-operations' `
  -FeatureBranch 'sampath-k-bloomstep-mvp-implementation' `
  -ConfirmPersonalResourceTenant
```

**Prerequisites:** `az` and `gh` authenticated with resource-directory app
administration and repository/environment administration permissions. Repository
`API_ORIGIN` must already equal the selected SWA's HTTPS default hostname; the
script checks it, does not replace it. Both allowed branches must exist.
The tenant/subscription must genuinely be the owner's approved personal resource
directory, not a corporate tenant or customer external directory. The explicit
confirmation is an operator assertion: matching subscription/tenant IDs alone
cannot prove personal ownership or free billing eligibility.

Before any Graph operation or mutation, the script verifies the explicit
subscription is enabled and bound to ResourceTenantId, and the selected existing
SWA has SKU Free. Every Azure resource command includes that SubscriptionId.
Graph token acquisition uses **tenant-only** `az account get-access-token
--tenant <ResourceTenantId> --resource https://graph.microsoft.com`; Azure CLI
forbids combining tenant and subscription on that token command. ARM commands
still use the explicitly validated subscription. A token-command failure is
reported neutrally, not automatically diagnosed as a missing human login.
Graph access uses a cached delegated token acquired silently for that resource
directory; no client-credentials request to the customer directory is made.

It idempotently creates/reconciles one clearly tagged single-tenant app named
`Bloomstep aggregate worker (personal resource directory)` and its service
principal. The app uses v2 access tokens, `api://<appId>`, and one enabled
**Application-only** role `Bloomstep.AggregateWriter`. The worker service
principal is explicitly assigned that role **on itself** as resource API; no
scope/application permission or Azure subscription-owner role is inferred.
Duplicate/untagged/mismatched apps, unexpected roles/application grants,
password/key credentials, extra FICs and changed FIC trust fail for manual review.
No unrelated app is modified. Newly provisioned directory objects/role changes
may require propagation; rerun safely after checking the sanitized failure.

The single FIC is exactly:

| Field | Value |
| --- | --- |
| Name | bloomstep-operations-github |
| Issuer | https://token.actions.githubusercontent.com |
| Subject | repo:Sampath-K/bloomstep:environment:bloomstep-operations |
| Audience | api://AzureADTokenExchange |

The stable GitHub environment uses custom **branch** deployment policies for
exactly `main` and `sampath-k-bloomstep-mvp-implementation`; no tag/PR/wildcard
policy is accepted. Unexpected pre-existing policies fail for review instead
of silently admitting another ref. Existing wait timers/reviewers/admin-bypass
settings are retained; unrecognized custom protection rules fail rather than
being overwritten. Because the FIC subject is environment-scoped, the environment
branch controls and workflow job ref guard are essential: the subject alone
does not encode main/feature/PR. Repo administrators must not loosen those
controls or run untrusted code through this environment. The script rejects
repository custom OIDC subject policies; this workflow expects GitHub's default
environment subject.

Only these production SWA app settings are added/reconciled; all other settings
remain untouched:

- `AGGREGATE_OIDC_ISSUER`: discovery's exact
  `https://login.microsoftonline.com/<ResourceTenantId>/v2.0`.
- `AGGREGATE_OIDC_AUDIENCE`: worker **appId GUID**, the v2 access-token audience,
  not `api://...`.
- `AGGREGATE_OIDC_JWKS_URI`: resource-directory discovery HTTPS JWKS URI.

Only two nonsecret GitHub **environment variables** are added/reconciled:
`WORKER_TENANT_ID` and `WORKER_CLIENT_ID`. There are no GitHub/Entra secret values
created, and no change to primary customer `OIDC_*`, Cosmos, SKU or resource
count. Partial provisioning is possible: errors do not roll back environment/
directory changes. Review current objects and rerun; never delete role/budget
state to force success. Existing ledger counters and worker action limits remain.

### Workflow execution and honest activation

`.github/workflows/aggregates.yml` supports explicit `workflow_dispatch` and a
daily **02:20 UTC** schedule. GitHub scheduled runs become active **only after
the workflow is merged onto the repository default branch**; pushing this
feature branch does not activate cron. Before merge, owner can manually dispatch
the approved feature branch once real provisioning and API deployment are
verified. Job rejects other repositories/refs and uses `bloomstep-operations`.
Existing environment reviewers/wait timers may require human approval.

The job grants only `contents:read` and `id-token:write`, has a five-minute
timeout and one named concurrency group (no cancel-in-progress). It runs no
checkout/dependencies/third-party analytics and creates no files with tokens.
It requests GitHub's assertion audience `api://AzureADTokenExchange`, masks the
assertion immediately, and exchanges it at the **normal personal resource-tenant**
`https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token` endpoint:

```text
client_id=<WORKER_CLIENT_ID>
scope=api://<WORKER_CLIENT_ID>/.default
grant_type=client_credentials
client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
client_assertion=<masked GitHub assertion>
```

The returned access token is masked before use. Then it sends strict body `{}`
to `POST <API_ORIGIN>/api/internal/aggregates` using **only**
`X-Bloomstep-Authorization: Bearer <actual resource-token>`. The backend chooses
the completed previous UTC day. The workflow refuses redirects, caps response
bytes, uses bounded request timeouts, fails on HTTP/JSON/auth errors without
printing response bodies, and emits only the completed snapshot count. It does
not perform broad retry loops/backfills or print assertions/access tokens.

This normal resource-directory workload flow is intentionally separate from
**paid customer External ID M2M**. No customer addon is enabled. Ordinary
GitHub runner allowances and resource-directory/free-tier eligibility still
need owner verification; the source cannot promise zero billing for an account
without checking those allowances. No paid Azure plan or resource is introduced.

**Owner live acceptance:** inspect the app role assignment and FIC, exact
environment branch policies, nonsecret settings, issuer/audience; verify the
deployed team routes reject no token with 401; manually run this job and observe
successful aggregate snapshots and audit records without leaking tokens.
Verify the real resource worker is rejected on garden/team endpoints and lacks
other grants; exercise the worker kill switch/budgets. Automatic runs remain
unclaimed until default-branch merge and a scheduled run is actually observed.
## Owner-record deletion rollout (approved, live verification pending)

Deploy the new backward-compatible sync deletion contract before installing the
new native candidate. SQLite migrates existing v4 gardens to v5 in the same
stable support/credential namespace; no account/session migration, issuer,
callback, provider registration, Admin role or OS permission change is involved.
Retain the normal signed-in account and existing content during upgrade.

Existing clients may upload empty/default deletion arrays and ignore the extra
response field. The service nevertheless suppresses their stale deleted IDs.
New clients send owner-scoped UUID markers before surviving records and apply
remote suppression before merge. Interrupted active-content cleanup must finish
before success/readback acknowledges the marker; pending cleanup resumes on
sync, with explicit conflict/quota/storage errors instead of a success fallback.
See `backend-contracts.md` for permanent ID-only retention, preview bounds and
processor/export-copy boundaries. Normal unsigned distribution remains labeled
as an engineering candidate, not full-MVP acceptance or a crash/cohort result.
