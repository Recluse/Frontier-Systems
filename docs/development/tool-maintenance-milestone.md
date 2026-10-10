# Live tool condition and maintenance milestone

## Status

Completed for the bounded cooperative source build on 2026-10-10. Starter and manufactured extractors and starter crowbars now have canonical component assemblies. Inventory inspection shows fitted components, material grades, precise condition and available actions. An owned component can be maintained at the powered workstation using finite station energy.

This slice completes live condition/maintenance integration. Physical detached-part inventory, player replacement/upgrades, sustained extraction reservations and handheld door interaction remain next steps.

## Play it

Use the existing [cooperative launcher](first-playable-running.md). In Inventory, select the extractor in your backpack, equip it in a free hand and select that hand. Approach an iron, ice or regolith source with a resource canister and extract 1 kg. Inspect the extractor: its space-grade head loses 1 ppm per successful cycle; its drive accumulates fractional wear. Return to the workstation, select its head and use **Maintain selected component at workstation**. Even tiny maintenance costs energy; an undamaged part rejects without payment.

The legacy inventory shell condition is retained for migration, but fitted components determine tool capabilities. Broken parts persist and can be maintained; no repair grants matter or deletes damage records. Crowbar component condition is registered but the legacy door lab still has its separate synthetic command adapter.

## Architecture and persistence

- ToolSimulationSystem (`tools`, priority 250) owns the component ledger; inventory owns physical identities; production owns structural material and station energy. Tick processing only advances the tool owner's tick, with no passive wear.
- `data/tools/inventory-bindings.v2.json` extends the preserved v1 catalog with fabricated crowbars and shovels and maps trusted inventory definitions to default assemblies. Extractors partition 1.5 kg into 300 g frame, 900 g head and 300 g drive. Starter crowbars partition their existing 2 kg shell. Components describe the same matter as the structural/shell record; they are never an additional carried mass.
- Completed `tool_extract` prepares one work cycle. Capacity/resource rejection leaves condition unchanged. Retained successful retries return their receipt without repeated wear. Work that would disable a required component is rejected before extraction commits.
- `repair_tool_component` requires production and tool revisions, an owned part, bounded amount, voluntary workstation capability, power and sufficient energy. Energy and prepared condition commit synchronously with the production receipt; no asynchronous mutation is involved.
- Fabrication/salvage prepares tool associations along with inventory and production candidates. Failed capacity checks cannot leak component records. Whole-tool salvage returns existing construction matter; it removes its associated parts rather than minting detached inventory.
- New world snapshots include tool-system v1, pinning both bindings and component catalog. Legacy snapshots missing this owner derive parts from saved physical inventory condition (permille × 1000), preserving broken state and existing matter. Invalid modern records reject before restore. Detached parts are rejected in live state until they have their own physical inventory/provenance contract.
- Host observations expose only the authenticated player's tools, including nested inventory. ToolObservationValidation bounds and validates this view before UI presentation. State revision refreshes inspection without a per-frame canonical mutation. Profiling exposes assembly/part counts.

Schemas cover tool-system v1, tool-observation v1, inventory bindings v1 and the expanded production intent. Existing production snapshot v3 is unchanged.

## Acceptance evidence

Windows Godot 4.7.2 editor import passed. `tool_runtime_test.gd` passed for scoped observations, invalid client condition, completed-work wear/fractional remainder, retained retries, idle ticks, workstation reach, other-owner rejection, stale revision, power, paid repairs, disabled-tool recovery, insufficient-energy rollback, restart validation and broken legacy migration. Existing domain, equipment fabrication and cooperative restart tests passed. The full existing Godot CI script set passed after correcting one pre-inventory legacy fixture to also omit the newer tool owner. The graphical equipment route passed using Forward+/D3D12 at 1920×1080 with the added tool observation, frame/head/drive inspection and action display.

CI now runs the live tool check on Windows and Ubuntu. These local results do not establish a new remote CI run, human maintenance usability, controller/VR operation, sustained extraction or exported release performance.

## Next implementation slice

Make component parts physical inventory entities with independently conserved material records and blueprint manufacturing/recycling. Prepare detach, fit and replace transactions across all owners, retaining removed parts. Support changed material grades/functions without silently rewriting pinned definitions or duplicating structural mass. Then add sustained extraction with interruption/restart recovery and finally terrain excavation.


## Follow-up

The [physical parts milestone](tool-parts-milestone.md) now adds independent manufactured parts, retained detach/replacement, material/module upgrades and recycling. Production v4 and tool observation v2 supersede the live versions described above; these notes retain the original milestone's scope and evidence.

The [construction coverage milestone](scratch-construction-milestone.md) adds hand assembly and handle/lever-shaft fabrication designs. Old v1 tool snapshot fingerprints migrate under unchanged legacy bindings.
