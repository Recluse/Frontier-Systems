# Physical tool parts, replacement and upgrades

## Status

Completed for the bounded cooperative source prototype on 2026-10-10. Players can manufacture independent tool parts, fit or replace them in manufactured equipment, detach them into inventory, store/share them and recycle their materials. Part identities, material grades, condition and fractional wear survive mounting changes and checkpoints.

The default editable equipment is the manufactured extractor. Starter extractors/crowbars retain their original shell provenance and maintenance support; converting those shells to editable physical parts requires a separate migration. Sustained extraction, actual automated extraction/scanner behavior and additional manufactured tool profiles remain next steps.

## Player instructions

Use the [cooperative launcher](first-playable-running.md).

1. Extract ore into a canister, unload it at the workstation and refine it. Manufacture an extractor (1.5 kg iron) using Workstation.
2. In Inventory, scroll to **Tool parts**. Choose a blueprint and **Manufacture selected part**. Parts appear as loose inventory items and can use existing backpack/tray controls.
3. Select the manufactured extractor in the inventory list. Select a mount and an owned loose part, then **Fit loose part in selected tool mount**. Any previous part returns to your body's loose inventory with its condition unchanged.
4. **Detach selected tool mount into inventory** leaves the mount empty. Missing parts remove their dependent capabilities; remaining parts persist.
5. A controller fits the module mount and grants automation/scanning capabilities when the drive/frame prerequisites work. These capabilities are hooks for later gameplay; fitting one does not yet run an AI, scan resources or start unattended extraction.
6. Upgrade a head's grade by making and fitting another head. Ceramic heads use 900 g silicate and have zero routine wear; obtain silicate by refining regolith. Physical damage and repair still apply.
7. Select a loose part and **Recycle selected loose part** to return its raw material. Whole-tool salvage returns the currently installed materials, including upgrades. Starter equipment cannot enter this manufactured-material pool.

Available part blueprints: 300 g iron frame, 900 g basic/space iron or ceramic head, 300 g iron drive, 100 g controller and 800 g prying head. Fabrication costs 300–1200 J depending on blueprint; recycling costs 100 J. Fitting/detaching costs 100 J at the powered workstation. Repairs retain their component-specific energy policy. These are tunable game defaults.

A mechanically compatible prying head can fit the extractor's head mount even though extraction becomes unavailable. Shape compatibility and functional capability are separate checks. Detachment/replacement outputs currently go to the body's loose inventory; make room first. Fixed inventory volume is a conservative generic 1 L for loose parts, pending per-definition volume policy.

## Ownership and transaction contract

ToolSimulationSystem retains the canonical part/assembly ledger. Installed parts have exactly one mount; loose parts have exactly one physical `item.tool-part.fabricated` item using the same stable ID. Their zero-base-mass inventory definition takes its real mass from production's material record. No mounted part also appears as a loose item.

Trusted part blueprints specify component definition, material grade and energy costs. Catalog component mass/material determines the bill of materials; clients cannot submit part state, manufacture free components, overwrite a grade in place or claim another player's part. Commands require current production/tool revisions and workstation reach, consciousness, a usable hand, power, energy, stock and inventory capacity.

Production prepares a candidate stock/energy record, component ledger and sequential physical inventory changes. Replacement removes the incoming loose item before adding the displaced part, then validates the final associations and capacity. All owners commit synchronously at one tick without waiting for services. Any rejected preparation leaves material, energy, part condition and mounting unchanged. Retained command retries return the existing completion receipt.

Production snapshot/observation **v4** adds `loose_parts` (physical ID → material quantities). Manufactured modular structures retain their pinned blueprint identity/fingerprint while their installed material bill changes. The trusted inventory binding selects which blueprints are modular; ordinary canister structure remains fixed. Exact component-stock cross-validation and the closed 25 kg fixture budget prevent forged structural or loose-part material. V1–v3 records migrate with an empty loose-part map and their existing structure. Tool snapshot/ledger v1 shapes remain compatible; their world cross-validation now permits physically owned loose parts.

A fully stripped manufactured tool retains an empty assembly/blueprint identity, with zero installed matter and no extraction capability. Restore does not regenerate default parts for this existing assembly. The same parts can reconstruct it later.

Scoped tool observation **v2** includes mounts, owned loose parts and trusted blueprint quotes. The client validates bounded shapes, IDs, conditions, unique mounted/loose ownership and action consistency. Inventory transfer automatically changes visibility through existing ownership rules. Profiling now includes physical tool part counts. Default limits remain 512 domain parts, 64 assemblies, 16 mounts; production permits at most 128 loose part records and 32 fabricated equipment structures.

## Acceptance evidence

Windows Godot 4.7.2 checks passed:

- `tool_parts_runtime_test.gd`: manufacture, worn-part replacement, unchanged carried mass, retained retry, incompatible mount and starter-provenance rejection, controller capabilities, compatible nonfunctional prying head, missing mounts, ceramic material upgrade, private observation/ownership, restart, forged balanced-mass rejection, full-inventory and power rollback, complete strip/rebuild and mixed-material recycling.
- Expanded `first_playable_acceptance.gd`: real authenticated clients, private loose-part observation, unauthorized recycle rejection, tray transfer, disk checkpoint restore and recycling by the new owner, alongside the earlier production/restart route.
- Graphical `first_playable_client_render_check.gd -- --tool-parts`: collect/refine resources, manufacture parts, replace the extractor head and fit a controller through inventory controls. The old head remains physically present. Forward+/D3D12, 1920×1080. [Screenshot](../../reports/tool-parts/client.png).
- Existing Godot CI script set, equipment fabrication, domain component and live maintenance checks passed locally. JSON/schema parsing and project import passed. Windows/Ubuntu CI includes the new runtime check.

This evidence does not establish human mouse/controller usability, Quest 3 interaction, stress performance, public identity/movement authority or standalone exports. Latest remote CI status must be checked for the published commit rather than inferred from these local results.

## Next milestone

Sustained extraction reservations: bind a tool, active hand, reachable source and physical carrier; reserve a bounded work batch; interrupt or pause safely when ownership, capabilities, power, carrier capacity, position or consciousness changes; apply wear only to completed cycles; define cancel/restart/retry recovery. Keep requests and service responses outside canonical tick mutation. Terrain excavation follows this resource/equipment loop.
