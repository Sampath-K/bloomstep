# Free-tier guard: read-only checks, not a spending hard cap

This source adds no paid resources, secrets, customer M2M, external email or
paid alerts. A separate **personal resource-directory** single-tenant app has
only enabled Application-role `Bloomstep.SpendGuard`, explicit self-SP assignment
and one GitHub environment FIC. It is distinct from the AggregateWriter and
customer SPA/API registrations. No customer client_credentials request is made.

## Owner provisioning

After source deployment, run with the existing approved Cosmos account name:

```powershell
.\infra\configure-spend-guard.ps1 `
  -ResourceTenantId '<approved personal resource tenant GUID>' `
  -SubscriptionId '<approved personal subscription GUID>' `
  -ResourceGroup bloomstep-free -SwaName bloomstep-free `
  -CosmosName '<existing approved Cosmos account name>' `
  -CustomerDirectoryName bloomstepcustomers261004 `
  -Repository Sampath-K/bloomstep -Environment bloomstep-operations `
  -ConfirmPersonalResourceTenant
```

No cloud mutation was performed by the source author. The script validates the
enabled explicit subscription/tenant, Free SWA, one-region Cosmos free tier,
manual400 RU on existing bloomstep/data container or shared database, approved
`FreeTrial_2014-09-01` spendingLimit On, existing repository API_ORIGIN, and existing
operations environment restricted exactly to main and approved feature branch.
It refuses unexpected/custom OIDC policy, trust, credentials, role grants or
Azure RBAC elevations. It does not change the aggregate worker's legacy FIC or
repository OIDC migration; that remains owner-owned.

GitHub repository REST supplies immutable owner/repository IDs. For the approved
repository the resulting FIC subject is exactly:
`repo:Sampath-K@72682617/bloomstep@1404357574:environment:bloomstep-operations`.
No IDs are hardcoded in provisioning/runtime source. Issuer is
`https://token.actions.githubusercontent.com`, audience
`api://AzureADTokenExchange`. Runtime checks those assertion claims before
exchange; Entra validates assertion signature/FIC trust.

The app requests v2 access tokens, URI `api://<guardClientId>`; its API token
audience is **GUID**, pinned in `SPEND_GUARD_OIDC_AUDIENCE`. Graph token acquisition
is silent tenant-only; ARM calls use the explicit subscription. Provisioning
identity needs approved app administration, RBAC assignment and selected SWA
configuration-write permissions. The **runtime** identity receives only:

- Reader (`acdd72a7-3385-48ef-bd42-f606fba81ae7`) on selected resource group.
- Cost Management Reader (`72fafb9e-0641-4937-9268-a91bfd8191a3`) on selected personal subscription.

No Contributor/Owner, Cosmos data-plane role, keys/listKeys, appsettings read/write,
customer directory Graph grant, user-flow change or secret/password/certificate.
Reader metadata requests inspect resource/SKU/SQL database/container throughput,
not garden items. Provisioning writes only the three pinned guard SWA settings,
with CLI output disabled to avoid returning existing settings/secrets.

Public operations-environment variables:
`GUARD_TENANT_ID`, `GUARD_CLIENT_ID`, `GUARD_SUBSCRIPTION_ID`,
`GUARD_RESOURCE_GROUP`, `GUARD_SWA_NAME`, `GUARD_COSMOS_NAME`,
`GUARD_CUSTOMER_DIRECTORY_NAME`.
`API_ORIGIN` remains the existing approved repository variable. Operational IDs
persist in tagged app/SP/FIC, RBAC assignments, SWA pinned settings and GitHub
variables, not committed files. Partial writes stay for owner inspection; matching
rerun is idempotent. Unexpected trust/role/elevation fails instead of repairing
broadly or deleting resources.

## Automatic/manual/reusable workflow

`.github/workflows/spend-guard.yml`: manual `workflow_dispatch`, reusable
`workflow_call`, every6hours cron,5-minute timeout, serialized finite concurrency,
only approved repository/main/feature branch, environment bloomstep-operations.
Scheduled runs become active only after default-branch merge. No PR/tag FIC
authorization; environment policy must be kept restricted.

