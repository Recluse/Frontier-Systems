# Queued inventory job lifecycle acceptance

This milestone extends PR #68 with an actual-runtime acceptance test, without changing runtime behavior or schemas. `inventory_queued_job_lifecycle_test.gd` composes `InventorySimulationSystem`, its real health provider, and one `InventoryRuntimeCommandQueue` with that queue's exact controller authority and scoped read gate. No development-command dispatch is used for tested actions.

## Acceptance contract

The fixture reuses the validated four-body setup from the controller lifecycle test: two existing bodies plus two empty bodies for independent work. It adds no items or payload matter. The FIFO has capacity four and drains one attempted command per tick, including denied attempts. Default policy durations remain search 120 and transfer 180 progress ticks; the command start boundary earns no progress.

Two independently configured runs compare full checkpoints, queue counters and scoped observations at milestone boundaries. They exercise:

- Search readiness at exactly tick 120, direct pouch visibility, and rejection of another bound actor's search read.
- Cooperative grip participation and an independent actor's ladder reservation, through queued joins.
- Replacement one progress tick before transfer completion: cancelled job/outcome, retired search, released participating hands, conserved owner records, and exact preservation of an unrelated job and grip. That unrelated job completes on its original schedule.
- A stale resume consuming the one-command drain budget, followed by an unrelated FIFO command succeeding on the next boundary.
- Revocation during active transfer, denied stale resume/read, and 180 further ticks with no transfer or receipt.
- JSON checkpoint recovery at transfer progress 179: volatile intents discarded without a tick, jobs and grip reservations paused, and 180 ticks with no automatic completion.
- Explicit authority reconciliation and fresh binds: old paused ownership is invalidated; even a fresh identity cannot resume that cancelled job. New work must use a fresh request.
- A fresh transfer completing after exactly 180 progress ticks, with one retained receipt and unchanged stable item records except the intended container. Skipped and duplicate boundaries preserve the complete checkpoint.
- Completed-receipt JSON recovery followed by retry of the original request ID and revision: refusal and 180 further ticks leave the recovered inventory owner unchanged.

JSON comparisons normalize numbers at the serialization boundary because Godot's parser represents JSON numbers as float variants. Retry-state comparisons use the actual recovered record directly. Item conservation compares all fixture item records, including IDs, definitions, revisions and condition; unchanged definitions retain their fixed mass/volume. This does not model terrain payloads or dynamic material production.

## Ownership and recovery

Inventory canonical owner, body epochs, jobs and grip records remain in the simulation runtime, persisted in inventory snapshot v4. The queue is volatile and owns fixed-tick admission, capacity, attempt budget and scoped observations. Controller lifecycle changes commit canonical epochs and invalidate participating jobs, views and grips before publishing new identity. Outcomes are bounded, principal-scoped and volatile. Restore generation clears queued intents and fences tokens; reconciliation alone does not grant a controller. Fresh binding advances the canonical epoch and cancels participating restored work. It is not a continuation grant for a saved transfer.

No session-provider denial is treated as canonical revocation: the trusted caller must invoke authority revoke for lifecycle cleanup. This test explicitly uses that contract. Profiling uses existing queue counters; no new diagnostics or state are introduced.

## Verification

Windows Godot 4.7.2, using the versioned bounded runner:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' -TestNames inventory_queued_job_lifecycle_test.gd,inventory_runtime_command_queue_test.gd,inventory_controller_composition_test.gd,inventory_controller_lifecycle_test.gd,inventory_command_drain_boundaries_test.gd,inventory_runtime_test.gd -TestTimeoutSeconds 60
```

The existing CI workflow discovers headless tests and runs them on Windows and Ubuntu; exact-head remote results are reported with the PR. Local execution covers real runtime systems and deterministic ticks, not rendered gameplay, physical controllers, VR, Linux graphics, production authenticated networking, durable storage, or external services. No listener is reserved or started by the added test. World-envelope checkpoint integration remains covered by the existing `inventory_runtime_test.gd`; the new test restores the actual inventory subsystem record through JSON.
