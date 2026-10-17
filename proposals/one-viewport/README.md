# PROPOSAL — Bloomstep in one viewport

**Not for merge or deployment. Owner approval is required before any production UI implementation.** This branch changes only `proposals/one-viewport/`. It does not change the live site, assets/configuration under `site/`, API behavior, preview.14 pointers, or the preview15 branch / [#48](https://github.com/Sampath-K/bloomstep/pull/48).

Open [`index.html`](index.html) directly in a browser, or serve this directory locally. It is a self-contained, no-build, no-analytics concept; it makes no requests until a reviewer follows an external source/release link. Use the clearly labeled proposal selector to compare copy, or append `?variant=b&scoutTheme=light` (variants `a`, `b`, `c`; themes `light`, `dark`). This selector is **not visitor randomization**.

## The proposed decision

One screen answers **what it is, how it works, why it feels different, who can use this preview, and where to download**. A Windows habit app; routine → tiny action → celebration; a growing garden without broken-streak pressure. One original illustrative recipe makes the mechanism visible rather than asking people to read a feature catalog. There are no testimonials, star ratings, user counts, endorsement badges or efficacy promises.

The download-intent CTA stays above the fold, but deliberately opens an accessible preview-boundary dialog rather than silently starting an installer. It points designated testers to the **existing preview.14 release/help page**, not preview15. The unsigned, unverified, owner-only status stays next to the CTA even in a screenshot; the dialog is not a way to hide it. General-customer download activation remains blocked by existing release-readiness requirements, independently of visual approval.

Below the first screen, optional learning explains B=MAP, the Anchor–Behavior–Celebration recipe, ability/simplicity, and context/repetition research. Claims link to primary sources. This is research-informed editorial framing, **not a scientifically proven app**. The interface rendering is labeled a concept; it is not a screenshot of a shipped redesigned app. Warm neutral surfaces, the existing Clawpilot rose accent and restrained typography keep it aligned with the current site rather than introducing a new brand.

## Copy concepts

| Concept | Headline | CTA |
| --- | --- | --- |
| **A — recommended baseline** | Build a habit small enough to start today. | Download Windows preview |
| B — identity-led | A tiny habit. A little more you. | Get the Windows preview |
| C — low-pressure | Make room for one small habit. | Try the Windows preview |

All share the explanatory subhead: “Pair an everyday routine with one tiny action. Celebrate doing it. Bloomstep helps you keep track, with a garden that grows along the way.”

These are creative alternatives, not three proposed concurrent arms. The current experiment catalog cannot vary hero headlines and does not contain these CTA labels. The [factual experimentation report](experimentation.md) explains the integration boundary and why 100 visitors/week calls for comprehension work, not an A/B/C winner.

## Review material

- [Eight-page benchmark and sources](benchmark.md)
- [Experimentation implementation, production evidence and 7-day/100-visitor example](experimentation.md)
- [1920×1080, concept A](screenshots/light-a-1920x1080.png)
- [1366×768, concept A](screenshots/light-a-1366x768.png)
- [1366×768, concept B](screenshots/light-b-1366x768.png) · [concept C](screenshots/light-c-1366x768.png)
- [Dark 1366×768](screenshots/dark-a-1366x768.png) · [mobile reflow](screenshots/light-a-mobile-390.png)
- [Machine-readable geometry/accessibility evidence](verification.json)

Screenshots are **CSS viewport sizes at device scale 1**, not guarantees about arbitrary browser toolbars, custom fonts, display scaling or zoom. Mobile and zoomed/short windows intentionally reflow and scroll rather than hiding content. Desktop screenshots include the proposal controls, so their removal is not needed to meet the stated targets.

## Reproduce the checks

Using the repository's existing browser tooling (no new dependency or manifest):

```sh
npm ci --prefix site --no-audit --no-fund
node proposals/one-viewport/verify.mjs
```

`CHROME_PATH` can point to an installed Chrome/Chromium executable; the default is `/usr/bin/google-chrome`. The verifier serves only the proposal on a temporary loopback port, then shuts down. It captures the screenshots and checks all three copy concepts in both themes at both desktop sizes; title, CTA, safety note, illustration and learn link must fit above the fold. It also checks rendered text contrast including the dialog, keyboard entry/focus containment/Escape/focus return, meaningful SVG alternatives, reduced-motion behavior, no external requests, no horizontal overflow at 320/390/683px and a no-JavaScript fallback. This is targeted automated/manual visual evidence, not a claim of a complete assistive-technology audit.

The provided dark muted/border tokens are strengthened using existing theme variables because small-text/control contrast is a blocker. There are no animations, autoplay, external fonts, hidden overflow tricks or consent-gated links. Approval should include owner review of the concepts and a final production accessibility review before implementation; there is no deployment approval implied by passing proposal checks.

The existing Lighthouse accessibility runner also scored this static proposal **100/100 in both themes**, with no failed automated accessibility audits. That is supporting evidence, not a substitute for screen-reader/manual acceptance.
