# Other-body inventory interactions

## Required gameplay

Players can physically interact with another body's possessions: search worn containers, pickpocket items, insert items into accessible storage, place wearable equipment on a body and remove equipment. An attempt can progress while the target allows it through inaction; no affirmative approval popup is required by the default mechanics. Resistance or deliberate movement interrupts the attempt. Other bodies include player-controlled organic bodies, cyborgs and eligible remote devices; actual anatomy and fitted hardware govern available interactions.

This is physical gameplay authorization, separate from owning an item. The authoritative server may permit taking another body's item through a validated interaction even though the actor does not own it. Container IDs or idle status alone never authorize direct ledger mutations. Being nearby does not expose all possessions.

## Interaction sequence

1. The actor selects a reachable body, accessible slot/container and registered action. Bind actor principal/body and target body from canonical server records.
2. Validate manipulation capability, distance/occlusion, access path, selected item/slot, target availability and target movement/resistance state. Start a bounded fixed-tick work order with exact targets and source revisions.
3. Revalidate those conditions during progress. Target inaction means no relevant deliberate movement/resistance since the job started; record the target's action epoch so a brief resistance cannot be lost between samples. Do not infer inaction from network silence, a client checkbox, or missing packets.
4. At completion, revalidate inventory/equipment revisions and perform the specific operation atomically through the shared inventory coordinator. Cancel on conflicts rather than applying stale contents or item references.

Process resistance/movement intents before interaction completion in the same fixed tick. Reach loss, actor movement that breaks access, target disappearance, a locked/closed access path, missing capability, region/control change or conflicting inventory mutation cancels the attempt. Interrupted operations transfer no items and reveal no newly searched contents. Earlier completed operations remain real; cancellation does not reverse a prior completed theft.

An explicit Resist action should cancel ongoing attempts against that body. Movement also provides an escape where feasible. Restraint, incapacitation, unconsciousness, death and disconnected-body policy need explicit mechanics; do not grant remote searches of unloaded/logged-out inventories. A physically present incapacitated or dead body can remain searchable under its configured physical rules. Deliberate movement and server-computed reach are separate: involuntary drift may break reach without being a deliberate resistance input.

## Search, visibility and access paths

Searching one backpack yields a scoped observation of that backpack's accessible contents, not a recursive dump of every nested container, stored program or private PDA note. A nested container requires its own access/search operation. The actor's view should expire or be revoked when distance, resistance, contents revision or path accessibility changes. Keep observer knowledge separate from the canonical inventory snapshot.

Slot equipment and container closures define an access path. Closed, locked, sealed or obstructed storage can require opening, appropriate tools or a separate bypass mechanic. Inaction does not defeat locks, create a free hand, make an incompatible item wearable or supply access through a spacesuit. An equip attempt needs a free compatible slot; removing sealed life-support equipment can have genuine consequences through the existing equipment/survival rules.

Pickpocketing uses the same timed transfer path as taking an item. Detection, concealment, sensory cues and skill/tool modifiers may later influence gameplay, but must not bypass ownership conservation. The initial policy supplies no probabilistic stealth or guaranteed undetected theft. Server events should support target reactions without globally broadcasting hidden container contents.

Putting items into another body's backpack counts their nested mass toward its body and equipped-container limits. Removing equipment updates the target's slot bindings and affected capabilities together with the transfer. Both actor and target records must commit in one region-owned transaction; do not mutate independent `BodyInventoryState` copies of a shared ledger. Search observations, take/insert, equip/unequip and eventual item use are distinct permissions. Search does not authorize arbitrary activation of a bomb, program access or machinery operation.

## Implemented policy foundation

`BodyInventoryInteractionPolicy` validates a pinned v1 definition and assesses server-created observations for `search`, `take`, `insert`, `equip` and `unequip`. It rejects invalid distance/flags, missing capability/target, resistance, deliberate movement and inaccessible paths. A successful assessment returns the configured duration only; it neither advances a job nor reveals, equips or transfers an item.

The default fixture uses a 1,500 mm reach and 120/180-tick durations (2/3 seconds at the current 60 Hz). These are provisional tuning values. Definitions bound reach to 1–5,000 mm and durations to 1–3,600 ticks. The schema describes the policy; observation flags must come from the server, never a player/LLM payload claiming the target is idle.

[Timed job state](../architecture/body-inventory-interaction-jobs.md), the [shared coordinator](../architecture/shared-inventory-transactions.md) and [scoped search views](../architecture/scoped-inventory-searches.md) now run through a [local fixed-tick inventory slice](../architecture/inventory-runtime.md), with resistance/movement epochs and paused world recovery. Physical positions/access are synthetic development fixtures. Real body/access producers, production observer transport and stealth detection remain pending; there is no networked other-player inventory feature yet.

## Implementation tasks

1. **Implemented:** versioned policy, default configuration and pure precondition assessment.
2. Add server-owned body/action epochs, physical access paths and explicit resistance intents alongside inventory system registration.
3. **Partially implemented:** individual timed job progress, interruption and paused recovery with original epoch/revision checks. Add bounded collection ownership, command ordering, fresh-session providers and replay-safe completion receipts. Restored jobs must restart validation, never complete while bodies are unavailable.
4. **Partially implemented:** shared-ledger cross-body transfers/equipment, bounded receipts, timed completion and scoped direct-container search observations. Add observer transport, runtime ownership/checkpoints and job collection acknowledgement. Verify end-to-end duplicate pickup, stale theft and failed insertion under authenticated command flow.
5. Build target-body inventory UI with timers, cues and interruption feedback, then concealment/tool modifiers and species/chassis-specific behaviors.

Keep all operations at fixed ticks. External services and LLMs may propose intents through promises; they cannot attest target inaction or mutate inventories. Profile active jobs, cancellations, scoped views, command costs and transaction conflicts with bounded counters.

## Verification

Windows Godot 4.7.2 import and `body_inventory_interaction_policy_test.gd` passed locally. Checks cover every passive-target action, resistance/movement interruption, missing capability/target/path, reach bounds, invalid flags/distances/actions, nonzero durations and detached policy records. Windows/Ubuntu CI includes the script. Timed jobs, reaction ordering, actual searches/transfers and Linux execution remain unverified.