`infra/spend_guard.py` uses standard-library HTTPS and normal resource-tenant v2
FIC exchange for ARM and the dedicated guard API. Assertion/access tokens are
masked before other output. Redirects rejected; transports/response sizes,
resource inventory, database and container enumeration bounded. No CLI login,
credentials extraction or cloud SDK dependency is needed by runtime.

Read checks:
- Approved trial quota and spendingLimit ON.
- Exactly three inspected RG resources: Free SWA, free-tier Cosmos, and the
  explicitly pinned existing customer ARM `Microsoft.AzureActiveDirectory/ciamDirectories`
  resource `bloomstepcustomers261004` with **SKU Base/tier A0**. Another directory,
  duplicate directory resource or non-Base/A0 SKU is not approved.
- Customer directory metadata uses documented read-only ARM
  `GET .../ciamDirectories/<pinnedName>?api-version=2023-05-17-preview`.
  Base/A0 is basic customer allowance metadata, not proof that SMS/M2M/premium
  add-ons are disabled. This ARM shape does not expose those add-on states;
  the guard cannot verify them and does not invent fields/Graph customer reads.
  Known RG cost still pauses, but billing latency and add-on visibility remain
  explicit limitations. No premium/M2M/SMS is provisioned by the guard.
- Cosmos one region, no serverless/analytical storage/continuous backup; exactly
  one provisioned manual400 RU throughput, no autoscale/additional throughput.
- Actual **resource-group MonthToDate** Cost Management query using PreTaxCost.

Unexpected paid configuration, spendingLimit OFF, known positive cost or
unavailable configuration read requests an authenticated **one-way application
pause**. Cost failure/empty response (including404 new-subscription GtmDimension)
is **unknown**, never zero. Unknown cost with independently verified approved
trial policy/free SKUs produces explicit warning—not fake pass and no fabricated
cost. A real numeric zero is labelled only current-query evidence. Billing latency,
credits/trial support/CostManagement coverage and permission errors prevent a
future $0 guarantee. Cost query unsupported for this subscription must remain
documented uncertainty, not invented API support.

Guard Reader cannot stop/deallocate Azure resources, change SKUs/settings, purchase,
upgrade or turn spending limits on. API pause reduces application work but existing
manual RU, operational reads/jobs and unrelated resources can still cost money.
It cannot inspect RG-external configurations or enforce subscription-wide caps.
Free-trial provider spending limit is independent Azure behavior, not a guarantee
created by this workflow. Owner must review drift/warnings/run failures promptly.
No automatic unpause, billing mutation or external paid notification exists.

API pause/resume schemas and privacy availability are in
`docs/backend-contracts.md`. Resume requires selected customer Admin's explicit
review of the exact pause ID; machine identity cannot call it.

## Offline validation and live owner proof

```powershell
npm --prefix api run check
npm --prefix api test
npx --yes --package=node@22 node --test api\test\*.test.mjs
.\infra\test-configure-spend-guard.ps1
Push-Location infra; python -m unittest test_spend_guard.py; Pop-Location
```

Tests cover pinned wrong issuer/audience/role/delegated scope, no worker elevation,
paused export/deletion/operations, strict one-way reason/idempotency and explicit
manual review; offline provisioning twice plus wrong-tenant rejection; actual
mocked runtime404 unknown-cost, known cost, SKU drift and legacy-subject rejection.
They are not deployed RBAC/billing/FIC/customer-role evidence. Owner must provision,
dispatch, inspect warning/real query outcome, validate unauthorized pause403/401,
and test a reviewed pause/resume with actual authorized identities before claiming
live operational coverage.

### Three-resource inventory correction / existing guard rerun

The real approved resource group includes the existing basic customer directory,
not just SWA and Cosmos. Runtime now pins its name and requires Base/A0, preserving
the strict three-type inventory and unknown-cost warning. Before first guard
dispatch, rerun the same provisioning invocation with
`-CustomerDirectoryName bloomstepcustomers261004`; it validates the ARM resource
and adds public operations-environment variable
`GUARD_CUSTOMER_DIRECTORY_NAME=bloomstepcustomers261004`. Existing app/SP/self-role/
FIC/RBAC remain idempotent; no new permissions, customer changes or API settings
are needed. Alternatively owner can set that single public environment variable
after independently verifying Base/A0. Source author made no live mutations.
