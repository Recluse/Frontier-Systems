# Equipment fabrication and salvage milestone

## Status

**Completed as a cooperative Windows source milestone on 2026-10-10.** Players can fabricate portable canisters and resource extractors from refined iron, use/store/share them, restore them from checkpoints and salvage their construction materials. This extends the first playable resource loop; it is not a Steam/public release or the entire construction roadmap.

## Play it

Run the existing [cooperative launcher](first-playable-running.md). At the workstation:

1. Collect and unload iron ore; each 1 kg refining batch produces 0.6 kg iron plus 0.4 kg tailings.
2. In Workstation, scroll to Equipment fabrication. Choose the resource canister (1 kg iron, 1000 J) or extractor (1.5 kg iron, 1500 J).
3. Fabricate into your inventory. Inspect its construction materials and loaded mass in Inventory.
4. Put a canister in a backpack, fill it through the normal extraction/load controls, or drop it on the tray for another player.
5. Equip a fabricated extractor in the active hand and use the existing extraction action.
6. At the workstation, select owned fabricated equipment and salvage it. Shell materials and any canister contents return to depot stock; salvage costs 500 J.

Three ore refining batches provide enough iron for one extractor; two provide enough for a canister. Both items together require five batches. Capacities, power, energy, reach, consciousness, active-tool capabilities and current revisions remain server checks.

Starter equipment has no mined-material provenance and is not salvageable through this fabricated-equipment path. Existing worlds gain the new blueprint catalog without being granted manufactured items. Production v1/v2 snapshots migrate with empty structural records and preserved resources.

## Acceptance evidence

All listed checks returned exit 0 on Windows with Godot 4.7.2:

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/godot/equipment_fabrication_test.gd
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/godot/first_playable_acceptance.gd
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --xr-mode off --script tests/godot/first_playable_client_render_check.gd -- --equipment-fabrication
```

- Domain check: invalid blueprint materials, v1/v2 migration, missing ingredients, unknown blueprint, power rejection, inventory-capacity rollback, refined-material fabrication, exact loaded mass, retained retries, conflicting retry rejection, active-hand extractor use, restore, orphan/pinned-record rejection and equipped/loaded salvage.
- Real two-client check: private structural observations, loaded manufactured-canister transfer, unauthorized salvage rejection, worker checkpoint and restore with 1.1 kg shell+contents, salvage by the new owner, plus the existing contention/refinement/restart/replay route.
- Graphical check: complete original guide, use actual equipment controls to fabricate/load, move the new canister into a backpack and inspect its 1.1 kg mass and recoverable 1 kg structure. Passed with Forward+/D3D12 and Compatibility/OpenGL on RTX 3080 Ti at 1920×1080. [Screenshot](../../reports/equipment-fabrication/client.png).
- Six existing inventory/consciousness/control/health regression suites passed again.

CI includes the domain and cooperative checks on Windows/Ubuntu. Remote Linux execution, human usability, controller/Alt interactions, stress profiling and exports remain separate verification work.

## Delivered contracts

See [equipment fabrication architecture](../architecture/equipment-fabrication.md). Trusted bill-of-material blueprints, production snapshot/observation v3, typed factory/salvage intents, conserved structural payload and physical inventory association are codified under docs/schema. No third-party code or assets were imported.

## Next milestone

[Independent modular tool components](../architecture/modular-tool-components.md) are the next foundation: space-tier routine wear is low, with repair/replace/upgrade paths rather than disposable tools. Runtime component/inventory ownership and conserved structural migration must precede sustained extractor reservations and interruption recovery. Terrain excavation follows after the extraction/equipment route. Inventory child-container manufacturing (backpacks/pouches), arbitrary machine/vehicle assemblies, timed fabrication and production queues remain future extensions.


## Follow-up: live components

The [live tool condition and maintenance milestone](tool-maintenance-milestone.md) now supplies canonical fitted parts, saved condition, conservative completed-work wear and paid workstation maintenance. Detached physical part inventory and player replacement/upgrades remain next.
