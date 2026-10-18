# Release governance — explicit role sign-off gate

Budlark is released like a high-stakes app. No release stage proceeds unless every
required role has made an explicit, evidence-backed sign-off bound to the exact bits.

## What is bound

Each sign-off names the **candidate commit**, its **git source tree SHA**, the
**installer SHA-256** and the **CI run/artifact id** that produced those bytes.
Releases promote that exact reviewed artifact; tag runs never publish rebuilt bits,
because builds are not byte-reproducible.

## Roles

`release/roles.json` lists 12 roles. `owner-test` requires product, domain (Tiny Habits),
UX/content/accessibility, architect, engineering, QA/release and security/privacy.
`public-launch` additionally requires legal/compliance, growth/website, editorial/brand,
analytics and support.

## Workflow per candidate

1. Freeze a candidate commit after push CI is green; record its run id, artifact id and installer SHA-256.
2. Each role agent reviews independently (one agent per role, no shared drafts) and writes
   `release/reviews/<candidate>/<role>.md`: scope, method, what was inspected, findings.
3. Findings are fixed in code. Any fix creates a **new candidate**; reviews restart for affected roles
   and all sign-offs are re-recorded against the new SHA. Approvals never carry across commits.
4. Each role records `release/signoffs/<candidate>/<role>.json` (schema below).
5. Generate the evidence file:
   `node tool/verify_release_signoffs.mjs --stage owner-test --candidate <sha> --head HEAD --installer-sha256 <sha256> --write-evidence`
6. Commit only `release/reviews|signoffs|evidence/**` on top of the candidate. Any other change after the
   candidate fails the gate.
7. Tag release: CI resolves the candidate, downloads its artifacts from the recorded run, recomputes the
   installer SHA-256, runs the gate at `public-launch` with `--check-evidence`, then publishes.

The **owner reads `release/evidence/<candidate>/README.md`** before each release; it lists SHAs,
every role verdict, findings and fixes, CI run, and residual risks.

## Sign-off record (`budlark-release-signoff-v1`)

```json
{
  "schema": "budlark-release-signoff-v1",
  "role": "security-privacy",
  "verdict": "APPROVED | APPROVED_WITH_ACCEPTED_RISK | CHANGES_REQUIRED",
  "candidateCommit": "<40-hex>",
  "sourceTree": "<git rev-parse <candidate>^{tree}>",
  "installerSha256": "<64-hex>",
  "artifact": { "runId": "<push run id>", "artifactId": "<artifact id>" },
  "scope": "What was reviewed",
  "evidence": ["release/reviews/<candidate>/security-privacy.md", "CI run URL", "..."],
  "findings": [
    { "id": "SEC-1", "severity": "critical|high|medium|low", "description": "...",
      "resolution": "FIXED|ACCEPTED_RISK|OPEN", "fixedInCommit": "<40-hex>",
      "ownerAcceptance": { "by": "Sampath-K", "at": "<ISO UTC>", "reference": "PR comment URL" } }
  ],
  "reviewer": { "session": "<agent session id>", "model": "<model>" },
  "reviewedAt": "2026-10-20T06:00:00Z"
}
```

## Fail-closed rules

- Missing required role, unknown role file, malformed JSON, or role/file mismatch.
- Any `CHANGES_REQUIRED` verdict or `OPEN` finding.
- `FIXED` without a fix commit contained in the candidate.
- Accepted risk that is not low severity or lacks explicit owner acceptance.
- Candidate, tree, installer SHA-256 or artifact identity mismatch (including across roles).
- Any file outside `release/signoffs|evidence|reviews/` changed between candidate and released head.
- Evidence README missing or not byte-identical to the regenerated output.

Owner decisions remain: scope, risk acceptance, money, access, public launch. Defender and SmartScreen are never bypassed.
## Hardening (review findings ARCH-1, ARCH-2, SEC-1, SEC-2, ENG-1, QA)

