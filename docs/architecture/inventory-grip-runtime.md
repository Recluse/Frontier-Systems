# Local inventory and grip runtime

## Fixed-tick integration

`InventorySimulationSystem` now composes `PhysicalGripOwner` in the existing authoritative tick/command path. Inventory and grip ownership remain distinct domain owners, but equipment and hand reservations are arbitrated by this common runtime. No PHP, Discord, Steam or LLM request blocks a tick. Production session origin is rejected, including sessions carrying the development permission.

`InventoryDevelopmentCommand` supports these new operations:

| Operation | Exact payload fields |
| --- | --- |
| `grip_join` | `session_id`, `expected_revision`, `target_id`, `action`, `hand_ids` |
| `grip_release` | `session_id`, `expected_revision` |
| `grip_resume` | `session_id`, `expected_revision` |

`expected_revision` refers to the grip owner, not the shared inventory revision. The command ID supplies the receipt ID; local principal binding supplies the body ID. Players cannot supply other bodies, strength, contact flags or force requirements. Joining derives all existing participants from the owner. A valid target/action cannot change during an existing session.

`inventory-grip-intent-v1.schema.json` codifies operation/payload fields; the existing simulation envelope supplies command identity, authenticated context and world scope.

Development fixtures are `fixture.salvage-crate` (cooperative movement requiring 300,000 mN) and `fixture.ladder` (anchored grip/traversal requiring 100,000 mN), both at `[0,0,0]` mm. A body contributes a provisional 200,000 mN total for its chosen hands; additional hands do not multiply strength. Contact is currently logical distance at most 1,500 mm, with no occlusion, surface normals or rigid-body collision checks. These are logical interaction targets, not inventory items, spawned matter, moving crates or physical ladders.

## Hand arbitration

Join requires existing profile hand slots that are unequipped. The owner rejects hands already reserved by another grip. Self equip and world pickup into an equipment slot reject reserved hands before committing inventory changes. Timed equipment changes into another body's hand check the reservation again at completion. World pickup/drop, self equipment/storage changes and timed inventory work require at least one unreserved profile hand; existing held tools remain usable by the current inventory interaction model. Choosing the active hand does not occupy it, so hand switching remains allowed.

Commands apply in queue order before system ticks. This prevents a grip and equip processed in the same tick from both acquiring the same hand. Only a release frees a paused reservation. Active grips whose participant moves outside fixture reach automatically release that participant at the next system tick, using bounded ordinary owner receipts. Remaining cooperative capacity is re-assessed from current membership; contact loss does not relocate or destroy any object. Paused restored grips retain their reservations for explicit recovery/release.

`local_grip_observation()` is principal-scoped and includes grip revision and only the sessions containing that body: session/target/action, paused status, own reserved hands, participant count and current availability. It exposes no other player's inventory or private data. Availability is a pure assessment, not a command authorization or actual movement result. Runtime profiling includes the domain counters under `grip_` keys.

The [local grip panel](local-grip-panel.md) now uses observation v2, adding this body's hand states and public fixture target reach/actions/session metadata. It submits the same queued development intents and remains outside canonical state.

## Snapshot v4 and recovery

Inventory-system snapshots emit v4 with an additional `grips` owner record. V1-v3 migrate to an empty grip owner while preserving all existing item matter and location metadata. The world snapshot outer version remains unchanged. Decode validates both owners and their links before any restoration: targets must be registered/compatible, participant bodies must exist, hand IDs must belong to their profiles, and reserved hands must not also be equipped. Invalid cross-owner saves reject atomically. The v4 schema is `inventory-system-state-v4.schema.json`.

All restored grip sessions pause. A sole participant can queue `grip_resume` after fresh derived contact/loadout checks. Cooperative recovery currently requires every member to release their own paused participation, followed by explicit joins into a new active group; a single local principal cannot reauthorize everyone. Group resume with individually recorded fresh consent is future work. Disconnect/controller replacement cleanup and durable authenticated transport are not implemented.

## Verification and next implementation

Windows headless import and focused grip runtime checks cover occupied/reserved hands, explicit cooperative joins, retained retries, world pickup, timed equipment completion, contact loss, principal scoping, paused JSON recovery, solo resume, cooperative resume rejection, cross-owner atomic rejection, v3 migration and production-origin rejection. Existing self inventory, world pickup/drop, 3D spatial and inventory runtime suites passed. CI includes the new script for Windows/Ubuntu; remote CI and Linux execution remain unverified locally.

Next add actual body/assembly physics, collision-derived contacts and grip constraints. Then add physical impulse push-off, object force/torque, inventory pickup/grip release coordination for real targets, resource-backed strength and gameplay/UI controls. Current crate/ladder commands reserve hands and evaluate capability only; they do not move bodies or world objects.
