# Push-off momentum foundation

## Canonical motion and units

`LinearMotionState` is a pure, versioned local-frame mass/momentum record. It contains body/assembly identity, reference-frame identity, state revision, integer mass in milligrams and three integer linear-momentum components in **micro-newton-seconds** (`micro_ns`: 1 unit = 10⁻⁶ N·s = 10⁻⁶ kg·m/s). Mass and momentum share the 10⁻⁶ SI scale, so derived velocity in m/s is component momentum divided by mass. Velocity observations use floating-point numbers; momentum remains canonical.

Prototype bounds are mass 1..10¹² mg, component momentum ±10¹² micro-N·s, aggregate local speed at most 10,000 m/s and revisions up to the existing exact JSON integer limit. These are explicit contract limits, not species or engine performance claims. JSON integer-valued floats normalize to integers. Motion record observations are detached. Position, rotation, angular momentum, force accumulators and body shape are not part of this linear contract yet.

## Pure two-body impulse plan

`PushOffImpulsePlanner.plan(actor, target, contact, impulse)` validates distinct actor/target identities in one local frame, then computes a plan without mutating either record. The impulse vector is integer micro-N·s with component bounds ±10⁹. The contact record contains v1 schema, an outward unit normal scaled by 1000, a duration in microseconds (1..1,000,000) and a trusted `PhysicalInteractionPolicy` observation identifying this actor and contacted target assembly.

Normals must have exact squared magnitude 1,000,000; `[1000,0,0]` and `[600,800,0]` are supported examples. The impulse must be nonzero, outward and exactly parallel to that normal. Arbitrary quantized normals, tangential friction and off-center impulses require a future solver rather than an approximate acceptance rule here.

The required mean force is `ceil(ceil(|J|) * 1000 / duration_us)` in millinewtons. Integer square checks correct floating square-root rounding when deriving the norm. Integer ceiling is conservative: very small or diagonal requests may overestimate needed effort by one impulse unit. The planner replaces the observation's requested-force field with this derived value before checking body force budget and contact strength. A supplied zero cannot bypass effort limits. Availability, usable hands, reach and actual contact must all pass; the physics/loadout adapter must derive these flags and consult existing hand reservations. The planner itself does not authenticate a principal or reserve a hand.

The actor receives `+J`, the backing assembly receives `−J`, and both revisions advance once in the returned after-records. Each momentum component conserves exactly as an integer. Existing momentum, including tangential drift, is preserved. Derived velocity changes inversely with mass. A large station still receives reaction momentum; it is not an infinite-mass sink. Anchored surface geometry must resolve to its backing ship/station/planet assembly, not a massless terrain decoration.

## Owner integration and limitations

[Atomic linear motion ownership](linear-motion-ownership.md) now commits paired plans through current owner/body revisions, same-tick trusted contact and bounded saved retry receipts. The domain owner remains outside `WorldRuntime`; it does not yet provide collision contacts, resource budgets or player controls.

The returned v1 plan contains both before/after motion records, the impulse and derived force. The domain owner compares both revisions and current contact/frame state before committing either side; retained command receipts prevent applying an impulse twice. If either body changed or either limit rejects, neither side commits. The planner itself remains pure, and a fixed-tick runtime wrapper is still required.

This is a **centerline translational model**. The caller must supply a physical contact whose reaction does not require unmodeled angular momentum; off-center contacts need contact offsets, inertia tensors and torque. No collision solver, separation-time model, position integrator, gravity application, drift damping, frame transformation, stamina/power/work accounting or recoil animation is implemented. Momentum conservation is not an energy model: muscle/actuator work and dissipated energy must be accounted before production exposure. The duration is the trusted effective contact interval, not an arbitrary player-selected force multiplier.

The current preview capsule still uses its original movement physics, and logical crate/ladder grip fixtures remain unchanged. This planner is not registered in the runtime, persisted by world snapshots or wired to a player/LLM/UI command. Those integrations must use real canonical body/assembly mass and collision-derived contact rather than debug distance flags.

## Default scenario and verification

`data/locomotion/push-off.default.v1.json` demonstrates an 80 kg body pushing against a 120 kg salvage assembly for 0.1 s with 8 N·s. The actor gains 0.1 m/s and the target gains −8/120 m/s along the normal. Default capability/contact budgets allow 200 N; the derived mean force is 80 N. The fixture is tuning/reference data, not a spawned physics object.

Schemas codify linear motion, contact and impulse-plan records. Code additionally checks vector norms, normal alignment, matching participant/frame identities, bounds after transfer and exact conservation.

Windows headless editor import and `push_off_impulse_test.gd` passed. Checks cover exact opposite momentum, mass-dependent velocities, retained drift, massive/anchored backing assemblies, unavailable hands/contact, derived effort and weak surfaces, inward/tangential/zero impulses, diagonal/nonunit normals, frame mismatch, zero mass, speed/revision/fractional limits, detached inputs and JSON recovery. Windows/Ubuntu CI includes the script; Linux execution, remote CI and runtime physics remain pending.

## Next steps

1. Add a fixed-tick motion owner with two-body atomic commits, request receipts, saved records and profiling counters for accepted/rejected impulses and contact work.
2. Add collision-derived contacts, assembly backing ownership and deterministic frame transforms; extend angular momentum and work/resource accounting.
3. Integrate actual body/vehicle physics and free-hand push-off commands under common capability and hand arbitration. Preserve drift on release and apply gravity through the local-frame policy.
4. Add force-limited grip constraints and cooperative target motion, with contact loss, leverage/torque and inventory pickup transitions through their existing owners.
