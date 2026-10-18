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