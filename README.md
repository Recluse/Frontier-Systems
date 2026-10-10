# Frontier Systems

Frontier Systems is a cooperative, persistent engineering simulation set across Moon and Mars colonies, spacecraft, and orbital infrastructure. First-party code and created assets are licensed under MIT; see `THIRD_PARTY_NOTICES.md` before adding external content.

## Current foundation

**Cooperative first playable source prototype:** extraction into portable containers, transport, refining, physical plate crafting and recycling, with two authenticated clients and restart checkpoints. [Run it](docs/development/first-playable-running.md), review [acceptance evidence](docs/development/first-playable-acceptance.md), or use the [agent handoff](docs/development/FIRST_PLAYABLE_HANDOFF.md). This is a development build, not a packaged Steam release.

- Optional OpenXR PC VR preview with a Quest 3 testing guide. Launch `tools/launch-client.ps1 -VR` for Mobile/Vulkan XR, or omit `-VR` for desktop. See [optional VR setup and current limitations](docs/development/quest-3-vr-testing.md).

- Godot 4.7 Forward+ project with a client/headless bootstrap, server-authoritative fixed-tick runner, component composition, bounded async continuations, and bounded TTL/LRU caching.
- One headless Godot world-host build is intended to support both community-hosted and official worlds; local headless startup is the first development mode.
- GodotSteam GDExtension 4.23.1 installed under `addons/godotsteam/` and wrapped by `GodotSteamProvider`.
- Local airlock prototype with an ideal-gas pressure solver, tick-sampled pressure sensors, door/valve interlocks, fixed-tick commands, and staged electrical/mechanical/combined access bypass jobs.
- Local [mining-to-crafting gameplay loop](docs/architecture/production-gameplay-loop.md): finite deposits, refining, chemical processing and dispensing, plate printing, wall construction/deconstruction and recycling. Shared materials, energy and reserved batches persist in world snapshots.
- Manual crowbar commands can move an unlocked, mechanically usable door without controller power; locks, tools, force limits, and airlock interlocks still apply.
- Versioned world snapshots with pressure and access-control restore contracts for the future PHP persistence boundary.
- Actor-free command-intent schema and server-local authenticated command context boundary; the local prototype uses a development-only principal.
- PSR-4 PHP foundation and world-contracts packages, including a promise-based snapshot compare-and-swap persistence interface, plus a separate ReactPHP control-plane application.
- Command, persistence, and PDA design contracts are documented under [`docs/design`](docs/design) and share versioned JSON schemas under [`docs/schema`](docs/schema).
- The first access-bypass runtime slice is documented in [`access-control-and-bypass.md`](docs/design/access-control-and-bypass.md); it uses synthetic debug tools until authoritative player inventory and equipment are implemented.
- Modular machine control definitions, slot/port compatibility checks, and a trusted-handler catalog are implemented under `src/core/control/`. The [modular controls contract](docs/design/modular-controls-and-signals.md) specifies wired/radio pulses, machine actions, alarms, and messages; live installations and signal routing remain future work.
- Control-board replacement plans retain fitted modules and check explicit relocations. Physical mounting and cable attachment allow dormant or unusual configurations; operability is diagnosed separately. The expanded door-board/igniter example is definition data, with construction execution and combustion still future work.
- Foundation architecture and known limitations are documented in [`docs/architecture/foundations.md`](docs/architecture/foundations.md).
- Non-fatal component integrity, gas/liquid pressure, docking, EVA, and remote-control invariants are documented in [`docs/design/survival-pressure-and-recovery.md`](docs/design/survival-pressure-and-recovery.md).

The cooperative client also provides a [player inventory and tool panel](docs/architecture/player-inventory-ui.md), nested portable storage, equipment/hand controls and a 1920×1080 default window. New worlds seed handheld extractors; existing worlds keep their saved inventory.

The next [equipment fabrication milestone](docs/development/equipment-fabrication-milestone.md) adds blueprint-driven canister/extractor assembly and salvage, with separate construction/contents mass and restart persistence.

## PHP control plane

Requirements: PHP 8.3+ and Composer 2.

```powershell
Set-Location 'services/control-plane'
composer install
$env:FRONTIER_CONTROL_PLANE_ADDRESS = '127.0.0.1:8080'
php .\bin\control-plane.php
```

The service exposes a liveness endpoint at `GET /health` and a small runtime snapshot at `GET /metrics`. The project-owned `RememberingCache` helper returns ReactPHP promises, coalesces same-key misses, and uses a React cache implementation such as the bounded in-memory LRU `ArrayCache`.

Composer scripts are available from `services/control-plane/`:

```powershell
composer cs
composer cs-check
composer unit
composer docs
composer phpacker
```

`composer unit` runs the initial PHPUnit suite; add focused cases with each implemented domain system. `composer phpacker` first builds a production-only PHAR, then asks PHPacker to produce standalone binaries for its supported platforms.

## Git workflow and continuous integration

`dev-master` is the primary integration branch. Optional feature branches should target it through pull requests. GitHub Actions checks PHP on PHP 8.3 and 8.5 on Ubuntu and PHP 8.3 on Windows, enforces the Windows runtime API policy, then imports the Godot 4.7 project headlessly on Ubuntu and Windows. See [CONTRIBUTING.md](CONTRIBUTING.md) for local commands and the GitHub branch protection settings needed to require those checks before merge.

## GodotSteam

The extension source and platform binaries are pinned in `addons/godotsteam/` to release 4.23.1. Run the project with Godot 4.7 and Steam installed for Steam API initialization. Use `GodotSteamProvider.initialize(app_id)` during startup; do not initialize Steam or call integrations from a simulation tick. Exported builds should use Godot's standard export templates for the GDExtension.

The `steamInitEx` call is wrapped by a project-owned adapter so gameplay code can later target a fake provider in offline development. Do not put a real app ID or secrets in source control.