- **Review files are evidence (ARCH-1).** Every sign-off must cite `release/reviews/<candidate>/<role>.md`; the file must exist and be non-empty. Every non-URL evidence path must exist in the repo.
- **Artifact provenance (ARCH-2).** Before any bytes are downloaded, the release job fetches the signed run and its artifacts from the GitHub API and requires: run id equals the signed `runId`, `head_sha` equals the candidate, a successful `push` event of `.github/workflows/ci.yml` in this repository, and exactly one non-expired `bloomstep-universal-installer` artifact whose id equals the signed `artifactId`.
- **No record data in shell templates (SEC-1).** The release job never interpolates `${{ }}` record values into scripts. The candidate and artifact ids are emitted only by the verifier after validation, regex-checked again in bash, and passed through `env:`.
- **Timestamps (ENG-1).** `reviewedAt`, `ownerAcceptance.at` and `testedAt` must be real ISO-8601 UTC instants (e.g. `2026-02-30T25:61:00Z` is rejected).
- **Owner trial record (QA).** Public launch requires `release/owner/<candidate>.json` (schema `budlark-owner-trial-v1`) with `result: PASS`, `installerSha256` equal to the signed bytes, `by`, `testedAt`, and an `https` `reference` to the owner's statement. Only the coordinator writes it, and only from the owner's own statement. It is shipped with the release and rendered in the evidence README.

## Trust model (SEC-2)

Role sign-off records are **agent attestations**: they provide accountability and traceability, not authentication. Authenticated human authority comes from GitHub itself:

1. The release job runs in the `public-launch` environment, which requires the owner (Sampath-K) as reviewer before it can run.
2. Only the owner can push `v*` tags (tag ruleset), and workflow-file changes require owner credentials.

A forged sign-off record therefore cannot publish anything without the owner's authenticated approval of that exact run.

### Owner trial authentication (QA-1)

The owner trial record's `reference` must be a GitHub issue or PR comment URL in this repository
(`https://github.com/<repo>/(issues|pull)/<n>#issuecomment-<id>`). Before promotion, the release job
fetches that comment through the API and fails unless it is authored by `github.repository_owner`
(`author_association: OWNER`, user account), unedited, names the exact candidate commit and installer
SHA-256, and states PASS with no FAIL. The coordinator writes the record only after the owner posts
that comment. Verified live (2026-10-18): Sampath-K is the sole collaborator and admin of this
user-owned repo, so the ruleset's admin-role bypass and the `public-launch` required reviewer both
resolve to the owner.

## Marketing and visual brand role (owner request, 2026-10-18)

The owner asked that all customer-facing brands, names and images be vetted and recommended by marketing and branding experts. `brand-marketing` is required at `owner-test`: it owns the Budlark visual identity (theme, app icon, songbird/lark motif, imagery), and signs off on every customer-facing surface: app, installer, Start menu, tray, sign-in pages (Microsoft Entra and Google consent screens), website, store listing and launch assets. `editorial-brand` keeps voice and naming consistency. Owner-test now requires 8 roles and public launch requires all 13.
## Functional evidence before the owner trial

The owner must never be the first person to find a functional failure. Both gate stages (`owner-test` and `public-launch`) require `release/evidence/<candidate>/functional/`:

- `results.json` (schema `budlark-functional-evidence-v1`). It must bind the same candidate commit, installer SHA-256 and CI artifact as the sign-offs, and record `environment.kind: clean-windows-vm`, an https run link and `executedAt`.
- One `PASS` test for every requirement in `release/functional-requirements.json`. Each test has a log; UI requirements also have light and dark screenshots. All paths must sit under the functional folder.
- For every owner-reported bug (`regression: true`), `baselineResult: FAIL` proves the same test failed on the baseline build `083f2de`.
- `README.md`: the human evidence pack the owner reads before receiving the installer.

`release/functional-requirements.json` maps every owner feedback item to a requirement or a named process gate. A unit test fails if any item is left uncovered.
