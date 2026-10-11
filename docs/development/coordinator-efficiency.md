# Coordinator snapshots and focused CI

The historical coordination evidence in `milestone-coordination.md` stays intact.
The Coordinator owns an explicit active-state record and uses a read-only snapshot
command to compare current evidence and due deadlines without rereading the whole
ledger at every heartbeat. Workers must not overwrite the Coordinator's state.

CI validates feature work through pull requests to `dev-master`, retains merge
queue checks, and keeps full builds for integration pushes and manual dispatch.
Only an explicit prose-only pull request classification may omit runtime jobs;
the stable `CI required` gate still reports and validates the classification.

This tooling does not authorize merges, deployments, public media, or outreach.
Exact reviewed heads and required checks remain the merge evidence. Art
provenance, owner approval routing, exclusive task boundaries, and port
reservations remain governed by the existing project instructions.

## Active-state contract

Copy `coordinator-active-state.example.json` to ignored
`var/coordination/active-state.json` in the primary checkout. Populate it from
current trusted task status, exact PR heads, the fundraising publication ledger,
the last verified website observation and current approvals. The example's null
timestamps deliberately produce `refresh_required`; never invent a timestamp or
reuse a stale deadline to suppress work. Use ISO 8601 timestamps with an explicit
timezone, for example `2026-10-11T05:30:00Z`.

The v1 record has these fields:

| Field | Meaning |
| --- | --- |
| `schema_version`, `repository` | `1`, `Valgorithms/Frontier-Systems` |
| `active_tasks[]` | `thread_id`, nullable `pr_number`, nullable `head_sha`, `scope`, `status`; a PR requires its immutable 40-character head SHA |
| `website` | `status`, `checked_at`, `next_check_at`; record the actual next authorized follow-up |
| `fundraising` | `last_confirmed_public_post_at`, `next_monthly_due_at`, Boolean `unreported_progress`; About/profile changes do not reset public-post timing |
| `pending_approvals[]` | Concise unresolved approval summaries for Coordinator routing |
| `tutorial_gate` | `open`, `awaiting_human` or `accepted`; preserve the actual human acceptance boundary |
| `ledger_sha256` | SHA-256 of the exact current ledger bytes reconciled into this state |

Read the latest ledger before reconciling changed evidence. Update this small
record only after reconciliation; if the ledger changes concurrently, the next
snapshot reports the mismatch. The helper never edits or archives the ledger,
updates state, makes network requests, or writes the previous snapshot.

## Snapshot invocation

Use PowerShell **7.5 or newer** (JSON timestamp parsing must preserve strings):

```powershell
$next = ./tools/coordination/snapshot.ps1 `
    -StatePath ./var/coordination/active-state.json `
    -PreviousPath ./var/coordination/previous-snapshot.json `
    -PullRequestsPath ./var/coordination/pr-evidence.json
$next # inspect/consume before replacing the prior snapshot
```

`-LedgerPath` defaults to this repository's ledger. Supply the primary-checkout
path when running a bundled copy of the helper. On the first invocation omit
`-PreviousPath`; a supplied missing previous file explicitly requests refresh.
Only after handling the snapshot should the Coordinator save `$next` to its
ignored previous-snapshot file. Never redirect output over a source input.

`-PullRequestsPath` contains a compact read-only capture of GitHub evidence:

```json
{
  "captured_at": "2026-10-11T05:30:00Z",
  "pull_requests": [{
    "number": 40,
    "state": "open",
    "draft": true,
    "head_sha": "0123456789012345678901234567890123456789",
    "checks": [{
      "name": "CI required",
      "head_sha": "0123456789012345678901234567890123456789",
      "status": "completed",
      "conclusion": "success"
    }]
  }]
}
```

Capture **all** checks for each exact head, including required/focused workflows;
the one-check example illustrates the shape, not a permission to omit checks.
Use REST PR/check-run data or an equivalent verified source, following all pages.
Status is `queued`, `in_progress` or `completed`; an unfinished conclusion may be
null. Every active PR requires exactly one evidence record, matching check heads,
and `CI required`. The default evidence age limit is 15 minutes. Missing, invalid,
future, expired or mismatched data produces `refresh_required`, never readiness.
Use `-EvidenceMaxAgeMinutes` only to apply an intentional freshness policy.

The JSON output exposes `fingerprint`, `changed`, `attention_required`,
`refresh_reasons`, `due`, `deadlines`, current tasks/checks and a bounded newest
ledger section (4,096 characters by default). The fingerprint excludes the
snapshot generation time and PR capture time, so timestamp-only refreshes do not
manufacture changes. It includes state, ledger bytes, PR identity and check
results. A changed head invalidates prior immutable review. These summaries do
not certify merge readiness; recheck the exact reviewed head and every required
gate before an authorized merge.

Independently of `changed`, the helper evaluates public-post preparation at
23 hours, its 24-hour deadline, monthly benefits, and website follow-ups. Due or
unknown obligations require attention even when no PR changed. A no-progress
decision must be explicit and evidenced; it does not fabricate a publication.
Pending approvals also require attention. Headless/scripted checks do not close
the tutorial's native/human acceptance gate.

## Focused verification

`tools/ci/test-ci-policy.ps1` checks prose and unsafe path classification, actual
Git diffs and runtime-to-document renames, event defaults and required-gate result
permutations. `tools/coordination/test-snapshot.ps1` uses temporary offline JSON
and ledger fixtures to check deadline boundaries, unchanged and changed state,
missing/future/stale evidence, exact PR heads, bounded excerpts and preservation
of original ledger bytes. Both run in the lightweight classifier job. The full
game suite remains in its existing jobs whenever the change is not prose-only.
