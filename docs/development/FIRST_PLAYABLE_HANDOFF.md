# First playable agent handoff

## Status and owner decisions

The **cooperative first playable source prototype is implemented and verified on Windows**. The owner explicitly requires shared multiplayer and restart persistence. The priority is environmental extraction → portable container → transport/unload → refine → physical component → recycle/reuse. Do not reopen this scope question. See [acceptance evidence](first-playable-acceptance.md) and [launch instructions](first-playable-running.md).

This is a bounded development prototype, not the full long-term game or a Steam distribution release. Terrain excavation follows this loop. Civ13-informed civilization progression remains a later update.

## Environment

- Workspace: `D:\GitHub\Frontier Systems`; integration branch `dev-master`.
- Godot console: `D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.
- Read `AGENTS.md`, the milestone and adapter contract before editing authority boundaries.
- Preserve uncommitted work; commit/push only when requested. Inspect Git status before assuming ownership of changes.
- Windows runtime support is mandatory: no ReactPHP child processes, pcntl or POSIX orchestration. PHP packages remain PSR-4 and strict_types=1.
- First-party code and procedural assets are MIT. No SS13/Civ13 source/assets were imported. Reference authorization does not provide MIT redistribution rights; Baystation source must not be supplied to AI.

## Implementation map

- `src/core/production/`: finite 25 kg resource fixture, recipe catalog, energy, timed reservations, chemical vessel bounds, extraction/cargo, factory/recycler transactions and bounded retained receipts. Production owns all resource payload mass.
- `src/core/inventory/`: physical canisters/plates, owned graph, prospective payload-mass validation and derived load caches. Payload is counted once; stable item identity carries it through transfer/drop/pickup.
- `src/adapters/network/`: WebSocket host, server-minted authenticated contexts, scoped observations, read-only client production projection and asynchronous checkpoint intent. Socket writes happen outside fixed ticks. Two invite slots map to persistent crew bodies.
- `src/adapters/persistence/`: alternating checksummed checkpoints, startup restore and worker-thread disk I/O. Capture detached snapshots outside tick callbacks; workers never mutate canonical state.
- `src/app/first_playable_bootstrap.gd` and `scenes/first_playable.tscn`: dedicated host mode or graphical remote client. Legacy main.tscn is still the standalone laboratory.
- `src/presentation/production/`: source picking, readable recipe controls and seven-stage session guide. Batch-completion notifications are volatile presentation events, not durable rewards/provenance.
- `tools/launch-first-playable.ps1`: ignored cryptographic invite keys, named save directories and explicit source-scene launch.
- `data/production/catalog.v1.json`, production schemas and adapter documentation codify contracts. Existing inventory fixture is preserved; shared.production seeds carriers only in new worlds.

## Verified state

Real two-client acceptance passes: invite isolation, competing extraction, overcapacity/missing-input/power rejection, outage pause/cancellation, refining, physical component creation/recycling, physical-item restore, worker save confirmation, corrupt-slot recovery, active-batch restart and retained retry. The graphical route completes with local physics and authenticated guide commands using Forward+/D3D12 and Compatibility/OpenGL. Six focused inventory/health/control regression suites passed. Exact commands and limits are in acceptance evidence.

## Next development slices

1. Collect human two-player usability feedback and profile this active route before changing tick rates. Recipe ticks currently mean different wall-clock durations at 60/72/90 Hz; migrate/retune deliberately.
2. Expand durable-storage guarantees if required: transactional/journal persistence and identity binding. Current saves are periodic/manual checkpoints, not per-command durability.
3. Integrate existing GodotSteam identity/lobby adapter behind transport contracts before Steam distribution; preserve offline community-host mode.
4. Add sustained extraction/tools, carrier construction, terrain excavation and spatial blueprint transactions after the current loop.
5. Improve movement collision authority, prediction, reconnect UX and server load limits before wider/public play.
6. Run Linux CI, standalone export and optional Quest 3 checks when those environments are available. Do not substitute Windows evidence for them.

Platform chat/voice, DiscordPHP/TwitchPHP integration, full survival/medicine, LLM station automation, ships and civilization progression remain staged roadmap work. Existing foundations are not evidence that these complete features already ship.

## Known constraints

Two fixed invite bodies; host binds loopback and remote access needs a TLS proxy. Client collision is local; server enforces region/speed and command reach. Guide progress is session-only. Autosaves every five seconds; sudden termination can lose newer actions. Catalog fingerprint and tick timebase must match saved state. No standalone executable export or public deployment was made. No commit or push was performed for this milestone session.

Production state_revision represents command/material/configuration transactions and output completion; remaining_ticks changes alone do not advance it. Preserve this distinction so network controls can pause/cancel active batches without becoming stale every frame.

## Subsequent player UI implementation (2026-10-10)

PlayerInventoryPanel adds scoped storage browsing, equipment/hand controls, inspection, tray actions and active extractor use. The host opts into inventory observation v3, while local APIs retain v2 by default. New cooperative fixtures seed backpacks/extractors; loaded saves are untouched. The window defaults to 1920×1080 and uses a draggable tabbed sidebar and existing theme controller. See ../architecture/player-inventory-ui.md for contracts and limits. Only editor import/script parsing were performed for this update; prior gameplay acceptance evidence predates it. Next verification should cover both crews, nested mass/capacity/cycle rejection, wrong-hand/tool rejection, tool extraction, restart retention and resized layouts.

## Subsequent controls implementation (2026-10-10)

PlayerInputSettings (PlayerControls autoload) owns named InputMap defaults, bounded local preferences and cursor capture ownership. Left Alt temporarily exposes the cursor; settings and focus loss release navigation. PlayerControlsPanel supports keys/chords, mouse, controller button/axis rebinding, sensitivity and defaults. Cooperative shortcuts and core UI navigation are configurable. Desktop cameras and world selection no longer depend on hard-coded physical keys/buttons. See ../architecture/player-controls.md. Only editor import and script parsing were performed; interactive verification remains pending. OpenXR action-map settings are separate future work.

## Completed equipment fabrication milestone (2026-10-10)

Equipment fabrication/salvage is complete for the bounded cooperative source build: trusted EquipmentBlueprintCatalog, canister/extractor blueprints, atomic factory inventory preparation, production snapshot/observation v3 and separate structural mass. V1/v2 saves migrate without granting items. Manufactured carriers/tools can be nested, transferred, used, checkpointed and salvaged; starter equipment is not salvaged through this path. See equipment-fabrication-milestone.md and ../architecture/equipment-fabrication.md.

The domain test, expanded real two-client acceptance, graphical fabrication/load/backpack inspection route (Forward+ and Compatibility) and six regression suites passed on Windows. Prior UI/controls notes describe earlier verification scope; current evidence additionally covers the manufacturing UI and nesting, not interactive Alt/controller rebinding. Next implement sustained extraction reservations/tool wear, then terrain excavation. Public release, Linux execution evidence, Steam identity and exports remain pending. Commit ec3e320 is the previous baseline; these milestone changes remain uncommitted unless separately requested.

## Modular tool component foundation (2026-10-10)

Owner clarified that all tools need independently reusable, repairable, replaceable and upgradable parts; routine wear should be low for space-tier gear. src/core/tools now supplies ToolComponentCatalog, ToolPartState and ToolAssemblyLedger with material grades, mount interfaces, prerequisite capabilities, retained detached parts, integer/remainder wear, damage and maintenance plans. Default profiles cover extractor, shovel and crowbar; a controller enables automation/scanning only when required functions exist. See ../architecture/modular-tool-components.md and data/tools/catalog.v1.json.

This is an independent domain foundation, not a registered live simulation subsystem. Current tool items and world snapshots are unchanged. Only editor import/script parsing and JSON/diff checks were performed. Next wire an authenticated component owner, physical detached-part inventory and an atomic material-preserving migration of 1.5 kg extractor structure into its frame/head/drive. Do not duplicate aggregate structural mass or allow client repair plans to bypass energy/ownership checks. Then implement sustained extraction with wear applied per completed work cycle, not per tick.

## CI verification request (2026-10-10)

The owner requested committing/pushing the current changes and checking GitHub CI. tool_components_test.gd was added to the Windows/Ubuntu workflow and passes locally; it covers independent part replacement, mounted ownership, capability dependencies, low/fractional wear, damage/maintenance and restore. Earlier import-only notes describe the previous verification scope. Live component integration remains pending.

## GitHub publication and CI harness fixes (2026-10-10)

The gameplay and component changes were committed and pushed to origin/dev-master (equipment/components commit 4659c4d; earlier cooperative baseline ec3e320). Subsequent CI fixes select scalar executable paths, wait for Windows GUI Godot processes, assert oversized HTTP header rejection before transmitting a body, and initialize missing Godot class metadata for standalone profiling checks. The optional phpDocumentor PHAR distributor is disabled during Windows dependency installation because its GPG import fails there; signed documentation generation remains enabled on Linux, while Windows formatting/unit/PHAR checks remain enabled. Local full Godot workflow scripts, PHP formatting/unit/PHAR and profiling integration (including missing class cache and GUI executable) passed. See the GitHub CI workflow for current remote evidence. The modular tool domain remains separate from live inventory integration.
