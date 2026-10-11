# Inventory fixed-tick runtime

Current extension: [inventory/grip arbitration](inventory-grip-runtime.md) adds queued grip intents, exclusive hand checks and paused grip recovery in inventory snapshot v4. Spatial records use 3D integer positions; see [inventory spatial state](inventory-spatial-state.md).

Current payload extension: [portable terrain material](../development/terrain-portable-milestone.md) composes disjoint Production and Terrain payloads through one catalog provider, including prospective factory checks and candidate-world recovery. Physical ledger records and inventory snapshot v4 are unchanged.

## Canonical controller owner boundary

The [canonical controller epoch increment](../development/canonical-controller-epoch-milestone.md) adds trusted controller_candidate and commit_control_epoch methods plus an explicit InventoryRuntimeControllerOwner interface adapter. It derives principal/body/root agreement from validated canonical inventory candidates and commits lifecycle increments to the existing v4 body metadata. InventoryControllerAuthority uses that sole epoch; session tokens pin it for freshness. The component remains unintegrated with production admission, commands, receipts, jobs/views/grips invalidation and startup fencing. Existing development authorization and command behavior are unchanged.

## Runnable development slice

`InventorySimulationSystem` is now registered in `WorldRuntime` at tick priority 200, after machine controls. It owns the shared inventory coordinator, logical body/action records, bounded interaction jobs, volatile search views and limited command-outcome metadata. Startup loads trusted catalogs and the existing two-human shared fixture outside simulation ticks.

New prototype worlds initialize that fixture. `body.human-2` belongs to local principal `local-inventory-actor` at `[0,0,0]` mm; `body.human-1` belongs to `local-inventory-target` at `[1000,0,0]` mm. These are logical test bodies, independent of the local preview capsule unless the opt-in development pose bridge is enabled. This slice uses 3D distance and checks grip reservations on profile hands, while assuming open accessible paths. It has no authoritative collision, occlusion, closures, restraints, anatomy or network-session provider.

All fixture command authorization requires a debug build, `AuthenticatedCommandContext.Origin.DEVELOPMENT_LOCAL`, the `inventory.development` grant and a matching registered principal/body binding. Real authenticated-session origin is rejected even with that grant. This deliberately runnable local surface does not enable production player inventory access.

## Commands and ordering

`InventoryDevelopmentCommand` validates the local context through the world, then applies at the next fixed-tick boundary. The runner increments its tick, drains validated queued commands and runs systems; all queued movement/resistance precedes job progress and completion.

| Operation | Exact payload | Behavior |
| --- | --- | --- |
| `start` | `action`, `target_body_id`, `target_container_id`, `item_id`, `slot_id`, `destination_container_id`, `expected_revision` | Bind the actor from context, pin current epochs/revisions and create a timed job |
| `resist` | Empty object | Increment the actor body's action epoch and assert resistance during this tick |
| `move` | `x_millimetres` | Move the logical fixture body and increment its action epoch |
| `resume` | `job_id` | Initiating principal explicitly revalidates paused work |
| `cancel` | `job_id` | Initiating principal removes its unfinished work |
| `close_search` | `view_id` | Close this principal's live search view |
| `self` | Self operation, item/source/destination/slot IDs and expected revision | Derive the body from context and apply shared-owner hand/equipment/storage changes |

Search uses empty item/slot/destination strings; transfer/equipment requirements follow the existing job/intent contracts. For take/unequip, the selected target container is the source and destination is supplied by intent. For insert/equip, the source is resolved from the actor's actual item and the selected target container is the destination. No client/passivity/epoch fields are accepted.

The owner permits at most 32 unfinished jobs, and at most one per actor. Retained transfer request IDs cannot start another attempt. New work starts with zero progress at its command tick; the next tick supplies its first progress unit. Search/take defaults complete after 120/180 consecutive progress ticks. Resume also requires a subsequent fresh tick before adding progress.

Resistance/movement updates action epochs, so a brief action invalidates existing attempts even after its flag clears. Same-completion-tick resistance cancels before ownership changes. Completed transfers and receipts commit through the shared owner; completed searches create scoped views. Finished jobs are removed, so the next world checkpoint contains either unfinished work or completed ownership/receipts, never a second completion candidate. No tick waits for storage or external services.

The default simulation produces actual target action epochs, but its control epochs are static fixture values. Session/body control changes, item/tool activation and movement through real authoritative physics remain separate integrations.

## Observations and privacy

`local_observation(context)` returns only that principal's bounded job outcomes and the shared inventory revision. Outcomes contain job ID, success/error code and optional search view ID; they never cache item lists. `read_search(context, view_id)` resolves the view's exact actor/target and obtains fresh scoped contents under current guards. Wrong principals cannot read another actor's view.

Search expiry is pruned each fixed tick. Search views, local outcomes and presentation nodes are not persisted. Profiling hooks expose bounded numeric counts for bodies, jobs and active search views. Capacity policies and real network observer delivery remain future work.

## Snapshots and migration

The inventory system now emits [v3 spatial snapshots](inventory-spatial-state.md) containing the matching last tick, shared owner/ledger/receipts, logical body metadata, unfinished jobs/immutable intents and registered world storage locations. V1/v2 remain accepted with axis-to-vector and existing-tray migrations. The current schema is `docs/schema/inventory-system-state-v3.schema.json`.

Decode checks exact fields, collection limits, unique body/principal/root bindings, pinned catalogs, bounded coordinates/epochs, job ownership, target-container ancestry, job tick limits, action/intent agreement and future revision/epoch rejection. All system records validate before world restoration mutates any system. Restored jobs pause; the initiating local principal must resume. Original revisions/epochs remain pinned. Restored views/outcomes are empty.

World snapshots predating the inventory system migrate to an **empty** inventory owner and body/job collections at the restored tick. They do not copy the new-world fixture or spawn additional matter. A later explicit world-content migration would be needed to add bodies/items to those worlds.

Runtime recovery exposed JSON integer normalization versus fixture float representations in hosted-capacity equality. `InventoryItemCatalog.capacities_match()` now compares validated integer quantities semantically while preserving exact accepted-tag checks. This retains capacity-inflation rejection and allows normalized world JSON to restore against pinned fixture definitions.

## Verification and remaining work

Windows Godot 4.7.2 import, `inventory_runtime_test.gd`, existing shared-transfer/search tests and control-runtime recovery checks passed. Runtime checks exercise real command queue/system order, exact search timing, scoped principal reads, same-final-tick resistance, successful transfer/receipt checkpoint, production-origin rejection, paused JSON recovery/resume, atomic future-epoch rejection and legacy empty migration. Windows/Ubuntu CI includes the runtime script; Linux execution remains unverified locally.

The [local client panel](local-inventory-panel.md) now exercises this slice through queued commands and scoped observations. Next: self-inventory actions, real body/physical access adapters, production authenticated command/observer contracts, control-session epochs and durable persistence. Networking, survival equipment consequences, closed-container mechanics, cyborg module jobs and material reservations are not implemented by this slice.
