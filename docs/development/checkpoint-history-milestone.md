# Checkpoint backup history milestone

Opt-in operator recovery history extends the [checkpoint recovery protocol](checkpoint-recovery-milestone.md). Scope is `src/adapters/persistence`, `tests/godot/checkpoint_history_test.gd`, and this contract. Active `world-a.json` / `world-b.json` filenames, sequence acknowledgement, v1 envelope, snapshot/domain schemas, network messages and UI remain unchanged.

## Ownership and lifecycle

`WorldRuntime` owns canonical world state. Capture occurs outside ticks with no pending commands. `WorldPersistenceAdapter.CheckpointTask` owns only detached directory, sequence, captured tick, JSON, retention policy, injected filesystem adapter and two separate results. Its worker commits the active slot first, then optionally archives the exact committed bytes. Neither result mutates world records. One worker/writer owns the directory, and frame processing joins only completed tasks. The five-second autosave cadence is unchanged; there is no per-command journal.

History is disabled when the fourth `configure()` argument is null. An operator integration can enable it with:

```gdscript
var retention := CheckpointHistoryPolicy.new(3, 33554432)
var configured: ServiceResult = adapter.configure(world, directory, null, retention)
```

The default enabled policy keeps three entries within 32 MiB of encoded UTF-8 envelopes; valid configured limits are 1-8 entries and 1 byte through 64 MiB. Configuration is copied at admission and again into the worker, so caller mutation cannot change in-flight work. There is no launcher/network/UI enablement in this milestone.

## Archive protocol and bounds

The history directory is `checkpoint-history/`. The writer scans exactly nine known `backup-0.json` through `backup-8.json` names, using one spare for Windows promotion before pruning. Every file read is at most 16 MiB and its embedded snapshot at most 8 MiB. It validates exact v1 fields, sequence bounds, SHA-256 and the shared world envelope. Listings return at most nine metadata descriptors containing fixed slot, original sequence, captured tick, checksum, world/region identity and encoded bytes. Rejected known files are reported with slot/reason code. No arbitrary filenames, directory traversal or manifest side effects are involved.

Only a slot whose sequence and snapshot exactly match the acknowledged task can be archived. Its existing v1 bytes are written to the single `archive.tmp`, flushed/closed, read back exactly, and promoted into an absent fixed backup slot. Partial, checksum-invalid, oversized or unreadable committed-name backups are rejected. `archive.tmp` is never listed or selectable, even when complete and checksum-valid. Interrupted staging is overwritten on retry; failed cleanup is separately visible. Identical committed archive retries do not create duplicates; conflicting content, newer history or mixed world/region identity fail visibly.

The writer prunes oldest sequences after the new verified backup is promoted. Active slots are outside its path set. It never removes the last structurally valid backup. Steady retention satisfies both configured count and total encoded bytes. A post-promotion prune failure can leave one spare entry and at most `retained_bytes + min(retained_bytes, 16 MiB)` valid archive bytes. Before the next archive, the worker must repair that excess; repeated prune failures cannot accumulate new backups. The staging file also has a 16 MiB limit. The conservative fixed-name physical bound is nine committed files plus one staging file, each at most 16 MiB (160 MiB), independent of retries. Normal reachable writer states are tighter. Unknown operator-created files are outside managed retention and are neither scanned nor deleted.

When an operator shrinks retention, existing data is preserved until safe pruning succeeds. If the last backup alone exceeds the new byte policy, archiving returns `backup_bounds`; it does not delete the last backup to satisfy a changed limit. Invalid/unreadable known entries stop new archival/pruning with `backup_scan`, preserving evidence for explicit inspection. There is no broad cleanup or automatic deletion of corrupt files.

## Separate acknowledgement and diagnostics

`checkpoint_completed` retains the exact active acknowledgement contract: success means a committed active checkpoint, regardless of backup outcome. `saved_tick`, `busy` and `last_error` keep their existing meaning and network shape. Completion waits for this worker's archive attempt, but neither active nor backup I/O blocks simulation ticks.

The separate local operator `backup_status()` returns `enabled`, `sequence`, `last_error` and `error_code`. Sequence is the latest successful history acknowledgement in this adapter session, zero until one succeeds. Backup directory/write/verification/promotion/cleanup/scan/identity/sequence/bounds/prune/acknowledgement failures never replace a successful active result or falsely roll back its saved tick. A later successful archive clears the backup error. On active failure no archive is attempted, and prior backup diagnostics remain. An interrupted post-promotion prune may have produced a selectable new backup even while history status reports failure; an operator listing is authoritative for available candidates.

