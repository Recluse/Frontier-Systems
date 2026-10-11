# Checkpoint recovery milestone

Scope: `src/adapters/persistence`, `tests/godot/checkpoint_recovery_test.gd`, and this document. Based on coordinator integration commit `45921a317f0ad38d1fa857626b7304019891dbed`. No world authority, network wire, production schema or snapshot migration changes are required.

## Contract gaps identified and fixed

The former writer truncated the alternating slot directly, while the adapter advanced sequence on every attempted write. Two failed attempts could therefore truncate the only good checkpoint. The writer also accepted invalid snapshot text and checked only the snapshot size, overlooking JSON escaping in the envelope. It acknowledged write/flush without readback, and the adapter trusted any successful result and left shutdown state pending.

`LocalWorldSaveStore` now validates the world envelope and both UTF-8 byte limits before opening staging storage. A write must immediately follow the latest committed sequence. Retrying the identical sequence and snapshot returns its already committed acknowledgement; stale/skipped sequences and changed content at the same sequence fail with `save_sequence`.

The worker writes `world-{a,b}.json.tmp`, flushes and closes it, then reads it back with a byte bound and requires exact equality. Only after verification does it remove the inactive destination and rename staging to the committed slot. This avoids relying on overwrite-rename behavior on Windows. The latest valid slot remains untouched through staging, verification, inactive-slot removal and failed promotion. After a process interruption, either the prior committed slot or the newly promoted slot is a recovery candidate; staging files never are. Successful promotion consumes staging; failures attempt cleanup and report `save_cleanup` if cleanup itself fails. Abandoned staging is overwritten on the next safe retry.

## Ownership and acknowledgement

- `WorldRuntime` owns canonical state. Capture remains outside ticks; startup restore finishes before simulation begins. The adapter changes storage status, never simulation records on completion.
- A `CheckpointTask` owns detached directory, sequence, captured tick and snapshot JSON. Its worker touches only storage and its result. The main thread joins a completed task before reading that result.
- `request_checkpoint()` success means queued work. `checkpoint_completed` success means the flushed, verified envelope was promoted (or an identical committed retry was found). It names the captured tick, even if simulation has advanced while storage runs.
- Committed sequence and `saved_tick` advance only after an exact, typed sequence acknowledgement for that task. Missing, malformed and stale results produce `checkpoint_acknowledgement`; a failed write retains the previous saved tick and sets `last_error`.
- Only one task runs at a time. Completion clears the old task before emitting, so a callback may queue another checkpoint safely. Autosave cadence remains five seconds; normal frame processing joins only tasks already reported complete.
- Sequence exhaustion fails before capture/task creation. Shutdown closes the adapter, joins its worker outside simulation ticks, consumes its result and emits no late completion callback. A removed adapter cannot start further work.

The existing `status()` fields (`saved_tick`, `busy`, `last_error`) remain the bounded observation surface. Storage failures have reason codes for directory creation, staging open/write, verification, cleanup, promotion, bounds, corrupt slots, unreadable slots and sequence conflicts.

## Recovery contract and limits

Committed filenames, envelope fields and `schema_version: 1` are unchanged. Even sequences belong to slot a and odd sequences to slot b. Recovery reads at most two committed files, each bounded to 16 MiB; snapshots are bounded to 8 MiB of UTF-8. It checks exact fields, integer version/sequence bounds, slot parity, SHA-256 and the shared world envelope, then selects the highest valid committed sequence. Truncated, oversized, checksum-invalid, structurally invalid or misplaced slots fall back to the other valid slot. Two invalid slots fail closed and are preserved. An unreadable slot also fails closed, because it could contain a newer checkpoint that must not be overwritten.

Actual system/cross-system restore validation stays in `WorldRuntime` on startup. A checksum-valid envelope that the domain rejects remains a visible restore error; this milestone does not silently skip incompatible identities, catalogs or system records. Files are preserved for operator recovery. It does not change runtime authority to add transactional domain fallback.

One adapter/process must exclusively own each save directory. This is a local checkpoint protocol, separate from PHP repository compare-and-swap and request-id contracts. A committed write whose acknowledgement was lost may survive restart; changed content cannot reuse its sequence. Reload the persisted checkpoint before resuming after an uncertain/external write. This is not a per-command journal or an exactly-once command durability promise.

Godot flush/readback/rename acknowledgement is an OS-level local write guarantee. It does not establish hardware power-loss durability, directory metadata fsync, filesystem/device ordering or recovery from both slots failing. Shutdown joins the worker and can wait for OS I/O; no portable hard thread cancellation is added. Process interruption scenarios are constructed at storage phase boundaries rather than proven with real device power cuts.

## Verification

Windows, Godot 4.7.2 console, after rebasing onto the coordinator baseline:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames 'checkpoint_recovery_test.gd','first_playable_acceptance.gd','control_runtime_recovery_test.gd','sustained_extraction_test.gd' -TestTimeoutSeconds 120 -OutputDirectory 'var/ci/checkpoint-recovery-final'
```

All six checks passed: import, startup, dedicated recovery, control runtime recovery, two-client first playable acceptance and sustained extraction. The final additional callback/rejected-restore scenarios also passed in the focused runner (import, startup, recovery). Logs/JUnit are in `var/ci/checkpoint-recovery-final/` and `var/ci/checkpoint-recovery-final-focused/` in this worktree.

Dedicated recovery scenarios use randomized temporary directories and injectable filesystem failures. They cover partial and checksum-valid unpromoted staging, corrupt/truncated/checksum-invalid/oversized/misplaced slots, invalid snapshot and encoded-envelope bounds, repeated directory/open/write/flush/read/removal/promotion failures, cleanup failures, sequence exhaustion/conflicts, identical acknowledgement retries, malformed/missing/stale completions, callback reentrancy, incompatible startup restore and shutdown. A gated worker proves world ticks continue while storage is blocked; writes run off the main thread, report only the captured tick and leave disposable storage cleaned.

The existing CI runner discovers the new test automatically on Windows and Linux through `.github/workflows/ci.yml`; it is not in the excluded list. Remote CI status must be checked against the final PR SHA before integration. Local Linux, graphical, export, live-service and device power-loss verification were not performed. The two-client regression uses its existing isolated loopback fixture; no external service or live world save is used.
