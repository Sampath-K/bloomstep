# Public website launch checklist

Status: public-site UX and isolated collector evidence are implemented; **a full public launch is not approved or
verified**. This checklist does not supersede the installer, privacy, identity or deployment gates.

Owner decision: launch a useful, trustworthy **ad-free** app first; monetization is deferred until customer
evidence. No ads, supporter checkout or paid-tier expansion is part of this launch.

## Audience and conversion path

Initial audience: adults using Windows who want a small routine alongside their working day, without streak
pressure. The page explains a concrete routine/action example, shows a labeled synthetic app screenshot, and
uses one primary action: go to the Windows download. It discloses 64-bit Windows, required sign-in, ages 16+,
the unsigned limited-preview status and no payment step beside the download.

Both hero and closing download-intent links enter the existing `primary_cta_click` website event; identical
intent observations are deduplicated within the consented page epoch. The closing link is **not** a new
experiment exposure or an experiment-secondary outcome. The download links use `download_click`.
No schema, account identity join or successful-download claim was added.

Optional consent is now discoverable from the hero and beside downloads, remains unchecked, and explains
subsequent-only collection. No earlier click is replayed on opt-in. DNT/GPC, memory-only choice, withdrawal,
no-JavaScript download access and service-outage independence are preserved. Privacy details remain linked.

## Initial demand hypothesis (owner action, not publication)

Use **one unpaid LinkedIn post** from the owner's existing profile, targeted in its wording to adults who use a
Windows PC. Explain one concrete tiny routine and the honest limited-preview boundaries; link to the current
canonical site using:

```text
?utm_source=linkedin&utm_medium=social&utm_campaign=tiny_habits
```

Append these allowlisted labels to the `origin` in `site/customer-config.json`; do not invent a campaign
containing names, email addresses or arbitrary audience details. No post was published, message sent, ad bought
or new account created. Confirm launch gates before creating demand for the downloadable app.

Hypothesis: a concrete Windows routine example will attract people who want to try one habit and make the
download path understandable. Review a fixed 14-day window after owner publication. The website report can
show opted-in page/button event counts and separate first/last page-touch margins for LinkedIn/social/tiny_habits;
publication floors below 50 remain suppressed. Campaign dimensions are marginal counts, not joined people,
qualified leads, installs or attributed app activations.

Treat stage ratios as descriptive event ratios, not visitor conversion probabilities or a causal test.
Account recipe -> first positive check-in and exact-day retention remain separate opt-in AARRR evidence.
The foundation's additive `linked.activation` report separately supports explicitly imported website receipt
download -> saved recipe -> first positive same-habit completion, with 50-account suppression and unknown
install/launch timing. It is not a campaign-level join or an anonymous visitor denominator; neither report can
be attributed to that post without a supported consented campaign link. Use voluntarily submitted in-app
feedback to identify specific obstacles, never infer rejection from missing telemetry. If evidence is sparse,
record insufficient data; do not promote variants, run experiments or broaden collection.

## Contact and qualified leads

A download click is intent, **not a qualified lead**. There is no lead count or website contact form. For an
initial free self-service preview, a mailing list is not essential to the product funnel. In-app private feedback
is now explicitly discoverable in the FAQ, but it requires successful sign-in and has no response-time guarantee.

An owner-approved public support/privacy contact is essential before full launch, including for people unable
to sign in. The existing privacy notice still lacks controller identity/contact, applicable basis and
processor/backup retention facts. Do not invent these or create an email/CRM signup. If the owner wants lead
capture later, first agree purpose, qualification, fields, consent, access, storage, retention/deletion,
response ownership and abuse protection. Existing aggregate telemetry cannot substitute for that agreement.

## Gates and owner decisions

| Gate | Current evidence / remaining action |
| --- | --- |
| Value proposition / audience | Concrete Windows routine, labeled app illustration; no clinical or efficacy claim. Owner approves initial audience/channel. |
| Responsive / keyboard / static download | Isolated real-browser 1280/390/320 reflow, skip link, keyboard FAQ, no-JS links; customer-site CI checks Lighthouse, both entry pages and warning/help surfaces. |
| Acquisition / intent | Real browser -> HTTP -> disk confirms allowlisted campaign, footer/hero dedup, consent-off zero writes, withdrawal and small-cell suppression. Synthetic proof only. |
| Privacy | Default-off preserved. **Blocked:** supply controller identity, support/privacy contact, applicable basis and verified processor/backup retention. |
| Production collection / console | Local synthetic preview is usable. **Unverified:** approved live deployment, Functions/OIDC/Admin roles, deployed collector/readback, retention/erasure operations and hosting logs/billing facts. No new paid resources provisioned. |
| Download / install / first launch | Existing preview.12 pointer unchanged. **Blocked:** independent real install/launch acceptance and unresolved launch CI. PR26 candidate was Defender-quarantined (`Behavior:Win32/DefenseEvasion.A!ml`) and withdrawn; do not download/run it or bypass protections. |
| App activation / retention | Existing separate account reports, not website or campaign conversion. Revenue and referral-delivery/attributed activation remain unsupported. |
| Experiments | Public OFF; no sufficient customer evidence or deployment authorization. Existing isolated loop proof is not live efficacy. |
| Public demand / deployment | Owner approves support/legal details, site/domain and verified downloadable asset, then explicitly approves publication/deployment. No merge, deploy, release or outreach was performed. |

## Reproduce the public UX/collector evidence

With existing API/site dependencies installed and trusted Edge installed (or `CHROME_PATH` configured):

```powershell
npm --prefix site run build
$env:EVIDENCE_DIR = Join-Path $env:TEMP 'bloomstep-public-launch-evidence'
node site\verify-launch.mjs
```

The source-bound `launch-receipt.json` and desktop/mobile/no-JS screenshots label the run synthetic. Real
download navigation is prevented; no installer is downloaded or executed. Production download pointers,
experiment configuration and account/website denominator contracts are unchanged.
