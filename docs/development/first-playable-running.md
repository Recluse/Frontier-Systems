# Run the cooperative first playable

This is a two-player Windows source build for the extraction/container/refining/recycling milestone. It uses a dedicated authoritative host, invite-bound persistent crew bodies and durable checkpoints. It is a playable development prototype, not a Steam store release.

## Local setup

Install Godot 4.7.2. The launcher defaults to the owner's installed console executable; supply `-GodotPath` if yours is elsewhere. Run these commands from the repository in three PowerShell windows:

```powershell
# Window 1: initialize private invite keys once, then start the persistent host.
./tools/launch-first-playable.ps1 -Mode Host -Initialize
```

```powershell
# Window 2: crew one, with the starting canister.
./tools/launch-first-playable.ps1 -Mode Client -Slot 1
```

```powershell
# Window 3: crew two. Collect the second canister from the storage tray.
./tools/launch-first-playable.ps1 -Mode Client -Slot 2
```

The host listens on loopback port 27840. Invite keys are generated with the operating system's cryptographic RNG, kept in ignored `config/local/first-playable/invites.json`, and are never printed or sent as command-line arguments. Each key controls one persistent crew body; only one connection per crew slot is permitted.

For a separate machine, expose the loopback host through an operator-configured TLS WebSocket reverse proxy and distribute only that player's invite in a private text file. The client verifies `wss://` certificates through Godot. Plain `ws://` is accepted by the client only for loopback hosts.

```powershellc
./tools/launch-first-playable.ps1 -Mode Client -InviteFile 'D:\Private\crew-invite.txt' -HostUrl 'wss://your-host.example'
```

The operator must provide the real hostname, DNS/certificate and proxy. No public listener, cloud service, purchase or account integration is silently configured by this project.

## Play the loop

1. Use **Overview** to find Iron ore and the workbench, then choose first/third person. Default controls: hold right mouse + WASD to walk/look; hold Left Alt to expose the UI cursor, or Escape to release capture. Rebind controls in Settings (F10 by default).
2. Approach Iron ore. Use the prominent collection-guide action twice to extract 1 kg each into your canister. Source double-click and the manual extraction button use the same validated command path.
3. Walk back to the workstation. The guide unloads the two kilograms, then runs two refining batches. Wait for each batch to finish.
4. Print a plate, collect it as a physical inventory item, recycle it, and print again. The guide reports seven completed stages.
5. Explore the manual recipe and container controls. Drop/pick up canisters through the nearby tray to share materials. Printed plates can also be placed on and collected from the tray.

The guide is session-only assistance, not a saved achievement. Depleted deposits, item locations, cargo, energy, retained receipts and in-progress batches are world state and do persist. No resource is created when a client reconnects.

## Save and restart

Checkpoints run every five seconds, with disk work on a worker rather than inside simulation ticks. **Save shared world now** waits for a disk confirmation from the host. Before intentionally stopping the host, request a save and wait for confirmation. Restart the host with the same keys and `-WorldName` to reload the world; clients reconnect with their own invite.

The default checkpoint directory is ignored `config/local/first-playable/worlds/main`. Two alternating, checksummed files preserve the last valid checkpoint if a slot write is interrupted. If both slots are invalid, startup fails rather than regenerating matter. Sudden termination may lose activity after the last completed checkpoint; these are checkpoints, not a per-command write-ahead log or a promise against hardware failure.

Use a different world name for a fresh development scenario without deleting the previous one:

```powershell
./tools/launch-first-playable.ps1 -Mode Host -WorldName demo2
```

Repeat the same name to continue that scenario. Stop the previous host before starting another on the same port. `-CheckOnly` prints launch configuration without generating keys, writing saves or starting Godot.

## Acceptance and checks

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --xr-mode off --path . --script res://tests/godot/first_playable_acceptance.gd
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --xr-mode off --path . --script res://tests/godot/first_playable_client_render_check.gd
```

The first exercises real WebSocket clients, authentication, scoped cargo, bounded replicated movement, a same-revision extraction race, unauthorized/overcapacity rejection, refinement, physical component recycling, a remote save confirmation, interrupted-slot fallback and reconnect to a restored host. The graphical check drives local character physics and the same guide callbacks through the full loop and writes `reports/first-playable/client.png`.

See [acceptance evidence](first-playable-acceptance.md) and [agent handoff](FIRST_PLAYABLE_HANDOFF.md). Linux is configured in CI; do not represent local Windows results as a completed Linux run.

## Current limits

- Two fixed invite-bound crew bodies, with no Steam account/lobby authentication yet.
- Server-approved movement has region and speed limits; detailed collision prediction/reconciliation and anti-cheat remain future work.
- Environmental extraction is discrete; sustained hand tools, terrain deformation and arbitrary component salvage follow later.
- Advanced survival, medicine, platform chat/voice, LLM automation, civilization progression and broad freeform construction remain outside this milestone.
- The legacy `main.tscn` remains the standalone development lab. Use this launcher or `scenes/first_playable.tscn` for the cooperative build.

## Player inventory and 1080p UI

The client now defaults to a 1920×1080 resizable window. Open the Inventory tab for backpacks/pouches, item inspection, equipment slots, two hands, storage transfers and nearby tray actions. Drag the sidebar divider to change its width. Workstation contains the collection guide and existing theme selector. See [player inventory and tools](../architecture/player-inventory-ui.md).

New worlds give both crew a backpack and handheld extractor. Existing saves retain their original inventories; start a new named world for the starter kit. Equip the extractor in the active hand, carry a canister and approach a source to use its extraction action. Cooperative crowbar door use remains pending.

## Controls preferences

Hold Left Alt for UI interaction. Releasing it resumes capture if look is still held. Settings exposes gameplay and core UI bindings, mouse sensitivity and reset; preferences persist locally. See [controls contract](../architecture/player-controls.md).

## Fabricate and salvage equipment

Workstation now lists canister/extractor blueprints with required iron and energy. Fabricate into inventory, use/store/share it, then salvage selected owned equipment and its contents at the workstation. See [equipment milestone instructions](equipment-fabrication-milestone.md). Existing saves migrate without resetting deposits or granting manufactured gear.

## Build portable resource machinery

Open the Construction tab to hand-build frames and modules, insert canisters, deploy generators, connect cables/routers, run powered processing and print replacement equipment. See [the construction walkthrough and prototype limits](modular-resource-machinery-milestone.md). Hold the configured UI cursor key (Left Alt by default) to interact. Existing inventory and settings remain in their original tabs.

The expanded printer also makes component-backed handheld extractors. For portable electrolysis select the 10 g recipe and fit separate water/hydrogen/oxygen canisters. Construction displays live machine telemetry; click deployed machines to select their controls. See the [verified workshop screenshot](../../reports/resource-workshop/workshop.png).
