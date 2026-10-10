# Gravity and EVA locomotion

## Required gameplay

Ships, orbital stations and colonies outside meaningful planetary gravity need working gravity generators for gravity-supported walking. Loss of generator power, condition or field coverage leaves the affected space in free motion. Players can use magnetic boots, handholds, tethers, jetpacks, other rated equipment or remote bodies to traverse it.

Separate local weight from celestial gravitational acceleration: an orbiting station can be in free fall inside a planet's gravity well and still need artificial gravity. Planetary surface habitats use natural local gravity; generated fields are the game's engineered technology. Ship acceleration and rotation can eventually provide other frame effects through explicit physics adapters.

## Simulation contracts

[Hand traversal and world manipulation](hand-traversal-and-world-manipulation.md) specifies free-hand push-off, ladder/handhold pulling and cooperative movement of objects that remain outside inventory. Its pure gate complements gravity resolution; authoritative grip constraints and body physics remain pending.

Gravity belongs to an authoritative region/assembly reference frame. It is a vector, not a global downward constant. Persist generator hardware, power connections, condition, coverage, settings and reference-frame relationships. Expose the resolved acceleration as an observation; the body physics system applies forces at fixed ticks.

Generator requirements include construction materials, electrical supply, operating condition and defined coverage. Outages and faults degrade or disable coverage while preserving repairable equipment. Overlapping fields need deterministic selection and boundary behavior; never multiply gravity because a device is registered twice. Docked ships and moving assemblies require explicit frame ownership and transitions.

Mag boots require actual contact with a compatible magnetic surface, enabled/intact hardware and their own power supply. They provide attachment/traction to floors, walls or hulls, not a gravity field for nearby items. They do not attach to empty space or automatically work on dirt/nonmagnetic surfaces. Future adhesion limits must account for acceleration, impacts, relative velocity, surface strength and safe detach/reattach. A station blackout need not disable separately battery-powered boots.

Jetpacks provide commanded thrust using available power/condition and finite propellant. They do not grant gravity or free hover, stop momentum automatically, refill fuel or remove pressure/thermal hazards. Integrate body/vehicle mass, thrust limits, rotation, collision, fuel consumption and exhaust accounting into the fixed-tick motion/resource owner. Stabilization is a separately configured controller with the same budgets.

In free motion, preserve velocity/inertia when propulsion or attachment is absent. Keyboard walking must not overwrite velocity as if a floor existed. Equipment may make EVA controllable, but breathing, pressure protection, temperature and other survival requirements still apply. Cyborgs/remote instruments use their chassis/module power, propulsion and attachment capabilities under the same authority rules.

## Implemented policy foundation

`LocomotionEnvironmentPolicy` under `src/core/locomotion/` validates a local-frame observation and trusted equipment/contact flags, then returns resolved gravity source/vector, locomotion mode and attachment/thrust availability. It neither applies forces nor consumes power/propellant.

Environment records include natural acceleration in integer mm/s², a free-fall flag and at most sixteen unique generator fields. Non-freefall natural acceleration takes precedence in this prototype. Otherwise, active, powered, covered and intact generators select by highest priority, then stable ID. Fields do not add together. Generator acceleration scales linearly with permille condition, truncating to integer mm/s²; this is provisional tuning, not a hardware model.

Modes are `gravity_supported` when contact and effective gravity exist, `magnetic_attachment` when qualifying boots/contact exist, or `free_motion`. Jetpack thrust availability is independent of that mode and requires nonzero propellant. Boots do not change the resolved gravity vector. Contact, surface compatibility, power and equipment flags must come from canonical physics/loadout observations, not player or LLM claims.

Default fixtures cover Mars/Moon surface frames and a generated-gravity space station. Values are simplified prototype tuning. The existing preview capsule still uses its fixed Mars gravity; no gravity/boot/jetpack physics system, generator device, fuel consumer or runtime environment adapter is implemented yet.

## Implementation stages

1. **Implemented:** local-frame policy, default configurations and pure availability/gravity resolution.
2. Add region/assembly gravity observations and generator components with power/condition/coverage and saved frame membership; integrate profiling and outage recovery.
3. Replace fixed preview/server movement assumptions with authoritative frame-aware acceleration and free-motion inertia. Cover moving/docked assemblies and field boundary transitions.
4. Add surface-normal/adhesion constraints and inventory-backed mag boots, handholds and tethers. Then add propellant/power-backed jetpack force commands and controllers.
5. Integrate EVA suit survival, cyborg modules, rescue UI, equipment alarms and admin-configurable environmental events. Every player/script/LLM action uses the same server-owned capability and resource checks.

## Verification

Windows Godot 4.7.2 import and `locomotion_environment_policy_test.gd` passed. Checks cover surface gravity, powered/generated gravity, damage/output degradation, outages, coverage, orbital freefall, deterministic non-stacking fields, boots/contact compatibility, fueled/depleted propulsion availability, detached input assessment and invalid quantities. Windows/Ubuntu CI includes the script; Linux and runtime physics integration remain unverified locally.
