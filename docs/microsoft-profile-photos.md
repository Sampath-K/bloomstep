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
