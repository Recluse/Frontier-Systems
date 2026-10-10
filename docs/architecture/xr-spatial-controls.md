# Spatial XR airlock controls

## Scope and ownership

`XRSpatialAirlockPanel` and `XRSpatialPointer` supply a local development control panel in the optional PC VR preview. Native procedural meshes and text are first-party MIT assets. The panel is available only in debug builds and targets the existing prototype airlock. It is not a production player interaction endpoint.

Canonical pressure and airlock state remain owned by the existing simulation systems. Selection creates an `AirlockCommand` using the local development context and queues it through `WorldRuntime`. The simulation processes it on a later fixed tick using the shared access and pressure rules. UI callbacks never mutate valves or doors directly. No external I/O or promise waits occur in the selection path.

## Controls and input lifecycle

Eight stable controls open/close the inner door, outer door, equalization valve and vent valve. Labels show queued, applied or rejected feedback and refresh pressure/door observations at most 10 Hz. One pending command disables further submissions until its matching airlock completion arrives. World closure clears the pending display and disables selection.

The native right controller's `aim_pose` supplies the ray; the original right grip controller supplies the analogue trigger. `stage_input()` caches one finite, bounded sample. Physics frames consume it only while focused, tracked and at most 250 ms old, measured using monotonic wall time. The ray has a five metre maximum range. This range is a UI convenience, not an authoritative body reach check.

Trigger values at or below 0.25 arm selection; values at or above 0.75 consume one press. Starting or regaining focus/tracking with the trigger held cannot select. A press consumed on an empty, occluded or unavailable target cannot activate another button by dragging while held. Invalid input, stale samples and recenter reset the gate. The beam and highlight are disposable presentation and are not persisted.

## Physics and target identity

Ray queries run only in `_physics_process()`, using native `PhysicsRayQueryParameters3D`. Collision layer 1 contains preview obstacles, and layer 8 contains the panel backing and button areas. The nearest hit stops the ray; walls and backing occlude buttons. Button lookup matches the exact registered collider instance rather than trusting names or metadata. See Godot's [ray-casting guidance](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html).

The panel is positioned in the habitat at (-4.2, 1.35, -0.4) metres. Its eight buttons and backing are local scene geometry, outside canonical world snapshots. Bounded diagnostic counters expose ray query and successfully queued selection counts, capped at one billion each. They do not affect simulation outcomes.

## Verification and next steps

`xr_spatial_controls_test.gd` exercises actual native physics frames without enabling XR hardware: initial/held trigger gates, hover isolation, queued versus committed commands, unsafe pressure rejection, pending guard, wall occlusion, collider impersonation rejection, focus regain, stale and invalid samples, unknown controls and world closure. The rig resource test checks the separate aim node and one-time panel construction. Windows checks passed; Windows/Linux CI includes the scripts. Quest rendering and physical controller alignment remain unverified.

Before production interaction, replace the development identity with authenticated player sessions and server-owned body/pose/reach/capability validation. Add network intents, accessibility/hand selection and a reusable spatial target adapter. Physical grip, inventory and push-off controls must use their existing owners and validators. Spatial UI theme/mod support and haptics are future work; this panel does not yet implement the desktop overlay theme contract.
