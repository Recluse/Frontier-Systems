# Procedural habitat cutaway

The client prototype now pairs its scrollable control panel with a 3D habitat/airlock viewport. `ProceduralHabitatPreview` generates box meshes, untextured first-party materials, lighting and pressure labels in code. No imported art, character models, textures or fonts are added. The project retains Forward+; the scene makes no platform-specific renderer calls.

The preview has its own `SubViewport`/`World3D`. Dedicated/headless world bootstrap does not create the layout, mesh resources or camera. Presentation is under `src/presentation/habitat/`, separate from canonical systems and integration adapters.

## Observations and geometry

The bootstrap passes the existing pressure/access observation into the preview each client frame. Door booleans select closed or raised visual targets. Door meshes interpolate toward those targets on the presentation clock; this does not add actuator travel time to the simulation. Pressure labels use validated finite absolute kPa sensor readings. Invalid observations leave prior display targets unchanged.

Geometry is an illustrative cutaway: a 20-by-10 metre habitat footprint, a 2-by-2 metre chamber, two 2.4 metre door panels and a flat surrounding surface. Walls are deliberately truncated and the roof omitted to make the engineering state visible. Mesh geometry does not determine gas volume, seal integrity, occlusion, walkability or power topology. Simulation volumes remain the existing domain records. These dimensions are not a construction blueprint or a physically sealed room.

The preview now has [local collision proxies and a capsule character](local-character-navigation.md). Terrain generation, resource deposits and authoritative gameplay bodies remain absent. Native mesh/node names are presentation identifiers, not persisted world entity IDs.

## Inspection cameras

The **Overview** control resets an orbit view around the cutaway. Right-drag rotates, and the mouse wheel changes radius within bounds. **Interior free look** resets a local camera inside the habitat facing the chamber. While holding right mouse, WASD moves along camera forward/right, Q/E moves vertically and Shift increases speed. Releasing right mouse, pressing Escape, losing window focus or destroying the camera releases capture.

Free-look movement is a local inspection tool: it can pass through geometry and is neither a player body nor a permission-bearing station AI/cyborg. Separate local first/third-person character views now provide prototype collision-aware walking. Multiplayer character cameras still require authoritative movement, replicated pose and spatial interaction checks.

The dedicated preview viewport isolates its mouse interaction from the engineering panel. No camera action creates a world command, changes physics state or affects command authorization. Inspection controls depend on native viewport input forwarding; actual mouse/keyboard ergonomics still require graphical playtesting.

## Verification and limits

`tests/godot/habitat_preview_test.gd` checks real snapshot consumption, door interpolation, invalid-pressure rejection, unchanged world snapshots across observation/camera changes, client layout creation, viewport allocation and panel camera routing. The tests run with dummy/headless rendering and passed on Windows Godot 4.7.2. CI includes the check for Windows/Ubuntu; Linux execution and actual GPU appearance remain pending.

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe' --path .
```

Use that normal client launch for visual inspection. Tick profiling does not measure GPU/rendering cost; the extra viewport remains outside simulation execution timings. Mesh batching, render scaling and a real player controller are later work. The inspection/geometry helpers may eventually be packaged as reusable MIT Godot tools once their editor interfaces and asset documentation are stable.
