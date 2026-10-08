# Profile and first-habit contract

## Profile surface

When signed in, the normal profile surface exposes only the identity's display
name and the state `Signed in`, plus the existing `Sign out` action. Email,
provider, issuer, account identifiers and URLs are not rendered. Use the
provider's standard OIDC `picture` claim when it is an HTTPS URL; do not request
additional scopes, persist the URL, or copy additional identity data into the
garden. If the claim is absent, malformed, or its image cannot load, show a
polished initials avatar and keep the name/state/sign-out surface intact.

## First-habit sequence

After startup has completed identity restoration and loaded the selected garden,
a genuinely new, empty device garden automatically opens the `Plant a new
habit` flow without a click. The flow must not open while restoration or garden
loading is pending, above another route, for an account garden, or for a garden
with existing activity/habits. Cancel/dismiss is a durable one-time choice: do
not reopen the flow on later launches, but keep the empty-garden `Plant a habit`
CTA available.

## Edge and error matrix

| Condition | Profile behavior | First-habit behavior |
| --- | --- | --- |
| Signed in with a display name and valid HTTPS OIDC picture claim | Show name, `Signed in`, photo, and `Sign out`; no technical identity fields | Not applicable |
| Signed in, picture claim absent/invalid, or image request fails | Show initials fallback; do not imply a photo loaded; retain name/state/sign-out | Not applicable |
| Signed in without a display-name claim | Do not invent an identity; retain signed-in state and sign-out | Not applicable |
| Signed out, sign-in pending, or sign-in fails | Preserve the existing sign-in/error states and provider choices | Not applicable |
| New empty guest while auth restore/store load is pending | Not applicable | Wait; do not open early |
| New empty guest after successful load and first-invitation claim | Not applicable | Automatically open the builder once |
| User cancels/dismisses the builder | Not applicable | Persist dismissal; keep the empty-state CTA |
| Returning empty guest or previously dismissed invitation | Not applicable | Do not auto-open; CTA remains usable |
| Existing guest visit or habit | Not applicable | Never auto-open |
| Empty account garden | Not applicable | Never auto-open |
| Garden read or durable invitation-claim error | Preserve visible error handling; do not present success-shaped invitation | Do not open until eligibility can be established |
| Another route owns the navigator when invitation becomes ready | Not applicable | Defer/skip rather than interrupt the route |