## Explicit startup recovery helper

`CheckpointBackupHistory.list_candidates(source)` is read-only and metadata-only. The operator explicitly chooses a whole descriptor and calls `select_candidate(source, descriptor)` or `adapter.configure_from_backup(world, source, descriptor, absent_destination, files, policy)`. Selection re-reads and validates the candidate and compares every descriptor field. A changed, missing or corrupt selection fails; another entry is never silently substituted. Listing/selection storage work is for stopped-world startup or a worker, never tick callbacks.

The configure helper accepts only a fresh, unconfigured adapter/world before simulation has ever started or commands have been queued. `WorldRuntime` checks world/region identity, system records and cross-system links using its existing startup restore contract. A running world, or one stopped after starting, rejects rollback. Domain-incompatible history remains a visible error; generic codec validity alone is not proof of domain compatibility.

Recovery requires an absolute destination outside the source tree and rejects active/queued worlds before any storage access. The existing owner still rejects an already-started world after stopping. Recovery seeds a new, previously absent destination with the selected snapshot at active sequence 1, preserving its tick. The source active slots and original history sequence/checksum/identity remain untouched. Future checkpoints advance the fresh destination sequence, so recovery cannot collide with newer source slots or silently overwrite them. An existing destination rejects before writes. A seed storage failure returns its active write error, closes the failed adapter, claims no saved tick, and requires discarding the fresh startup world/adapter before retry. Startup restore may already have populated that disposable world; do not start it after any configuration failure. Partial destination evidence is preserved.

Automatic `configure()` continues to consult only active slots. Two invalid slots fail closed even when good backups exist. No live save is touched by this helper or its tests. No uploads, SQL/accounts, journal, production/world schema, network, launcher or UI changes are included.

## Verification

Local Windows verification followed a rebase onto `origin/dev-master` at `bef1b39622a6b0fbbc19f1b10f02819f3314d82d`. Godot 4.7.2 console at `D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` passed import, startup, history, checkpoint recovery, control-runtime recovery, sustained extraction and first-playable two-client acceptance on runtime commit `8683bf9ec0cee0f106c83bfa59b6648462b8d87c`. Acceptance passed in 36.18 seconds and port 27849 was released immediately. The final additional operator preflight/source-tree guards on `b0202a5` passed all six non-network checks again. Logs/JUnit remain in this managed worktree at `var/ci/checkpoint-history-final/` and `var/ci/checkpoint-history-final-guards/`.

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames 'checkpoint_history_test.gd','checkpoint_recovery_test.gd','first_playable_acceptance.gd','control_runtime_recovery_test.gd','sustained_extraction_test.gd' -TestTimeoutSeconds 120 -OutputDirectory 'var/ci/checkpoint-history-final'
```

Draft PR [#4](https://github.com/Valgorithms/Frontier-Systems/pull/4) targets `dev-master`. Exact final commit and remote CI are reported with the PR; earlier successful draft CI is not evidence for the implementation head. Coordinator/human review and authorization are required before merge; this chat does not merge, deploy or push the integration branch.

The bounded versioned runner imports and starts the project, then runs the history/recovery/control-runtime-recovery/sustained-extraction tests. History scenarios use randomized temporary directories, injected I/O and a semaphore-gated archive worker: opt-out, copied policies, count/byte retention, exact envelope metadata, idempotent retry, uncommitted sources, identity conflicts, partial/unpromoted staging, interrupted write/flush/read/promotion/cleanup/pruning, full eight-entry retention plus spare, restart retry, unreadable/oversized/checksum-invalid backups, stale/tampered selections, active success despite backup failure, nonzero-tick startup recovery, source/destination preservation, running/stopped-world rejection, domain rejection, failed recovery seed and shutdown joins. No live player storage or external service is used.

The existing CI runner automatically discovers this test on Windows and Linux. Local Linux, graphical, packaged export, live-service and real device power-loss verification are outside local evidence. Flush/readback/rename remains an OS-level guarantee, not hardware power-loss durability or directory fsync. Shutdown can still wait on OS I/O; no thread hard-cancellation is added.
