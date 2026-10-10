# Modular tools and independent components

## Owner requirements

Every tool must be composed from separately identifiable components that can be maintained, replaced and upgraded. Materials/grades affect wear and capabilities without defining a separate subclass per shovel/head/alloy combination. Space-tier routine wear should be a minor maintenance concern; hostile damage and missing operating requirements still matter. A damaged tool remains recoverable.

## Implemented domain foundation

`src/core/tools/` provides ToolComponentCatalog, independent ToolPartState and ToolAssemblyLedger. These are reusable RefCounted domain types with exact versioned records and detached transaction plans. ToolSimulationSystem now registers their live inventory associations and component condition. See [live condition and maintenance](../development/tool-maintenance-milestone.md) for ownership, energy settlement, inspection, completed-work wear and migration. Physical part inventory and live replacement/upgrades are now implemented for manufactured extractors; see [physical parts milestone](../development/tool-parts-milestone.md). Sustained extraction remains pending.

The trusted `data/tools/catalog.v1.json` defines:

- Material grades with raw-material identity, tier and routine wear rate.
- Parts with mechanical mount interfaces, selectable material grades, mass, wear multiplier, operational threshold, maintenance energy and named functions with prerequisites.
- Assembly layouts with mount-compatible slots and actions requiring functions.

Definitions include frames, handles, multipurpose heads, prying heads, electric drives and an automation/scanning controller. Extractor, shovel and crowbar profiles demonstrate interchangeable heads and multiple functions. New profiles and parts use declarative definitions, not tool-name switches in behavior code. Function IDs describe capabilities; they never load scripts or authorize a player/LLM action.

## Standalone part identity and ownership

A part records stable ID, definition, material grade, integrity in parts per million and fractional wear remainder. Its identity and condition do not depend on the tool holding it. ToolPartState can validate, serialize, calculate material stock and prepare wear, damage or maintenance independently.

The ledger owns each part once. Assemblies reference part IDs in slots, with at most one mounting owner per part. Unmounted parts remain in the registry. Replacing a slot retains its former part as a detached record; removing a slot does not delete material. Aggregated material stock counts the parts registry rather than following each assembly, preventing duplicated mass. Physical inventory/world location and authenticated owner are the future containing system's responsibility; a loose domain record is not yet a collectible world item.

## Mounting and function resolution

Mounting checks intersecting physical interface IDs. It does not require a part to grant a useful function. A controller can physically mount on a shovel while remaining inactive without a drive. An alternate head can fit but disable excavation and enable prying instead.

Operational installed parts contribute function grants. Prerequisites resolve through a bounded monotonic dependency closure; cyclic grants cannot power themselves. Disabled parts remain fitted and retain material but do not supply functions. Missing functions are reported for each action, so removing an optional controller removes automation/scanning while leaving other capabilities available.

A drive's presence is a capability prerequisite, **not proof of live electrical supply**. The world owner must still check actual power, tools, targets, environment, consciousness, permissions and work reservations.

## Wear, damage and maintenance

Defaults are tunable game policy, not measured material science. Basic iron wears at 100 ppm per work cycle; space-grade iron at 1 ppm (100× less). The ceramic example has zero routine wear, while retaining external damage and repair requirements. Components multiply the rate; frames/controllers have zero routine wear, and drives accrue fractional wear. Maximum integrity is 1,000,000 ppm and default disabled threshold is 50,000 ppm.

Wear is integer arithmetic with a persisted remainder. Splitting a work batch cannot discard fractional wear. A work plan checks capability availability before and after monotonic wear and rejects a batch that would cross a required component's disabled threshold; the work owner can choose a smaller reservation. Damage can disable a part, including reducing it to zero, without deleting it.

Maintenance plans restore bounded integrity and quote energy. The owning system must debit that energy before adopting the proposed state. This models maintenance/recalibration with conserved structural matter; material-consuming patches, lost-material damage and fabrication-grade processing need explicit stock/byproduct transactions later. Repairs retain the fractional wear remainder. Replacement changes the part, and therefore its material grade/functions/condition, instead of magically upgrading an installed definition in place.

## Transaction and persistence boundary

Plans carry expected revision, validated next record and required energy. Adoption accepts only the next revision and revalidates the pinned catalog, parts and mounts. These APIs are trusted internal preparation hooks, **not client RPC endpoints or proof of authorization/payment**. The owner must settle energy, resource, inventory and assembly records atomically; no external callback may mutate them.

JSON schemas: tool-component-catalog-v1, tool-part-v1 and tool-assembly-ledger-v1. A ledger pins the normalized catalog fingerprint; definition changes require explicit migration. Bounds: 64 definitions per catalog registry, 512 parts, 64 assemblies, 16 slots per tool, 32 functions per part/action registry, 32 prerequisites per function and 10,000 cycles per usage plan. World snapshots now include tool-system v1; bindings and scoped observation schemas document the live integration.

## Required integration order

1. Add a canonical component owner and authenticated intent adapter with inventory ownership, workstation/tool reach and action capabilities.
2. Partition manufactured extractor material provenance into default frame/head/drive parts (300 g + 900 g + 300 g), preserving existing 1.5 kg mass and condition. Starter equipment must retain distinct provenance; do not credit unbudgeted starter matter into the closed mined-resource pool.
3. Store detached parts as actual inventory entities; construct/salvage them through blueprint and material transactions. Migrate aggregate structural records atomically rather than counting both aggregate and parts.
4. Expose inspect, detach, fit, repair and replacement in the player workbench. Use the same capability system for player tools, cyborg modules, remote instruments and machine tooling.
5. Build sustained extraction reservations around component capability/condition, active hand, target/carrier, power, interruption and restart rules. Apply routine wear to completed bounded work, not every simulation tick.
6. Connect automation capability to authorized station programs/agents; a fitted controller alone must not run untrusted code.

## Verification scope

Godot editor import, affected-script parsing, JSON syntax and diff whitespace checks were performed. The owner subsequently requested CI verification. tool_components_test.gd now passes locally and covers mounting, replacement without material loss, partial functionality, automation, space-tier and fractional wear, damage/maintenance, stale plans and JSON restore. Live component integration is now covered by tool_runtime_test.gd and the cooperative equipment route; see the maintenance milestone for exact evidence and limits. Before runtime integration, verify compatible/nonsensical mounts, duplicate ownership rejection, disabled capability loss, cycles, wear batching/remainders, repair energy settlement, replacement material conservation and restore. Existing equipment fabrication acceptance evidence does not verify this new domain model.
