# Deferred PR copy and visual proposals

**Awaiting owner approval. Not included in preview.15.**

On 17 October the coordinator confirmed that the exact approved `8a0772c`
gallery does not cover the additional surfaces in PRs #27, #29, #30, or #38.
The instruction to merge open PRs does not override the later mockup-before-code
rule. Keep these PRs open and unmerged; they do not block the approved preview.15
scope. No production UI, animation, updater setting, or consent changes are
implemented by this packet.

Review gallery:
`docs/evidence/visual-quality/proposals/deferred-pr-gallery.html`.
These are conceptual HTML proposals, not Flutter or installed-app screenshots.
The gallery uses the Calm starter recipe so the practice action has its actual
context. The review shell is not a proposed replacement for Budlark's garden
art or Windows theme. Existing garden art remains unchanged.

| PR and exact source | Existing surface or copy | Proposed disposition and copy |
| --- | --- | --- |
| #27 `3ec07ccc50aaed741cec642f521d30b53f80464f` | Permanent bottom status row; startup/daily release discovery enabled by default. Dialog explains unsigned Inno, MSIX, background checks, and policy limitations in one long paragraph. Errors interpolate raw exceptions. | Do not add a permanent status row: retain practice space and put update status in Settings. Title **Updates**; existing manual-install behavior remains explicit: **You choose when to install an update.** Action **Check for updates**; available-release action **Open release page**. Failure: **Couldn't check for updates. Try again.** Preference failure: **Couldn't save your update choice. Try again.** Propose leaving automatic discovery off for this trial; changing its default requires explicit owner approval. No automatic execution, signed feed, trust enrollment, MSIX publication, or credential/permission change is authorized. |
| #29 `e88bfaa639fcf9d20232e3065b9252759e32bc93` | Weekly recap adds local date ranges, aggregate practice days, stages and an optional recommendation. Disclosure uses “deterministic” and “local week’s saved reasons”; errors interpolate exceptions. | Title **Your garden this week**. Keep accurate local dates and per-habit counts, not streaks or outcome claims. Example: **Calm: 3 practice days.** Heading **An optional next step**. Disclosure **This suggestion uses your saved reasons. Your recipe changes only if you edit it.** Separate privacy detail: **Opening this summary doesn't start a sync. Your existing sync settings still apply.** Actions **Edit recipe** / **Close**. Error **Couldn't open your weekly summary. Try again.** Counts are synthetic examples, not owner data. |
| #30 `c9b119c0e324f74c2f8e2f3e7b53845112700e08` | After **Not today**, adds **One optional idea: [reason-based recommendation]** and **Adjust my recipe** inside the habit card. | Keep this below the full recipe and practice controls, only after a reason was saved. Heading **An optional next step**; action **Edit recipe**. Retain the existing reason-specific recommendation without claiming AI or diagnosis. Never let the card displace the primary practice control at 200%, short viewport, high DPI, or keyboard focus. |
| #38 `77d7e75d163fbfd95cf9f15fb296889773217c5e` | New badge reveal and coach cards; **A small surprise**, **Keep growing quietly**, **A gentle invitation**, **Later**. A 700 ms opacity animation is new motion outside the approved gallery. | Keep badge/coach additions unmerged until approved. Proposal: show optional secondary cards after practice, never modal or before the habit action. Badge example **First seed** / **You made room for one small beginning.** Dismiss action **Dismiss**. Coach heading **An optional next step**; contextual action **Review recipe** / **Not now**. Do not implement the 700 ms fade. Static is the proposal baseline; any later motion needs a separate exact rendered approval, reduced-motion support, and no delayed controls or announcements. |

## Release disposition

- #48: approved accessibility/copy implementation; merge only after hosted
  x64/ARM64 and other required engineering checks pass.
- #49: patches already composed in #48; close as superseded only after #48 lands.
- #50: private, local-only project-status tooling composed in `8d3fb21729215bec33aff43796acd491a1310510`;
  no customer configuration or app surface changes.
- #36: fail-closed photo foundation composed in `8dc00de88c0b8414065026f7c1cc46f2db35ea3a`.
  Production immutable linkage remains `null`; no browser/Graph photo path is
  enabled. Preserve the approved profile name and compact hierarchy.
- #28/#31/#33: closed as superseded, with exact main-commit evidence in their
  closure comments.
- #26: installer/profile behavior is composed in main through #46/#47; its
  historical branch also contains #38's unapproved coach patch. Do not merge
  that branch wholesale. Record a final superseding disposition without
  claiming that the held coach patch shipped.
- #27/#29/#30/#38: **held for owner review; excluded from preview.15**, not
  rejected or described as merged.

## Approval and validation boundaries

Approval must identify these exact proposed surfaces and strings before their
production implementation. A conceptual review render is not a native
accessibility pass. After approval, write regression tests first and render
the actual combined Flutter source at desktop, 420x820/200%, and 640x480/200%.
Assert full button-rectangle containment, recipe context, semantics, and
keyboard order. Native Narrator, high contrast, mixed DPI, protected install,
and genuine launch remain separately unverified until observed.
