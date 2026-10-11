# Inventory command drain provider boundaries

## Owner and behavior

This successor to PR66 hardens the explicitly composed `InventoryRuntimeCommandQueue` over one actual `InventorySimulationSystem`. The trusted same-process owner retains controller lifecycle authority and calls one consecutive `advance_tick(tick, fixed_delta)` boundary. Commands precede job advancement; inventory must not also run in another runner. No network admission or production composition is added.

The command gate pins canonical last tick and restore generation before synchronous session-provider validation and checks runtime validity, generation and last tick again before dispatch. This prevents applying stale intent when a provider frees, advances or restores the actual runtime, including a restore reconciled inside the callback. Ordinary provider denial still consumes one bounded attempt and lets the queue continue normally.

After every gate attempt, even a denied one, the queue checks validity before accessing the runtime, detects restore and checks canonical tick ownership. Interruption returns `queue_unavailable`, `queue_restored` or `queue_tick_mismatch`, releases the busy guard, discards all unattempted intents and increments the boundary rejection counter. Each popped entry counts as an attempt; only unattempted entries count as discarded. Restore clearing and interruption share discard accounting so the remainder is counted once. No transient outcome list is returned on interruption; earlier successful commands remain canonical and are not rolled back. Callers must consult canonical state/receipts rather than interpret boundary failure as an atomic batch rollback.

The queue never adds a job tick after interruption. Restore resynchronizes its last tick, but controller reconciliation and fresh bind/pin remain caller-owned. Direct advancement does not silently transfer tick ownership or resynchronize the queue; subsequent calls continue to fail closed until an explicit restore/recovery. Freed runtime remains unavailable. Duplicate, skipped or externally mismatched ticks detected before draining retain pending intent as before. Busy callbacks cannot enqueue or recursively drain.

Inventory snapshot v4 and all shared schemas remain unchanged. Canonical owner, conservation rules, fixed-tick cadence, bounded per-tick outcomes and saturating profiling counters remain in place. No dependencies, configuration/environment variables, assets or third-party provenance change; all additions are first-party MIT.

## Verification

`inventory_command_drain_boundaries_test.gd` uses real inventory, health, queue, controller authority and session providers. Twelve interruption cases free, advance or restore during the first or second attempted command, including denial after free/advance and reconciliation/rebinding after restore. They verify exact error codes, no transient outcomes, callback invocation, released busy state, attempted/discarded/pending/rejection accounting, no stale command dispatch, no extra job tick, complete post-callback inventory conservation, no double advance and fresh post-restore draining. A normal callback case verifies successful FIFO draining, reentrancy refusal, ordinary provider denial, tick advancement and full inventory conservation.

Before the implementation fix, the real-health fixture produced 16 assertion failures plus freed-runtime diagnostics. After the fix, Windows Godot 4.7.2 import/startup and the new fixture pass. Twelve existing regressions also pass: queue, gate, composition, authority, lifecycle, observations, inventory runtime, grip runtime, self/world inventory, search views and checkpoint recovery. A callback counter reset in the additional normal-provider fixture was corrected and that fixture rerun; the unaffected twelve regression results were reused.

The existing bounded, port-free runner was used:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames inventory_command_drain_boundaries_test.gd,inventory_runtime_command_queue_test.gd,inventory_controller_composition_test.gd,inventory_runtime_command_gate_test.gd,inventory_controller_authority_test.gd,inventory_controller_lifecycle_test.gd,inventory_controller_observation_test.gd,inventory_runtime_test.gd,inventory_grip_runtime_test.gd,self_inventory_runtime_test.gd,world_inventory_runtime_test.gd,inventory_search_views_test.gd,checkpoint_recovery_test.gd -OutputDirectory var/ci/drain-final
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames inventory_command_drain_boundaries_test.gd -OutputDirectory var/ci/drain-final-fixture
```

Exact-head Linux/Windows CI results are reported with draft PR68; local Windows evidence does not establish Linux execution. The existing CI automatically discovers the new fixture on both operating systems. PHP is untouched and local PHP suites were not rerun. Graphical/controller/VR, live services, production networking, deployed performance, game exports/releases and public media uploads remain outside acceptance. No port reservation is needed for these fixtures. The isolated worktree stays attached for review; no merge or deployment is authorized by this milestone.
