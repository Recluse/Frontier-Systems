# Queued inventory write-fault recovery acceptance

Successor to PR #72, based on integration commit `7afab62c00f2ce823452e2145af75ba2785bfc00`. Inspection found existing low-level fault coverage in `checkpoint_recovery_test.gd`; this change extends the existing queued inventory acceptance fixture with the missing worker/filesystem integration evidence. No runtime defect was reproduced, so no runtime code, schemas, queue ownership, networking, configuration or presentation changes are included.

## Composition and acceptance

The real `WorldRuntime`, `InventoryRuntimeCommandQueue`, controller authority, `WorldPersistenceAdapter`, worker and `LocalWorldSaveStore` operate against unique temporary native filesystem directories. The injected `CheckpointFileIO` delegates successful operations to native storage. Inventory remains canonical; inventory v4, world snapshot v1 and checkpoint v1 contracts remain unchanged. Physics and periodic autosave are disabled in this acceptance fixture, using the existing queue-exclusive tick driver. No external services or ports are used.

For each staging-open, partial-write, promotion and staging-cleanup failure, the fixture saves an actual queued transfer at progress 179, then completes it to produce one canonical receipt. Two asynchronous failed saves must each emit one failure for the captured tick, release busy within the five-second test deadline, retain the previously acknowledged tick, preserve the exact prior committed slot bytes, and leave the complete world JSON, queue counters and controller observation unchanged. Overlapping requests are rejected. A cleanup failure retains unpromoted staging, which recovery ignores; other injected failures remove staging.

After the worker joins, the test clears the injected fault and explicitly requests another checkpoint without advancing ticks. Readback must match the original captured world JSON exactly, with sequence 2, one receipt, no duplicate completion and no remaining staging. This establishes exact-snapshot retry for these pre-commit failures with an unchanged world; it does not introduce a retained-snapshot retry API or establish retry safety after an uncertain committed write while the world advances.

A single replacement runtime then exercises envelope-corrupt newer-slot fallback through the actual adapter. It loads the valid older final-tick checkpoint, discards its pre-load volatile intent through the restore fence, pauses saved work, and advances 180 ticks without completing it or manufacturing a receipt. Both source slots remain byte-identical. This allowed structural fallback does not bypass checksum-valid domain rejection; the existing refusal tests cover that boundary.

## Verification and limits

Use the versioned bounded runner:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' -TestNames 'inventory_durable_checkpoint_test.gd','checkpoint_recovery_test.gd' -OutputDirectory 'var/ci/inventory-write-faults-final'
```

Windows Godot 4.7.2 import, startup and the two selected checks passed on the final test content. Logs/JUnit remain ignored in the managed worktree. The existing CI discovers the extended check on Windows and Ubuntu; exact-head results are reported in the PR handoff and pending jobs are not passes.

Native writes, flush/readback and rename are exercised, while failures are constructed at the injected filesystem boundary. These checks establish neither process-crash durability nor device power-loss durability, directory fsync or hardware ordering. Busy cleanup is bounded for these injected operations, not for indefinitely blocked OS I/O. Local Linux, graphical/controller/VR, production session admission, live transport, export and external services were not exercised. No merge, release or deployment is authorized by this milestone.
