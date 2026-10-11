# Mining, chemicals and crafting runtime

## Playable local loop

The desktop client exposes **Extract, store, refine and recycle** inside the existing inventory overlay. This follows the [community-selected first playable milestone](../development/first-playable-milestone.md) and the [environmental extraction route](environmental-extraction.md). No external services or proprietary art are required. The procedural habitat shows deposit depletion and constructed wall segments.

1. Select an owned canister and 1000 g transfer mass. Extract from the iron ore source twice, then unload both kilograms into workstation storage. Extraction requires source reach; unloading requires workstation reach.
2. Run `refine.iron` twice. Each kilogram of ore yields 600 g iron and 400 g retained tailings.
3. Run `craft.plate`, consuming 1 kg iron. Build a wall segment with the printed plate.
4. Deconstruct the wall to recover the plate. Run `salvage.plate` to recover its iron and print again.
5. Extract ice into an empty canister, transport/unload it and run `refine.ice` to produce water. Dispense a selected mass into the shared vessel, then return it to storage.
6. Extract regolith into an empty canister, unload it and run `refine.regolith` to separate salts, silicate and retained tailings. Combine 900 g water and 100 g salts with `chemical.nutrients`.
7. Alternatively run `chemical.electrolysis` to separate water into stored hydrogen and oxygen. Dispense small gas quantities while respecting vessel pressure.

The loop is executable runtime code, with command buttons and durable snapshot records. It is a finite shared workstation prototype: the bulk depot and vessel belong to production, separate from wearable/handheld inventory. Payload contents now attach to real inventory canisters through the [portable resource bridge](portable-resource-carriers.md); the same mass is never also minted as duplicate item stacks. Legacy wall segments remain aggregate blueprint mass records. [Physical floor panels](../development/spatial-wall-milestone.md) add owned-plate placement/removal, static collision and server movement validation, with production v7 persistence. Neither path forms atmospheric enclosures; pressure topology remains future work.

## Ownership and commands

`ProductionSimulationSystem` owns the deposit masses, bulk depot, shared vessel contents, constructed wall mass, finite battery energy, station power flags, one reserved batch and at most 64 request receipts. It runs after health and inventory, at priority 300. The catalog is read once during startup; ticks never perform file or service I/O.

`ProductionDevelopmentCommand` uses the existing fixed-tick command queue. World and region scope are checked before ingress. Inventory resolves the server-bound actor, requires a conscious body, an available unreserved hand and logical reach within 1.5 m of the fixture workstation at `[0,0,0]` mm. Mounted drill and station tools provide processing capabilities; there is no handheld mining tool check. A machine batch continues autonomously if its operator subsequently moves away or becomes unconscious.

An operation commits one whole candidate state or rejects without mutation. The client supplies IDs and quantities, never outputs/yields or material compositions. Commands require the current production revision. Concurrent actors compete on that revision; a stale command fails. Identical retained requests return their receipt without repeating the operation; changed intent under the same retained ID rejects. Evicted old requests remain subject to current revision validation.

Closed operations:

| Operation | Fields in addition to `expected_revision` | Effect |
| --- | --- | --- |
| `extract` | `deposit_id`, `carrier_id`, `amount_milligrams` | Transfer finite environmental matter directly into an owned canister at source reach |
| `mine` | `deposit_id` | Reserve 1 kg from a finite deposit and start mounted drilling |
| `process` | `recipe_id` | Reserve exact recipe inputs and start refining, chemistry, printing or recycling |
| `cancel` | none | Recover reserved original inputs; spent energy remains spent |
| `dispense` / `return` | `material`, `amount_milligrams` | Transfer chemical mass between depot and vessel |
| `load_cargo` / `unload_cargo` | `carrier_id`, `material`, `amount_milligrams` | Transfer resource mass to/from an owned physical canister |
| `build` / `deconstruct` | none | Transfer one 1 kg plate to/from a wall segment |
| `power` | `station`, `enabled` | Change a registered station's power flag |

Every payload has exact fields; unknown operations, extra fields, negative/fractional quantities, missing feedstock, exhausted deposits, overcapacity storage and unpowered stations reject. Read-only workstation observations still require identity and reach, but do not grant voluntary actions to an unconscious body.

## Material and energy conservation

