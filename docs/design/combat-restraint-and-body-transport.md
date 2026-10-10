# Combat, restraint and body transport

## Direction and status

Combat should support the physical, situational interactions requested by the project owner: knock players over, grab and drag them, carry them, buckle them onto rolling beds or chairs, and confine them inside containers such as welded boxes or lockers. Use independent first-party mechanics, terminology, definitions and assets under the project licensing policy.

**Primary requirement:** physical combat is largely physics based. Actual body/tool trajectories, collision geometry, contact, support and bounded applied effort determine strikes, blocks, shoves and holds. This must support immersive VR hand interactions alongside first/third-person desktop controls. Authored physiology and balance policies interpret physical outcomes; they do not replace contact with a button-declared successful hit.

**Planned, not implemented:** this document adds design requirements and implementation stages. Existing logical grip, inventory and motion foundations do not yet simulate combat, body transport, buckling or occupied containers.

## Posture, force and combat

Separate standing, crouched, prone and supported/seated posture from consciousness, injury, stun and movement capability. A player can be conscious while prone, incapacitated while strapped to a bed, or mobile with an injury. Knockdown changes posture/control capability and may cause a collision injury; it does not automatically mean unconsciousness or lethal damage.

[Consciousness and sustained unconsciousness](health-medicine-and-chemistry.md#consciousness-knockout-and-sustained-unconsciousness) define injury-driven knockouts and chemical sedation. Physical impact supplies injury observations; the health owner determines unconsciousness and recovery from all continuing causes. Voluntary grip/combat inputs stop while unconscious, including VR hand input; physical transport, restraints and environmental exposure continue.

Attacks and shoves require server-observed range, contact, body/tool capability and resource availability. The defender can move, block, brace or resist where their current capabilities permit. Tools and body parts declare contact affordances, force/impulse limits and damage profiles. Health receives injury events through its owner; combat must not manipulate anatomy or chemical records directly.

Gravity, support, traction, mass and relative motion affect outcomes. In zero gravity, pushing an unsupported body creates motion with a reaction on the attacker or backing assembly. There is no automatic floor knockdown or immobilization merely because a timer says stunned. Apply posture changes and physical impulses through their respective owners; do not teleport bodies or discard momentum.

Resolve simultaneous interactions in stable tick order with bounded action durations, recovery windows and stamina/power costs. If later mechanics use probability, use authoritative saved random state and reproducible event results. Clients and LLMs request actions, not successful hits or claimed defender states.

## Physics-driven combat and VR

### Shared physical model

Represent body collision zones, usable manipulators, held tools and support contacts with stable canonical IDs and explicit geometry. Begin with simplified articulated bodies and physical hand/tool proxies; detailed active ragdolls are a later fidelity option. Posture changes should reflect loss of support/balance and recovery capability. Avoid requiring a full ragdoll solver before the first playable shove and block.

Derive impact observations from collision contact: local relative velocity at the contact point, normal/tangential motion, participating mass and rotational inertia, contact geometry, duration and resolved impulse. An impact policy maps these observations plus armor, material, anatomy and tool affordances into injury/stagger outcomes. Cuts, punctures, blunt impacts and sustained compression have distinct policies. Swing speed alone is insufficient to determine damage, and carrying a massive tool does not grant unlimited striking energy.

Off-center strikes and holds need torque and angular momentum, friction and bounded actuator work. The current centerline `PushOffImpulsePlanner` cannot serve as a general melee collision solver. Extend motion/physics contracts before combat integration. Account for muscle, suit or powered manipulator work and dissipation; conservation of momentum alone does not bound energy injection.

Blocks require actual interposition/contact of a capable hand, shield, tool or structure. A deflection can change a tool's path; a grip can constrain a limb or held object; a shove can destabilize a body's support. Do not apply both the engine's resolved impulse and a duplicate gameplay impulse. Group collision callbacks into bounded contact episodes so resting contact, vibration or multiple collider contacts cannot repeat one strike's injury every tick. Sustained crushing uses elapsed load exposure separately.

### Input adapters

VR supplies desired tracked hand/head poses and grip/release intentions. Desktop supplies bounded hand/tool target trajectories generated by swing, block, shove and grab controls. NPCs and agents supply the same bounded intents. All adapters use the same body capabilities, force/work limits, collision evaluation and injury policy. Desktop users need usable blocking, reach and precision controls; VR movement must not bypass equipment or body limitations.

Tracked controllers are desired targets, not authoritative colliders moved by teleportation. Server-controlled physical proxies follow them through constrained, effort-limited motion. A real hand can pass a real-world empty space occupied by a virtual wall; its proxy and held tool must remain blocked, with clear visual discrepancy feedback. Validate finite poses, timestamps, sequence/order, body binding, reachable envelope, continuity and maximum plausible velocity/acceleration. Reject stale or discontinuous tracking instead of turning recovery jumps into damaging swings.

Recenter, snap turn and seated calibration transform presentation. They must not generate strike velocity, weapon displacement through geometry or free combat impulse. Reset/reconcile pose history and require fresh valid tracking before enabling contact actions. Tracking loss pauses active hand input and prevents new attacks; existing body restraint/support remains governed by its owner. Define bounded hold/drop behavior for held objects without freezing targets indefinitely.

The current XR aim ray selects a development UI panel only. It is not a physical hand, weapon collision shape or authoritative body reach observation. VR combat requires separate grip-pose/body integration, including room-scale body collision and tool ownership. Haptics and effects observe accepted contacts and add feedback without creating damage.

### Multiplayer and performance

Resolve physical combat on the authoritative Godot host at the fixed simulation cadence, independently of headset refresh and external services. Predict local hand/tool presentation for responsiveness and reconcile to host state. Remote clients receive bounded pose/contact/state updates; clients never submit trusted damage, impulse or contact outcomes. Start with current-tick host validation; any later rewind policy must explicitly handle moving ships, obstacles, grips and world revisions without applying historical damage twice.

Do not assume native physics is bit-identical across operating systems. Stable command order, saved authoritative outcomes, revisions and snapshots provide consistency; deterministic lockstep requires separate proof. Limit active articulated bodies, contacts, constraints and optional substeps. Fast tools/projectiles need validated swept collision or appropriate continuous collision handling to prevent tunneling. Sleep/distance optimization must preserve nearby interactions and cannot skip a sealed occupant's physiology.

## Grabbing, dragging and carrying

Bodies are world entities with stable identity, mass, worn equipment and contents. Grabbing references the body; it does not convert a player into an inventory item or transfer ownership of their possessions. One sustained interaction can develop into a stronger hold through explicit timed steps with resistance opportunities, rather than silently granting control on first contact.

Dragging uses a force-limited grip/constraint, available hands, reachable anchors and obstruction checks. A prone body may be dragged along a surface; collisions, friction and unsuitable terrain can slow movement or injure the patient. Carrying requires a supported load and appropriate manipulators, clearance and force budget. Cooperative carrying uses independently joined participants and the existing shared reservation principles. Equipment and carried contents contribute to total mass.

Resisting, movement out of reach, lost grip, incapacity or depleted effort can interrupt an attempt or release a hold. Releasing preserves the body's physical state and momentum. Carrier disconnection cannot delete or leave a body attached to a nonexistent controller. A strapped patient's transport attachment can persist independently of its previous operator.

Distinguish the existing cooperative grip join rule from contested grabs: helpers must authorize their own participation, while a target may be grabbed without an approval popup through the configured combat rules. Inaction permits attempts to progress; resistance remains an available action where capability permits. A grip never grants persistent access to the target's records, inventory or controls.

## Buckling and movable supports

Chairs, seats, stretchers and rolling beds expose data-defined support anchors, occupant limits, compatible body profiles, restraints and release affordances. A rolling bed combines the same support/attachment components with wheels or another movement component; it is not a special teleporting transport system. Restrained occupants add mass and inertia to the assembly and move with it.

Buckling another body requires suitable proximity/posture, an available anchor, time and compatible restraints. Self-buckling and unbuckling use explicit intents. Straps, locks and immobilizing restraints differ: a seat belt may permit self-release, while a locked restraint requires keys, tools, force or assistance. Capability loss is defined per restraint; buckling must not universally disable every hand, tool, speech channel or bodily action.

Move and rotate the support through normal physics, including slopes, braking, collisions and gravity changes. Damage may loosen straps, jam a latch or break a mount. Detachment resolves a safe world position and velocity through physics, or remains pending if no valid placement exists. Do not duplicate occupants, eject them through walls or silently remove restraints on load.

## Container confinement and escape

Occupant-capable boxes and lockers declare internal dimensions/capacity, entrances, occupancy anchors, internal controls, seals, ventilation and valid access from each side. Closed, locked, jammed and welded are independent conditions. Only definitions with suitable space and an entry path accept bodies; ordinary inventory containers do not implicitly support occupants.

Placing a resisting or incapacitated body inside is a timed physical action using the same reach, force, clearance and attachment rules. Closing an occupied container requires valid occupancy and doorway clearance. Welding requires a compatible surface/tool, finite consumables, time and environmental safety checks. Welding changes the seal/latch component; it does not destroy the occupant or grant an indestructible prison.

Escape and rescue depend on actual affordances: internal releases, accessible tools, prying/cutting welds, lock bypass, force against structural limits, outside assistance, or dismantling compatible panels. A contained body retains only the actions physically available inside. Communicating remains governed by fitted radio/PDA equipment, power and signal propagation rather than a universal confinement mute.

Containment must integrate with the pressure/health model. A sealed finite internal atmosphere can run out of breathable gas; a vented locker exchanges with its surroundings. Neither sealing nor being inside automatically makes a container airtight, pressure-rated or safe. Heat, fire, chemical leaks, oxygen use and pressure hazards use the same volume/exposure owners. Deconstruction must expose/release occupants through an explicit transaction before removing their container; if geometry prevents safe release, resolve obstruction or damage through configured rules rather than deleting a body.

## Proposed architecture and authority

| Contract | Responsibility |
| --- | --- |
| Body posture/capability state | Posture, support and transient action restrictions; separate from health/life state |
| Combat action/job owner | Attack/shove/grab phases, bounded effort, resistance and completion receipts |
| Physical grip owner | Exclusive manipulator reservations and sustained force-limited contacts |
| Attachment/occupancy owner | Canonical occupant links, support anchors, restraints and container relations |
| Motion/assembly owner | Mass, reaction impulses, constraints, collision and moving-frame transport |
| Container security/pressure components | Entrances, latch/weld state, ventilation and physical hazards |

These are proposed integration boundaries, not new runtime classes. Reuse existing owners where responsibilities match; do not duplicate health, inventory, hand reservation or motion state. Each body has at most one primary support/containment parent, with separately bounded grip references. Validate an acyclic attachment graph and aggregate mass exactly once. A bed can carry a patient and move inside a ship through nested frames without creating duplicate world locations.

Fixed-tick commands validate authenticated body binding, target revisions, current reach, effort, tool capability, occupancy and resistance. Changes spanning attachment, reservations and motion require an atomic transaction plan. Conflict ordering and retained command receipts prevent double carrying, duplicate occupants, repeated attacks and double consumption on retry. Scripts, remote cyborgs and LLM agents use the same action registry and validators. External service responses never stop ticks or directly move bodies.

Persist stable links, posture, restraints, container conditions, job progress, resources and revisions in versioned records. On restore, keep valid buckles/confinement, rebuild physical constraints only after validating restored geometry/owners, and pause active hand-operated grabs pending fresh contact/control. Detect orphaned/cyclic links explicitly; never silently free a restrained patient or delete a missing-parent occupant. Bound and profile active actions, contested holds, attachments, contact checks, resistance evaluations and constraint work.

## Staged implementation and acceptance checks

1. Define body posture, support/occupancy and restraint records with human, cyborg, chair, rolling-bed and locker fixtures. Check compatibility, anchor capacity, graph cycles and detached save recovery.
2. Implement authoritative physical body/hand/tool proxies, angular motion/work budgets and contact-to-injury policies, then queued shove/knockdown, blocking and recovery. Check standing versus zero-gravity outcomes, reaction momentum, off-center impacts, obstruction, effort, tunneling, contact-episode deduplication and duplicate retries.
3. Extend sustained grips for contested body grabs, dragging and cooperative carrying. Check target resistance, reserved hands, combined load, lost support and controller disconnect.
4. Add support attachment and self/other buckling/unbuckling. Check competing occupants, permissions versus physical restraint, moving beds, body mass accounting and safe detachment.
5. Add occupant-capable container entry/exit, lock/weld work and rescue/bypass. Check occupied closure, inaccessible internal tools, interrupted welding, finite materials and dismantling with occupants.
6. Integrate internal atmospheres, injury/exposure and diagnostics; expose desktop/VR interaction feedback. Check sealed/vented containers, restart continuity, observation scopes and equivalent player/script/LLM validation. Validate VR tracking loss/recovery, implausible poses, recenter/snap-turn discontinuities, wall-blocked hands, desktop/VR effort parity and prediction reconciliation before exposing multiplayer combat.

Add focused Windows/Linux checks as each stage is implemented. Scenario fixtures should include medical rescue as well as antagonistic use; confinement and restraints are configurable gameplay, not substitutes for administrator moderation.
