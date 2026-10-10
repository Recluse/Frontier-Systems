# Finite medical treatment planning

## Implemented boundary

Three independent components provide a pure treatment plan: `MedicalSupplyState`, `MedicalTreatmentDefinition` and `MedicalTreatmentPolicy`. They introduce no simulation system, network endpoint, UI healing button or second inventory. The current world remains the sole owner of live injuries; these planners never mutate it.

Supply state identifies a physical item, trusted definition, revision, last changed tick and 0–1000 remaining charges. Inventory continues to own that item's location and accessibility. An exhausted supply remains a stable object suitable for eventual refill, salvage or disposal; reaching zero charges does not delete it. No refill or fabrication API is implemented.

Trusted treatment definitions specify a localized injury kind, fixed maximum healing and positive charge cost. The two independently authored prototype dressings each remove up to 200 severity units of blunt or burn injury for one charge. The supply fixture starts with four charges. These fixtures are planning examples, not spawned inventory items or live gameplay stock.

## Inputs and authorization

An exact v1 intent supplies request ID, target body ID, physical supply ID, part ID and expected injury/supply revisions. It cannot supply healing strength, charge cost, actor identity or authorization flags.

The server adapter supplies an exact observation with `schema_version`, `actor_body_id`, `target_body_id`, `supply_id`, `tick_number`, `actor_can_act`, `manipulator_available`, `reachable`, `target_accessible`, `target_resisting` and `supply_accessible`. Capabilities are booleans. The adapter must resolve authenticated actor identity, current consciousness, available manipulators, inventory ownership/access, target exposure, contact and resistance at the authoritative commit tick. Never accept this observation from a player, script or LLM.

Both self-treatment and assistance are possible when those observations allow them. An unconscious target can be helped; an unconscious actor cannot treat. Current target resistance blocks treatment. Incapacity does not imply that a body is reachable or exposed. There is no medical skill, species catalog or anatomical access override yet.

## Pure result and conservation

`MedicalTreatmentPolicy.plan(injuries, supply, definition, request, observation)` validates identities, revisions, supported anatomy and capabilities. It returns detached injury and supply before/after candidates, the actual clamped healing amount, consumed charges, actor/request identity, definition revision and commit tick. Input objects remain unchanged on success and failure.

Treatment with no matching injury rejects without producing a consumption plan. Insufficient charges, stale revisions, mismatched definitions and unavailable actors or targets reject. A partially injured part receives only its remaining damage worth of healing, but consumes the full application cost. The prototype treats localized blunt/burn injuries only; systemic oxygen injury requires future chemistry or physiology, and cannot be healed with a dressing.

Each candidate increments its component revision once and records the same fresh positive tick. As with the injury foundation, one mutation per component per tick is supported. Planning is bounded constant work over six parts; no I/O, callbacks, caches, promises or profiling history occur here. This pure layer owns no tick scheduler or persistence lifecycle.

## Required runtime integration

Before exposing treatment to players, the inventory/health transaction owner must:

1. Register charge components against real ledger item IDs; persist them alongside the physical items and validate one-to-one associations on restore. Definitions must be resolved from a pinned trusted catalog. Do not create a private HUD stockpile.
2. Authenticate actor/body binding and world/region scope. Derive fresh contact, equipment, target access and resistance observations at the fixed tick; reserve required manipulators for any timed action.
3. Build and revalidate both plans without changing either owner. Validate health cause capacity and pending mutations before committing.
4. Commit the injury and supply candidates together with a bounded, persisted request receipt. Publish success only after both commit. Never debit inventory and then queue healing separately: a later failure would lose supplies without healing. Never commit healing before its debit.
5. Return an identical retained retry receipt without spending another charge or healing again. Reject changed intent under a retained request ID. Restore both component revisions and receipts atomically; stale requests must not regain access after restart.
6. Schedule consciousness assessment from the committed injury state. Healing a head injury does not erase independent chemical suppression or bypass recovery hysteresis.

The existing `queue_injury_change(..., "heal", ...)` remains a trusted internal foundation API. A player treatment command must not call it directly until the paired transaction above exists. No world snapshot version changes in this step.

## Acceptance scenarios for integration

Cover full/partial injury healing, healthy-part rejection, exhausted supplies, wrong-kind treatment, foreign body/supply identities, inaccessible storage, locked/gripped manipulators, out-of-reach or resisting targets, unconscious actors, unconscious patients, stale revisions/ticks, JSON numeric normalization, detached candidates, failure between preparation and commit, duplicate retries and restart continuation. These are documented future checks; no treatment tests were added or run in this step.

Schemas: [supply](../schema/medical-supply-state-v1.schema.json), [definition](../schema/medical-treatment-definition-v1.schema.json), [intent](../schema/medical-treatment-intent-v1.schema.json).