All mass is integer milligrams. The default closed fixture starts with 10 kg iron ore, 5 kg ice and 10 kg regolith, with empty storage, vessel and structures. Mining transfers matter from the deposit into a reserved batch, then into bulk storage. Processing reserves feedstock, then atomically replaces it with equal total output mass. Waste remains explicit tailings; it never vanishes. Cancellation recovers input chemistry, not unearned outputs.

Snapshots validate that deposits + bulk stock + vessel + constructed wall mass + reserved batch mass + portable payload mass total exactly the initial 25 kg. A 100 kg bulk capacity includes reserved future outputs, and a 2 kg vessel capacity bounds all contained matter. Receivers are checked before transfer. The vessel may contain several registered chemicals, each retained separately; dispensing cannot create matter or change its identity.

The fixture battery starts with 100,000 J. Batch energy is charged atomically at acceptance; insufficient energy rejects. Turning off the active station pauses progress without losing its reserved materials. Power-on resumes it. Switching power on does not refill the battery. Power generation and real electrical network integration are future work. Dispensing and construction currently use powered fixtures without a quantified energy debit.

## Vessel pressure

The shared sealed vessel has 2 L internal volume, a fixed 293.15 K temperature and a 1000 kPa absolute pressure limit. Liquid displacement uses prototype water-like density; hydrogen and oxygen use ideal-gas molar quantities. Gas pressure derives from mass and remaining headspace; it is not separately saved. A transfer exceeding capacity or pressure rejects before commit. For example, 100 g oxygen exceeds this vessel's pressure limit; choose a smaller quantity. Filled liquids leave less gas headspace.

This vessel is not a breathing tank and has no atmospheric connection, rupture, leaks, gas reactions, explosive ignition, phase changes or heat exchange. Bulk output gas is stored as abstract sealed stock. Electrolysis and nutrient recipes are mass-balanced gameplay approximations, not a full stoichiometric, thermodynamic or medical chemistry simulation. No SS13 chemistry code or content was copied.

## Cadence, persistence and bounds

The fixed runner advances one active batch by one tick when powered. Recipe durations range from 60 to 180 ticks in the defaults. At 60 Hz these are 1–3 seconds; 72/90 Hz currently shorten wall-clock durations. Saved timebase must match the process, and mid-session rate changes reject advancement/commands. Explicit retuning or migration is required for production rate changes.

The v2 snapshot adds portable cargo records to the original v1 canonical quantities, power, reserved input/output identities, remaining ticks and retained request receipts. Snapshot restore validates exact registries, quantity bounds, conserved total mass, pressure, recipe correspondence, ordered receipt revisions/ticks and supported timebase. A SHA-256 catalog fingerprint prevents silently loading a batch against edited recipe definitions. The runner validates all systems before restoring any.

Legacy worlds without `systems.production` receive the initial finite fixture at their saved tick. This is a one-time schema migration, not a respawn operation; new snapshots include depleted resources. A malformed present production record fails rather than resetting. The cooperative scene now adds authenticated sessions and worker-thread checkpoints; see [adapter contracts](first-playable-adapters.md). Database/journal storage remains future work.

Work is bounded by 32 material types, 16 deposits, 32 recipes, seven stations, one batch and 64 retained receipts. Profiling exposes active batches, stored/vessel mass, remaining energy and receipt count. Desktop observations refresh at 10 Hz and hold detached values only. The HUD clears when the world closes; themes and section visibility continue to work.

## Verification state and remaining integration

Windows cooperative and graphical route checks now pass. See [acceptance evidence](../development/first-playable-acceptance.md) for coverage and remaining unverified chemistry cases.

Remaining broader gameplay includes carrier crafting and detailed equipment damage, freeform terrain excavation/fill, spatial blueprint placement, power generation/network integration, chemistry effects on living bodies, atmospheric pipe connections, arbitrary modular construction and wider multiplayer distribution. The first playable supplies the bounded cooperative workstation loop; those broader systems remain staged.


Command revisions advance on accepted commands and batch output commits. Countdown-only progress changes last_tick and remaining_ticks without changing state_revision, so a remote pause/cancel intent can use the latest published transaction revision. Completion still invalidates competing commands. Cancellation returns reserved input mass; spent energy is not refunded.
