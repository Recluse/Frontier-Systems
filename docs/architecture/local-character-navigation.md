# Local capsule character prototype

The cutaway preview now has a collision-aware `LocalHabitatCharacter` and explicit **First person** / **Third person** buttons alongside the existing inspection cameras. The body is generated from a capsule mesh and collider. No imported character art is added.

This is a local prototype in the preview's presentation world, not an authenticated multiplayer player entity. Its pose, velocity and camera are absent from canonical snapshots and cannot grant inventory, access, survival or LLM capabilities. There is no remote movement endpoint.

## Input and camera ownership

Select a character camera mode, hold right mouse in the viewport, then use WASD to walk, Shift to run and Space to jump. Releasing right mouse, Escape, focus loss or teardown releases capture and clears local movement intent. Gravity continues while the character mode is active, even with the mouse released. Choosing an inspection view pauses the local body and restores inspection camera ownership. Changing modes preserves body position.

Movement intent validates finite axes within [-1, 1] and normalizes diagonal input. Walk/run speeds are 4/7 metres per second. The initial body uses a 1.8 metre tall, 0.3 metre radius capsule and Mars-like 3.71 m/s² downward acceleration with a 2.5 m/s jump impulse. These are prototype constants, not regional planetary gravity or engineering mass/force models. Physics movement uses Godot `CharacterBody3D.move_and_slide` on fixed frames.

First-person mode places the camera near the capsule's eye height and hides its body mesh. Third-person mode shows the procedural body and uses a three-metre `SpringArm3D` that excludes the body and collides with environment barriers. Pitch is bounded; look input is gated by active camera/control ownership. There is no animation rig, head tracking, crouching, suit geometry, network interpolation or accessibility/controller mapping yet.

## Collision proxies

Generated floors and walls now have static box colliders. Their layer is 1; the local capsule is on layer 2 with environment mask 1. These proxies exist only in the client preview, not the authoritative world runtime.

Door collision proxies stay at the closed panel location, independently of the cosmetic rising mesh. A validated open/closed observation requests disabling/enabling its proxy through deferred physics-safe updates. An open observation therefore permits passage without waiting for the visual animation; a closed observation blocks passage even if the mesh is still descending. This is a prototype synchronization policy and may visually disagree during transition. No crush damage, occupied-door checks or authoritative character contacts are implemented.

Walls remain cutaway geometry and no roof collider is provided. This is not a physically sealed or secure navigable colony. The ghost inspection camera may still pass through geometry; it has no body interaction.

## Verification and next gates

`tests/godot/local_character_navigation_test.gd` advances real physics frames and uses real airlock commands with zero-pressure test fixtures. It checks grounding, closed/open door passage, outer-door blocking, finite/normalized input, grounded jumps, camera visibility/arm behavior, inspection handoff and unchanged canonical snapshots. Windows Godot 4.7.2 checks passed. Linux CI and graphical/input ergonomics still need validation.

Next steps are stable actor/body IDs, movement intent contracts, authoritative regional physics ownership, replicated pose/prediction, reach checks, inventory/suit/vital components and cross-system occupied-door rules. The local character must not be promoted into a production authority source by exposing its setter or trusting client transforms.

### Held-look UI handoff in the actual client

The client routes a mouse look gesture into its preview SubViewport before root GUI mouse hit-testing, so holding RMB cannot pin a subsequent Left Alt UI click to the forwarding surface. Ordinary world picks keep native dispatch. The gesture release and Escape reach the preview even over another UI control or a focused editor. PlayerInputSettings checks both root and owning viewport GUI focus before granting capture or allowing navigation; Alt release recaptures only when no GUI control owns focus. Focused coordinate editing therefore pauses local movement/look with RMB held. See [held-look acceptance](../development/held-look-ui-activation-milestone.md) for injected actual-client checks and physical-input limits.
