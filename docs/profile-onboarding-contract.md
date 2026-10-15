# Profile and first-habit contract

## Profile surface

The owner's 15 October preview.14 feedback supersedes the avatar-only presentation.
When signed in, the compact profile shows the authoritative display name,
avatar and existing `Sign out` action. Standard `name`, or nonempty
`given_name`/`family_name`, claims supply the name. If missing, show
`Signed-in account` and `Your sign-in provider did not supply a name.`
Never invent identity or substitute email, subject identifiers or a U-only badge. Email,
provider, issuer, account identifiers and URLs are not rendered. Use the
provider's standard OIDC `picture` claim when it is an HTTPS URL; do not request
additional scopes, persist the URL, or copy additional identity data into the
garden. If the claim is absent, malformed, or its image cannot load, show a
polished initials avatar and keep the sign-out action intact.

## Garden continuity and explicit copy

The preview.14 source intentionally opens different account/device SQLite files;
isolated fixtures prove the guest recipes survive signing in and signing out.
The owner's installed database has not been inspected and its actual state is
unconfirmed. The previous transient notice was also omitted from the signed-in
profile, making preservation easy to miss.

Keep a persistent selected-garden explanation with saved device-habit count,
`View device garden`, and a non-destructive `Return to account garden` action.
Viewing the device garden preserves the account session but never enables device
sync/analytics. Session expiry removes account access from either surface.

`Copy device habits to this account` opens a confirmation describing all recipes,
check-ins/reflections, possible cloud sync, unchanged local originals and no
automatic ongoing linking. `Keep separate`/dismissal writes nothing. Confirming
copies only those three tables in one destination transaction, using stable
destination-account/source-record UUIDs; existing copies/account edits and
deleted-copy tombstones are skipped. Retries/concurrent retries do not duplicate
or overwrite, and no account-to-account input is accepted. Account generation,
selected store and valid identity must still match before commit, otherwise
rollback everything and show an actionable error. Settings, telemetry, feedback,
consent and reminder enablement are excluded. Normal account sync handles only
the committed copies. Success reports the number actually added and warns sync
can still be pending; it never claims upload/delivery. Deleted local/account
storage deliberately clears its local history as before; a later user-confirmed
copy is not a restoration guarantee.

When an empty account has device habits awaiting this choice, do not auto-open
the first-habit builder over the continuity message; the manual CTA stays
available. Otherwise the existing once-per-garden-per-launch invitation remains.
Errors/progress/success reuse the existing live-region profile and garden status
surfaces, not an OS notification or new messaging service.

Account gardens retain the existing app-bar **Settings and privacy** action,
independently of the minimal profile card. Export, local/account deletion and
consent controls must remain reachable after restoration and sign-in. Device
gardens keep the existing inline Settings action without adding a duplicate.

Personal Microsoft accounts federated through the customer tenant do not provide
a usable Graph photo token to this app. A direct Microsoft public-client photo
connection with delegated `User.Read` and additional consent is a separate
follow-up; this PR does not request that scope or claim live MSA photo evidence.
The Google HTTPS `picture` claim path is unchanged.

## First-habit sequence

After startup has completed identity restoration and loaded the selected garden,
an empty device or account garden automatically opens the `Plant a new
habit` flow without a click. Opening an empty account garden after sign-in does
the same unless saved device habits need the explicit copy/keep-separate choice.
Invite once per garden per app launch; cancellation must not loop.
Previous visits, the legacy first-run dismissal flag, and reinstall-preserved
settings must not prevent a new launch's invitation. The flow must not open while
restoration or garden loading is pending, above another route, or when habits
are planted. Keep the empty-garden `Plant a habit` CTA available.

## Edge and error matrix

| Condition | Profile behavior | First-habit behavior |
| --- | --- | --- |
| Signed in with a display name and valid HTTPS OIDC picture claim | Show name, photo and `Sign out` | Invite if empty and no device-copy choice |
| Signed in, picture claim absent/invalid, or image request fails | Show initials fallback; do not imply a photo loaded; retain sign-out | Invite if empty |
| Signed in without a display-name claim | Generic avatar, useful signed-in label and missing-provider-name explanation; retain sign-out | Invite if empty and no device-copy choice |
| Signed out, sign-in pending, or sign-in fails | Preserve the existing sign-in/error states and provider choices | Not applicable |
| New empty guest while auth restore/store load is pending | Not applicable | Wait; do not open early |
| New empty guest after successful load and first-invitation claim | Not applicable | Automatically open the builder once |
| User cancels/dismisses the builder | Not applicable | Do not repeat for this garden this launch; keep the empty-state CTA |
| Returning empty guest or previously dismissed invitation | Not applicable | Auto-open once on the new launch |
| Previous visit without habits | Not applicable | Auto-open once on the new launch |
| Planted habits | Not applicable | Never auto-open |
| Empty account garden at restoration or after sign-in | Not applicable | Auto-open once for that garden this launch |
| Garden read error | Preserve visible error handling; do not present success-shaped invitation | Do not open until eligibility can be established |
| Another route owns the navigator when invitation becomes ready | Not applicable | Defer/skip rather than interrupt the route |

## Evidence boundary

The old implementation excluded account gardens and used a durable first-run
claim for device gardens. Both prevent the owner's requested every-launch
empty-garden invitation. Regression tests reproduce those gates through the
production `HabitHome` restore/sign-in path using isolated SQLite gardens with
previous activity/dismissal settings, and capture the restored empty account's
automatically opened builder. The owner's installed executable and live MSA
session were not reproduced or accessed; these are synthetic app-path tests,
not live provider or installed-launch acceptance.
