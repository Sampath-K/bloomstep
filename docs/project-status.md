# Private local project status

From the repository root with Node 22+ and an already authenticated `gh` CLI:

```powershell
node tool\project-status\status.mjs collect
node tool\project-status\status.mjs serve
```

For autonomous local source refresh instead of manual collection:

```powershell
node tool\project-status\status.mjs serve --poll-seconds 60
```

This starts an immediate source attempt, then schedules the next only after the
previous attempt finishes. Intervals are bounded to 60..3600 seconds. Partial
and failed reads double the delay up to 8 times the base; an observed GitHub
rate-limit response waits at least 15 minutes. Successful complete reads reset
the delay. Each fixed GET/auth subprocess has a 20-second timeout. No overlapping
poll cycles, shell commands from requests, OS scheduler or cloud service is used.
The server continues serving the last atomic snapshot during collection.
Ctrl+C stops the timer and aborts outstanding subprocesses; restart the command
to resume. Do not run manual `collect` concurrently with the polling process.

Open **http://127.0.0.1:8791/**. Stop the server with **Ctrl+C**. An occupied
port fails rather than attaching to another service; use `serve --port 8792`
if necessary. No dependencies need installing.

Run `collect` again in a second terminal whenever fresh source evidence is
needed in manual mode. The page rereads the saved snapshot and polling status
every 15 seconds, or use **Refresh view**. Neither starts GitHub collection.
Only the explicit `serve --poll-seconds` mode runs local authenticated source
polling; there is no scheduler or refresh endpoint. Observations expire after
five minutes even while the page remains open. No real-time agent-session API is
connected: agent activity is never shown or inferred.

## Executive one-slide view

The page is a single executive slide about the **next release**, not an
engineering board. It shows only:

- **Release headline and readiness**: `narrative.headline` and the readiness
  label from `sources.json`. Readiness stays the configured candidate label
  (currently "Candidate preparation; owner installation validation pending")
  until every milestone has observed done evidence; `Not ready: <milestones>
  needs attention; <pendingNote>` naming every milestone that needs attention; `Unknown` when collection failed, evidence is
  stale (older than five minutes), the latest polling attempt failed or the
  snapshot cannot be read. It never shows shipped, launched or accepted claims.
- **Product taking shape**: reviewed customer-value statements in the release
  candidate, labelled not yet owner-validated or customer-proven.
- **Verified progress**: plain-language milestones mapped from the gating
  launch sequence (hosted checks -> installer candidate -> owner accepted
  installation -> release approved, plus download hosting prepared -> live download
  verified). A milestone is *Done* only for its configured observed states;
  steps without a live source show *Waiting* or *Not yet evidenced*; read errors
  and stale data show *Unknown*. The latest observed milestone state change is
  shown; polling heartbeats are never progress.
- **System improving**: reviewed quality/delivery improvements in the candidate.

No PR numbers, commits, jobs, links, commands, dependency layers or historical
VM gates appear on the slide. The collector still computes the full evidence,
change history, blockers and next actions in the git-ignored
`.project-status\snapshot.json` (`workstreams`, `changes`, `executive`) for
agents; the slide reads only `narrative`. Narrative text lives in
`sources.json` (`narrative`) and is validated: 1-4 short statements per
dimension and milestones that reference configured gating sources. Update it
only from release/website owner review; do not add percent complete or dates.

The owner-trial launch sequence in `sources.json` is: PR52 hosted checks ->
installer artifact -> owner manual installer check -> approved integration/release,
plus PR54 hosting -> live budlark.com download verification -> owner-trial
launch decision. PR52/PR54 are read live; the other steps have no live source and
stay unknown/waiting until evidence exists. Abandoned VM native acceptance, the
combined candidate, PR48/49, visual, preview and hosted GrowthBook rows are
non-gating context in the snapshot only. This tool changes no CI, protections or PRs.

## Source of truth and integration

`tool\project-status\sources.json` owns the bounded workstream definitions,
owners, next actions, accepted dependency states, workflow names and required
job names. It links the existing status ledger, MVP exit matrix and experiment
documentation; it does not replace their acceptance contracts. Update this
reviewed config when PRs/branches/gates change. It is developer tooling, not a
customer dashboard, public marketing page or deployment artifact.

