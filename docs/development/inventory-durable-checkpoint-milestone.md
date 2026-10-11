# Durable queued inventory checkpoint acceptance

This successor to PR #70 closes the acceptance gap between the queued controller lifecycle, world checkpoint validation and durable storage. It adds `inventory_durable_checkpoint_test.gd` and changes no runtime code, schemas, production admission or networking.

## Ownership and composition

The fixture uses `WorldRuntime`'s actual default inventory owner and its health, tools, production and terrain associations. It adds no item matter or alternative inventory records. Actions pass through one `InventoryRuntimeCommandQueue` (capacity four, one attempt per tick), its exact controller authority and an injected same-process authenticated-session provider. Inventory snapshot v4, world snapshot v1 and local checkpoint envelope v1 remain unchanged. Sessions, controller tokens, pending intents and outcomes remain volatile; canonical epochs, jobs, grip reservations, item records and receipts remain inventory-owned.

The queue exclusively advances inventory. For each manually driven test tick the fixture temporarily unregisters inventory from the actual `SimulationRunner`, advances it through the queue, runs the remaining world systems, then re-registers it before any world capture. This prevents double advancement while retaining the complete real world checkpoint system set and cross-system validation. Automatic physics and periodic persistence processing are disabled in the fixture. This explicit test composition does not install the queue into production networking or prescribe a production scheduling adapter. No ports or external services are used.

The existing `WorldPersistenceAdapter` captures detached world JSON between ticks, writes through `WorkerThreadPool` and `LocalWorldSaveStore`/native `CheckpointFileIO`, and acknowledges the captured tick only after verified staging/promotion. Writes never execute in a simulation tick. Each test uses a unique temporary user-data directory, a bounded five-second acknowledgement wait, and removes its files on completion. One adapter owns each directory at a time.

## Acceptance evidence

- An actual queued take reaches progress 179 of the default 180 ticks, alongside a cooperative grip reservation. The full world is saved asynchronously into sequence 1 and read back through the checksum-validated committed-slot decoder, byte-identical to the captured JSON.
- The source world and adapter are destroyed. A replacement world, queue and authority exist before adapter loading, with a pre-load bound token and pending resume. Loading restores the exact world tick, pauses the job and grip, and fences the pre-load token. Queue restore detection discards exactly one volatile intent without advancing inventory.
- That paused final-tick record is itself durably saved as sequence 2. A second replacement loads it. After explicit startup, 180 ticks preserve progress 179, the exact serialized owner, and the complete paused grip record: no automatic transfer, receipt or grip continuation.
- Trusted reconciliation and a fresh epoch-checked bind invalidate restored participating work and release its grip. The old token stays denied; a fresh identity cannot resume the invalidated job. The owner stays exactly conserved.
- A fresh queued take earns no progress on admission, has no receipt at progress 179 and completes on the next tick with one receipt. All stable item fields, including IDs, definitions and condition/provenance records, are conserved except the intended crowbar container. Fixed item definitions retain their mass/volume; this is not a dynamic terrain-payload production test.
- Sequence 3 stores the exact completed owner and receipt. Another replacement runtime loads it, discards a pre-load duplicate intent, reconciles and rebinds. Retrying the original completion request ID and revision fails; 180 further ticks leave the exact serialized owner and its one receipt unchanged.
- Isolated truncated and checksum-corrupt files are refused by storage. Checksum-valid envelopes containing a future saved job epoch or malformed owner receipt are refused by domain validation. Each refusal preserves the complete world JSON, existing pending-queue counters, scoped controller observation, original file bytes and saved-tick status. A failed configure cannot start a writer over the corrupt source.

Godot JSON parsing represents numbers as float variants, so owner/item comparisons normalize through JSON. Disk readback compares the exact serialized world string. Existing checkpoint recovery tests separately cover corrupt newest-slot fallback, interrupted staging, write/flush/promotion failures, lost acknowledgements and shutdown. This test adds their actual queued inventory/world composition rather than duplicating the fault matrix.

## Verification and limits

Windows, pinned Godot 4.7.2, versioned bounded runner:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' -TestNames inventory_durable_checkpoint_test.gd,inventory_queued_job_lifecycle_test.gd,inventory_runtime_test.gd,checkpoint_recovery_test.gd,inventory_controller_lifecycle_test.gd,inventory_runtime_command_queue_test.gd -TestTimeoutSeconds 60
```

The added test proves actual subsystem/controller lifecycle through full world-envelope validation and temporary filesystem storage, including worker acknowledgement and replacement runtime recovery. It does not prove power-loss durability, OS-level fsync guarantees, process-crash recovery, production session admission, live-service transport, graphical play, controller/VR acceptance or Linux local execution. Existing CI discovers the test and runs the headless suite on Windows and Ubuntu. Exact-head CI results and tested revisions are reported with the PR; pending CI is not a pass. No environment-variable/configuration changes, merge, release, deployment or public media are included.
