# Hand traversal and world manipulation

## Gameplay

[Combat, restraint and body transport](combat-restraint-and-body-transport.md) extend these principles to contested grabs, knockdowns, dragging/carrying bodies, rolling beds, buckling and container confinement. These interactions are planned; existing grip foundations do not yet implement body combat or attachment physics.

Players with an available, capable hand can push off a reachable surface in zero or low gravity. They can grip handholds, ladders, rails and suitable object geometry, then pull themselves along. These actions also work under gravity when strength, support and contact permit. A free hand is a physical capability: an occupied, disabled or already reserved manipulator cannot simultaneously perform another action. Human hands, cyborg manipulators and remotely controlled equipment share this rule through body profiles.

Players can grasp and move a world object without storing it in their inventory. This supports hauling salvage, moving machinery, carrying bulky equipment and cooperative handling. Inventory capacity does not limit this action; physical strength, grip geometry, clearance, inertia, support and equipment do. An assembled or bolted-down machine must first be detached through its construction/maintenance contract. Moving an object preserves its stable identity, contents, damage and connections; connections may constrain movement or require disconnection.

## Physics and ownership

Pushing applies a bounded contact impulse with an equal opposite reaction to the contacted body/assembly. A freely floating crate recoils; a massive station receives the corresponding reaction through its assembly owner. Releasing a grip preserves momentum. Hand traversal does not grant gravity, automatic braking, infinite strength, teleportation or pressure protection. Moving-frame relative velocity and collision must govern whether contact can be acquired safely.

Ladders and rails offer authored/procedural grip anchors and directions. Pulling uses force-limited constraints between the body and anchor. Smooth surfaces may permit pushing while offering no usable grip. Surface geometry, material, condition, gloves/tooling and accessible anchor points determine suitability. Low gravity reduces weight but does not remove mass or rotational inertia. A force requirement must include intended acceleration, torque, gravity, friction and obstruction; do not use inventory mass capacity as a movement threshold.

Cooperative movement uses one target interaction owner with explicitly joined participants. Each participant contributes a server-observed body force budget once, with hand reservations and reachable contacts. Participants must independently authorize joining; proximity alone grants no control. Direction, leverage and contact geometry determine effective combined force/torque; blindly summing opposing pulls is invalid. The prototype accepts already aligned force budgets supplied by future physics, rather than calculating leverage. Leaving, releasing, losing contact or becoming incapable removes contribution on the next tick and may cause slipping/dropping if the remaining group cannot support the load. Collision and attachments can still prevent movement despite sufficient strength.

World objects remain in their existing canonical world location owner while grasped. A grip is a constraint/reference, not a second inventory item or ownership transfer. Inventory pickup is a separate atomic operation that releases all relevant grips and updates the existing ledger location exactly once. Drop places an item into world ownership before anyone grips it. Existing world inventory root metadata and preview meshes are not yet physical object bodies and must not be used as substitute physics state.

## Implemented pure gate

`PhysicalInteractionPolicy.assess()` validates a versioned trusted observation for `push_off`, `grab`, `pull_along` or `move_world_object`. Traversal has one participant; cooperative world manipulation accepts up to sixteen distinct bodies, with up to eight distinct free hand IDs each. It checks capability, reach/contact, usable hands, target affordances, summed aligned force budget and contact strength. Invalid contracts fail; valid but unavailable interactions return `allowed: false` with reasons.

All force values are integer millinewtons, bounded to 1,000,000,000 per observation/participant. The caller supplies a total body budget for exactly the listed hands, preventing per-hand multiplication. `free_hand_ids` lists the hands proposed for this action, not every unused hand on the body. Results contain detached proposed reservations; assessment does not reserve hands, apply forces, consume stamina, change inventories or mutate world state. Required/contact force and all availability flags must come from trusted physics/loadout observations, never player or LLM claims. A successful gate is not permission or a durable action receipt.

The default fixture demonstrates two individually insufficient bodies moving a shared salvage crate. It is a policy example, not a runtime crate or saved grip. Contact/force observations use `physical-interaction-observation-v1.schema.json`; semantic unique-body/hand checks also run in code.

## Runtime implementation stages

[Physical grip ownership](../architecture/physical-grip-ownership.md) adds a domain owner with atomic reservations, explicit cooperative joins/releases, bounded receipts and paused recovery.

The subsequent [local inventory runtime integration](../architecture/inventory-grip-runtime.md) now composes that owner with queued development commands, inventory reservation checks and v4 world recovery. Production authentication and physics constraints remain pending.

[Push-off momentum](../architecture/push-off-momentum.md) now adds pure linear motion records and normal impulse plans with exact equal opposite reactions. It is not yet wired to runtime physics or controls.

1. **Implemented:** bounded pure availability/force gate, cooperative fixture and focused checks.
2. Add a fixed-tick physical interaction owner with authenticated body binding, target revisions, unique hand reservations shared with equipment/inventory actions, bounded participant sessions and idempotent command receipts. Resolve competing grabs/pickups deterministically. Commands request intent; the owner derives observations and verifies authority.
3. Add rigid-body/assembly targets, grip anchors, body mass, contact normals and relative velocities. Integrate conservative impulses, force/torque limits, collision constraints and frame-aware traversal with the gravity policy. Add stamina and powered manipulator budgets.
4. Add cooperative joining/releasing, aligned force/torque calculation, contested control and loss-of-support behavior. Configure whether targets can be pulled, carried, pushed, attached or detached through components, not display names.
5. Persist object/body identity and canonical motion through their existing owners; checkpoint explicit grip intents and participants but restore grips paused until fresh authority, hand availability and contact checks succeed. Never restore a stale physics constraint blindly. Add UI highlighting, grip/release input, ladder feedback and physical pickup transitions.

Profile bounded active interactions, reserved hands, contact checks, rejected actions, constraint work and cooperative membership changes. The owner runs at physics ticks and must never wait for external services; player, script and LLM requests use the same queued command path.

## Verification

Windows Godot headless editor import and `physical_interaction_policy_test.gd` passed. The focused script covers single/cooperative force, anchored targets, push/grip affordances, ladder traversal, unavailable hands/helpers, weak contact limits, duplicate bodies/hands, fractional force rejection, detached inputs and JSON round trips. Windows/Ubuntu CI includes the script; remote CI, Linux execution, runtime physics and graphical behavior remain pending.
