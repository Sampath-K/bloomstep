# Microsoft profile photos: blocked draft foundation

This stacked follow-up does **not** enable photos for the current CIAM/MSA
configuration. It preserves PR #31's avatar + Sign out surface, Google picture
claim path, and once-per-garden-per-launch empty-garden invitation.

## Blocking prerequisite: prove the same Microsoft account

The CIAM identity is validated by the existing customer-tenant flow. Its `oid`
and `sub` identify the customer-tenant user, not the upstream personal Microsoft
account. The upstream MSA `sub` is pairwise to the separate confidential
federation client; it cannot be compared to a different public client's `sub`.
Email, display name, provider label, login hint, and a user's choice in the
browser are not proof of linkage.

The [documented CIAM OIDC claims mapping](https://learn.microsoft.com/en-us/entra/external-id/customers/reference-oidc-claims-mapping-customers)
maps upstream `sub` to **N/A**, not an outgoing immutable MSA object-id claim.
There is no verified supported outgoing upstream MSA tenant + `oid` projection
in this repository. A new registration and `User.Read` consent alone cannot fix
this. `IdentityService.microsoftPhotoIdentity` deliberately returns null, even
when `MICROSOFT_PHOTO_CLIENT_ID` is provided. No browser or Graph call is made
without proof. Do not replace this gate with CIAM `oid`, email equality,
cross-client subject equality, or a user-editable custom attribute.

Before enabling the adapter, the owner needs a separately reviewed identity
design that obtains the upstream MSA's immutable `tid` and `oid` from a validated
provider token, binds them to the existing CIAM issuer/subject on the trusted
server side, and emits that binding in a validated, non-user-editable CIAM
token or an equivalently authenticated server response. The adapter must return
the signed-in Bloomstep account hash and the bound MSA tenant/object identifiers
only for the actual Microsoft provider. Claim names and portal mapping steps
cannot honestly be prescribed until a supported mechanism has been verified;
this draft does not invent them or change provider configuration.

For personal accounts the expected tenant is
`9188040d-6c67-4c5b-b112-36a304b66dad`. The direct public-client ID token is
signature/issuer/audience/expiry/nonce validated, and its `tid` and `oid` must
match the trusted binding before its access token or photo is read. A mismatch
disposes the direct connection and leaves initials.

## Exact owner registration/build steps (necessary, not sufficient)

No registration, tenant setting, Azure configuration, terms acceptance, release,
or merge was performed.

1. In a normal Microsoft identity-platform tenant, create a **separate**
   registration named `Bloomstep Microsoft profile photos`. Do not reuse or
   modify the CIAM desktop registration or confidential MSA federation
   registration. Choose **Personal Microsoft accounts only**
   (`signInAudience: PersonalMicrosoftAccount`). Workforce accounts are out of
   scope for this connection.
2. Configure it as **Mobile and desktop applications / public client** with
   redirect URI **`http://127.0.0.1:43822/photo-callback`**. Enable public-client
   flows (`isFallbackPublicClient: true`), not implicit ID/access-token grants.
   Create **no client secret or certificate**. If the portal rejects the HTTP
   IP-literal textbox, use its manifest editor: in the Microsoft Graph manifest
   set `publicClient.redirectUris` to this exact URI (legacy Azure AD manifest:
   `replyUrlsWithType`, `type: InstalledClient`). Preserve unrelated entries.
   See [loopback redirect restrictions](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url#prefer-127001-over-localhost).
3. Under API permissions, use **Microsoft Graph > Delegated > User.Read** only.
   No application permission, directory-wide permission, custom Garden API
   permission, or admin-consent grant is needed for this personal-account
   design. The protocol also requests `openid` to validate the direct identity;
   it does not request `profile`, `email`, or `offline_access`.
4. Copy the new registration's **Application (client) ID** into the Flutter
   build define `--dart-define=MICROSOFT_PHOTO_CLIENT_ID=<new-public-client-id>`.
   This is a public identifier, not a secret. Keep the existing `OIDC_ISSUER`,
   `OIDC_CLIENT_ID`, `OIDC_API_SCOPE`, and `API_ORIGIN` unchanged. The photo
   authority is the consumers tenant's v2 issuer at
   `https://login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/v2.0`.
   Until the linkage adapter is reviewed and implemented, this define does not
   activate photos; leave it unset in release packaging.
5. After that separate linkage prerequisite is resolved, test with a genuine
   personal account: first consent, previously granted consent, decline/cancel,
   a different browser account, no photo, timeout, sign-out during callback/token
   refresh/download, and a restarted app. Verify only the bound account's photo
   appears. Do not capture tokens, codes, provider identifiers, or real photos
   in logs/screenshots/evidence.

Consent is left to Microsoft: the flow does not force `prompt=consent`, so an
existing grant need not be consented again. It attempts at most once per signed-in
account per app launch; declining/failing does not loop. A subsequent launch may
open the browser again because nothing about the photo connection is persisted.
Revoking the Microsoft grant is owner-controlled; Bloomstep sign-out clears the
local connection but does not sign out the system browser or revoke consent.

## Transport and privacy contract

The separate authorization-code + PKCE flow reuses `openid_client` and the system
browser. The callback binds IPv4 loopback only, validates path/state/single values,
accepts code or denial (not access tokens), returns only static text, and sets
no-store/no-referrer/no-content response headers. It never logs callback data.
The dependency's `openid_client` logger is explicitly disabled because its
FINE logging otherwise includes token response bodies, even when a diagnostic
listener enables root logging. `logging` is an existing transitive package now
declared directly for this privacy guard.
OIDC metadata/JWKS/exchange transport accepts only HTTPS
`login.microsoftonline.com:443`, does not follow redirects, limits responses to
1 MiB and 30 seconds, and closes on cancellation. Callback wait is three minutes.

The Graph request goes only to
`https://graph.microsoft.com/v1.0/me/photo/$value`, using only the separate
connection's token. It never sends the CIAM Garden API token to Graph. Redirects,
non-200 responses, missing/empty photos, non-JPEG/PNG content, responses above
1 MiB (including streamed bodies), and a 15-second total download deadline fall
back to initials. Requests are abortable on sign-out/deadline; generation checks
discard late authentication, token refresh, and download results.

Photos, credentials and linkage metadata are memory-only. No file, secure
storage, garden record, analytics event, or network image URL cache is added.
The avatar requests a 112px decoded image and evicts its Flutter image-cache
entry when changed or removed. Sign-out clears the connection before attempting
existing secure-storage deletion, even if that deletion fails.

## Evidence boundary

The [Graph photo API documentation](https://learn.microsoft.com/en-us/graph/api/profilephoto-get?view=graph-rest-1.0)
lists delegated **User.Read** for personal-account user photos and
`GET /me/photo/$value`. That is documented platform support, **not live MSA
evidence**.

Synthetic tests exercise absent proof/no browser/no Graph, mismatch rejection,
account-scoped memory bytes, denial, bounded content, redirect refusal, malformed
callbacks, sign-out during authentication/token refresh/download, and cache
eviction. `microsoft_photo_avatar_test.dart` writes
`microsoft-photo-SYNTHETIC.png` to `BLOOMSTEP_SCREENSHOTS` when set; the drawing is
synthetic, not a Microsoft user's photo. Existing profile/startup tests remain
app-path regressions, not installed-executable acceptance.

**Not observed:** live MSA sign-in, live User.Read consent or reuse, actual
MSA ID-token claims/Graph photo response, a supported CIAM upstream immutable
identity projection, or installed desktop acceptance. Photo support is blocked
until that projection and a real owner-controlled end-to-end trial exist.

## Bounded design decision (2026-10-10)

**Decision:** there is no evidenced configuration-only fix for the existing
CIAM-to-separate-public-client gap. The smallest plausible existing-account
solution is a **server-side same-federation-client proof bridge**, not an
arbitrary account-link button or a custom claim populated from user input.
It preserves the primary CIAM login and garden keys but adds an authentication
component, backend directory-read privilege, a confidential-server credential,
and an extra browser authentication round trip. These are new approval scope,
not covered by the owner's approval of delegated photo `User.Read`.

The components below are documented platform capabilities. Their composition
is a proposed design, **not implemented or live-verified**. In particular, the
actual deployed CIAM federated identity representation must be verified before
calling the bridge viable. If that equality gate cannot be demonstrated, do not
deploy it.

### Evidence and options

| Option | Decision and reason |
| --- | --- |
| Project an upstream MSA object ID through standard OIDC mapping | Not evidenced by the supported mapping table; current mapping uses upstream `sub`. No invented extension claim is acceptable. |
| Add an OnTokenIssuanceStart custom claims provider | Supported enrichment mechanism, but not an identity-proof source. Its documented request contains the CIAM user ID/profile, not a validated upstream MSA token or object ID. It cannot manufacture the missing binding. Adds a synchronous dependency to sign-in; not the minimum photo-only solution. |
| Read the CIAM user's directory `identities` | Supported server Graph surface containing issuer + issuerAssignedId. This supplies the federation-side identity, not automatically the separate public-client MSA object ID. Must verify the actual representation, provider mapping and provenance. |
| Reauthenticate on the server with the **existing federation application ID** | Candidate bridge: compare a validated token's same-client upstream `sub` to the authenticated CIAM user's authoritative federated identity; derive MSA tenant + object ID from that same validated token. This does not compare different clients' `sub` values. |
| Change federation Subject mapping to `oid`, replace provider, or make direct MSA primary login | Authentication architecture/migration project, not this follow-up. Existing subject-based directory links and issuer/sub garden keys can change; account duplication/orphaned gardens require explicit migration. Do not toggle the mapping on the live provider. |

Sources:
[MSA federation settings](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-microsoft-accounts-federation-customers)
document the confidential web registration and `openid profile email`;
[OIDC claims mapping](https://learn.microsoft.com/en-us/entra/external-id/customers/reference-oidc-claims-mapping-customers)
documents the Subject mapping;
[Graph objectIdentity](https://learn.microsoft.com/en-us/graph/api/resources/objectidentity?view=graph-rest-1.0)
documents the authoritative identity tuple;
[Graph get user](https://learn.microsoft.com/en-us/graph/api/user-get?view=graph-rest-1.0)
supports customer users, `$select`, and application `User.Read.All`;
[ID-token claims](https://learn.microsoft.com/en-us/entra/identity-platform/id-token-claims-reference)
documents same-client pairwise `sub`, cross-application `oid` within a tenant,
and the consumer tenant ID;
[custom claims provider request](https://learn.microsoft.com/en-us/entra/identity-platform/custom-claims-provider-reference)
documents the callout data rather than an upstream-token forwarding channel.

### Minimum proof-bridge contract, if approved

1. The desktop starts a short-lived photo-binding operation with its existing
   **Garden API access token to the Garden API only**. The API validates the
   existing CIAM issuer/audience/signature/expiry/scope and authorized client.
   It must additionally retain a validated CIAM `oid` and tenant context for
   directory lookup. Current `createPrimaryAuthenticator` returns only the
   issuer/sub account hash, roles and scopes; it does not expose that object ID.
   Never accept a client-posted directory user ID or account hash as authority.
   Do not auto-start this on Google/local sign-in: a documented, verified
   trusted current-provider signal must gate an automatic attempt. A directory
   identity list alone does not establish which provider authenticated this
   session. If that signal is unavailable, automatic startup stays disabled;
   any explicit Microsoft-connection UX is a separate owner-reviewed behavior.
2. The server reads only
   `GET https://graph.microsoft.com/v1.0/users/{validated-ciam-oid}?$select=id,identities`
   with its **separate CIAM-tenant app-only Graph credential**. It pins the
   configured customer tenant and exact Microsoft provider identity, verifies
   `id` equals the token's object ID, and rejects missing/ambiguous identities
   or unexpected provider mapping. This credential has no role in reading
   personal-account photos. The Garden API token is never sent to Graph.
3. The server creates random one-use state/nonce/PKCE and binds them to the
   authenticated garden account, directory identity and initiating operation.
   The browser URL contains only an opaque short-lived operation/state handle,
   never the CIAM token, upstream identifiers, photo or a user-chosen callback.
   The server initiates authorization code flow against the consumers authority
   **using the existing confidential MSA federation application's client ID**,
   requesting `openid profile` (no Graph permission). A new unrelated bridge
   client cannot match the old pairwise subject.
4. At its fixed HTTPS callback the server exchanges the code using a
   server-only credential for that same federation application. It validates
   signature, exact consumer issuer, audience, expiry, nonce and the operation.
   The token's nonempty `sub` must exactly match the directory identity's
   issuerAssignedId **under the verified existing Subject=sub mapping**;
   any composite/transformed representation without a documented verified
   comparison rule fails closed. Provider alias `https://login.live.com` is
   not the JWT issuer. Require consumer `tid` and valid `oid` in this same
   validated token; neither email nor two successful logins is sufficient.
5. The server returns the resulting consumer tenant/object-ID binding only
   through an authenticated HTTPS operation-result read by the initiating
   Bloomstep account. It does not issue it to another account or put it in a
   browser redirect. State/results are one-use and expire within minutes;
   keep tokens and binding data in scoped ephemeral server memory, with an
   instance-affinity or reviewed shared ephemeral-state strategy. Do not add a
   durable identity/photo cache by default. Restart/scale-out losing state must
   fail closed. Rate-limit starts and do not log tokens/codes/identifiers.
6. Only then run the **separate public-client User.Read** photo flow. Its
   authenticated consumer identity must match that server-proved object ID.
   The bridge must not receive the public client's Graph access token. Fetch
   `/me/photo/$value` only after equality; all failures retain initials.
   Sign-out/cancellation invalidates the initiating operation and all local
   photo state; late results are discarded.

**Additional finding:** Microsoft's ID-token reference says `oid` requires the
OIDC `profile` scope. The foundation currently requests only `openid` +
`User.Read` and rejects an absent `oid`; it cannot assume `oid` will be returned.
Before operationalizing it, choose either OIDC `profile` as well (still only
one **Graph delegated** permission, `User.Read`) or resolve the direct user's
`id` through bounded, redirect-free `GET /me?$select=id` using its own Graph
`User.Read` token. The latter adds an endpoint/identity-source change and tests.
Neither option by itself proves the CIAM linkage.

### Exact owner prerequisites for a proof-only pilot

These are a proposed operator checklist, **not an instruction to mutate now**.
Do not change the live primary flow just to obtain evidence.

1. Using a dedicated test identity and an owner-controlled diagnostic harness,
   privately verify the configured MSA provider's client ID, issuer alias and
   Subject=`sub` mapping; verify the authenticated CIAM token includes a usable
   customer-tenant `oid` and verify how (or whether) the actual current provider
   is authoritatively distinguished. Read that exact test user's Graph
   `id,identities`.
   Verify the identity corresponds to the upstream **same-client** validated
   MSA subject. Report only equality/absence outcomes, not token or identifier
   values. No real customer photo/token exports or credential screenshots.
2. Approve backend **application Microsoft Graph `User.Read.All` in the CIAM
   tenant with admin consent**, for read-only directory identity lookup. Keep
   it separate from the photo public registration and from API scopes. Do not
   grant `Directory.ReadWrite.All` or `User.ManageIdentities.All`; the bridge
   never creates/updates directory links. Review the privacy/breach scope of
   tenant-wide profile read before approving.
3. Approve server access to a credential for the **existing MSA federation
   application**, with rotation/secret-store policy. A new credential for that
   same application is preferable to extracting the provider's current secret;
   it still requires owner approval. No confidential material goes into Dart,
   git, public-client configuration or logs.
4. Add only a **Web** redirect on that existing federation registration:
   `<API_ORIGIN>/api/microsoft-photo-binding/callback`, after implementation
   establishes that exact fixed HTTPS endpoint. `API_ORIGIN` is the existing
   pinned SWA HTTPS origin. Preserve every existing CIAM federation callback,
   audience and Subject mapping. This is **not** the separate photo client's
   loopback redirect and must not be added as an InstalledClient URI.
5. Approve the backend start/result/callback routes, bounded ephemeral state,
   authenticated CIAM-object-ID extraction, and mismatch/replay/expiry/sign-out
   coverage as a new narrowly scoped workstream. No custom claims extension or
   primary-login replacement is necessary for this candidate. The public
   client's settings remain those above, with the direct `oid` scope/source
   correction explicitly reviewed.

**Go/no-go:** if the owner permits the additional server privilege/credential
and the same-client directory-subject equality is demonstrated, implement a
photo-only bridge as a separate reviewed change, preserving V1 login/gardens.
If either is refused or cannot be established, the original no-secret desktop
photo connection cannot securely identify the current CIAM-federated account
with available evidence. A broader primary-auth/provider redesign would then
be required and is outside the approved scope. V1 and PR #31 remain nonblocking;
there is no live proof or current configuration-only solution to claim.
