# Profile and first-habit contract

## Profile surface

When signed in, the normal profile surface exposes only the avatar
and the existing `Sign out` action. The name is used only for avatar initials
and its accessible label; neither the name nor `Signed in` is displayed. Email,
provider, issuer, account identifiers and URLs are not rendered. Use the
provider's standard OIDC `picture` claim when it is an HTTPS URL; do not request
additional scopes, persist the URL, or copy additional identity data into the
garden. If the claim is absent, malformed, or its image cannot load, show a
polished initials avatar and keep the sign-out action intact.

Personal Microsoft accounts federated through the customer tenant do not provide
a usable Graph photo token to this app. A direct Microsoft public-client photo
connection with delegated `User.Read` and additional consent is a separate
follow-up; this PR does not request that scope or claim live MSA photo evidence.
The initials avatar is only a fallback, not a live photo. This change does not
claim MSA photo support; the Google HTTPS `picture` claim path is unchanged.

## First-habit sequence

After startup has completed identity restoration and loaded the selected garden,
an empty device or account garden automatically opens the `Plant a new
habit` flow without a click. Opening an empty account garden after sign-in does
the same. Invite once per garden per app launch; cancellation must not loop.
Previous visits, the legacy first-run dismissal flag, and reinstall-preserved
settings must not prevent a new launch's invitation. The flow must not open while
restoration or garden loading is pending, above another route, or when habits
are planted. Keep the empty-garden `Plant a habit` CTA available.

## Edge and error matrix

| Condition | Profile behavior | First-habit behavior |
| --- | --- | --- |
| Signed in with a display name and valid HTTPS OIDC picture claim | Show photo and `Sign out`; no identity text | Invite if empty |
| Signed in, picture claim absent/invalid, or image request fails | Show initials fallback; do not imply a photo loaded; retain sign-out | Invite if empty |
| Signed in without a display-name claim | Show a generic avatar, not an invented identity; retain sign-out | Invite if empty |
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