The collector uses only GitHub **GET** calls through the existing local `gh`
authentication. It reads PR48/49, the configured visual branch and its PR,
the latest published release (including prereleases), its resolved tag commit,
and the latest `ci.yml` push run plus **all pages** of jobs for the exact source
SHA and run attempt (also requiring the release tag for native verification).
It does not read PR bodies, release bodies, customer data,
mailboxes, credentials or workflow logs. API responses are reduced to states,
SHA, tag, job names/outcomes and GitHub evidence links. Tokens never enter the
browser, config or snapshot.

`.project-status\snapshot.json` is the generated, git-ignored local data
snapshot and source-observation history. `.project-status\polling.json` records
mode, collecting/partial/failed/stopped state, last attempt/finish, last successful
source read (possibly partial), last complete read, next attempt and errors.
Writes replace each file atomically; they are not a cross-file transaction.
The page displays timestamps, not a guaranteed connection: killed processes
cannot persist their stopped state, and old timestamps/five-minute source expiry
remain visible. It is
not synchronized or indexed into a personal knowledge system, published or
committed: the durable shared index is the reviewed config and existing repo
documents. Regenerate on another checkout using its own approved `gh` login.
No external accounts, resources, permissions, issues, notifications, release
changes or PR mutations are performed by collection/serving.

## Evidence contract

- **Planned**: a configured integration gate with satisfied prerequisites;
  no observed implementation claim. **Implementing**: a draft PR or remote
  branch exists; not proof of current agent activity.
- **Validating**: exact-head workflow jobs are pending. **Blocked**: a failed,
  cancelled or skipped required job, closed unmerged PR, or unmet dependency.
- **Review-ready**: all configured engineering jobs passed, with no failed or
  pending jobs in that workflow run. This is not human approval, branch
  protection evaluation, native acceptance or a universal mergeability claim.
- **Merged**: PR API merge evidence, separately from its displayed workflow
  observations. **Released**: published release plus peeled immutable tag SHA,
  not the release's potentially mutable `target_commitish` branch.
- **Verified**: only the explicitly configured exact-release protected native
  workflow gate, with every named job succeeding. This is bounded CI evidence,
  not provider, cohort, customer safety or public-launch signoff.
- **Unknown**: missing/unconfigured/ambiguous/unreadable evidence. Hosted
  GrowthBook and launch acceptance have no live source configured. Their
  historical OFF/unverified context is labeled, not asserted as current truth.

The combined-candidate row is a dependency gate, **not** a live child-agent
status. It cannot turn verified automatically. Configure an exact candidate
source and independent acceptance evidence in a reviewed follow-up when those
exist; the dashboard makes no completion claim in the meantime.

Dependency edges specify their accepted states: `merged` and `released` cannot
satisfy `verified`. Snapshot rows retain their own observed state even if prerequisites are unmet;
unmet prerequisites are recorded separately in `graph`. Order is by dependency
depth, never by dates, durations or invented progress percentages.

Hosted GrowthBook activation is an independent optional workstream with its
own blockers, not an owner-trial prerequisite (context only): the default-OFF adapter may ship
without hosted activation. This target is not public-MVP readiness; the wider
MVP exit matrix and public-launch acceptance remain separate.

Authentication errors, API failures, timeouts (20 seconds per command), malformed
or incomplete paginated responses produce nonzero collection exit and a visible
failed/partial snapshot. Successful independent sources remain visible. Failed
sources become unknown and keep their previous state, links and observation time
under **Last known**, including across repeated failures. The last complete
GitHub collection time is retained separately. Manual/API-unavailable gates stay
unknown even when GitHub collection is complete. Missing or unreadable snapshots
return HTTP 503; the page retains any previously loaded snapshot explicitly
as stale. Future/invalid timestamps never satisfy dependencies.

The server binds only `127.0.0.1`, rejects foreign Host/Origin headers, serves only
the fixed HTML, snapshot and polling-status routes with no caching, and has no mutation routes.
It is not an authentication boundary against other processes/users on this
machine. Keep the snapshot local; do not expose or proxy the port publicly.

## Contract tests

```powershell
node --test tool\project-status\status.test.mjs
```

These run in the existing API CI job and cover lifecycle separation,
freshness, authentication failures, retained history, partial reads, exact-head
jobs, immutable tag resolution, dependencies and loopback read-only serving.
No GitHub writes, cloud resources or real customer records are needed.
