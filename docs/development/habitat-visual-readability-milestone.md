# Habitat visual readability milestone

Base: 82ed214a9dcadb742b1fbaa778f4d7375f229c49. Branch: habitat-visual-readability, draft PR targeting dev-master. No merge, integration push or deployment authorized.

Presentation-only work improves the cutaway floor contrast and native directional shadows, clustered resource silhouettes, supported workbench surfaces, storage tray rims/pedestals and advisory terrain outlines. The original IDs, anchors, collision shapes, reach, native picking, input guards, target feedback, terrain preview and UI panels remain owned by their existing components.

HabitatVisualDetails owns disposable mesh decorations. Resource children inherit existing observation visibility/depletion scale. Tray decoration rebuilds only when the inventory display rebuilds and caps itself at 32 trays. Terrain outlines follow the existing two observed marker positions and retire when observations disappear. No canonical state, schema, persistence, simulation tick or service boundary changes.

Provenance: independently authored first-party MIT GDScript and Godot primitive meshes/materials; ordinary Godot rendering only. No AI image generation, imported artwork/fonts or new creative dependencies. Local captures/logs go under ignored var/ and must not be uploaded or used as public showcase material without future owner clearance through Coordinator.

Verification is in progress. Required evidence: bounded Windows import/startup, preserved target and context interaction regressions, focused decoration lifecycle/anchor checks, actual local graphical captures with Compatibility and Forward+ coverage reported separately. Headless results do not establish GPU appearance, Linux native rendering, physical controller ergonomics or human acceptance.

## Verified local scope

Windows Godot 4.7.2: bounded import/startup and habitat_visual_details_test, habitat_preview_test, habitat_target_feedback_test, world_inventory_preview_test, terrain_work_target_test and world_context_label_test passed. The new check consumes real in-memory authenticated production/inventory/terrain observations; checks source/pick dimensions and anchors, no decoration collision, stable tray allocation, visibility, canonical snapshot immutability, depletion/unavailable resources, removed trays and terrain outline retirement. Its initial missing terrain grant failed and was corrected; that failed run is not counted as success.

Ordinary native rendering passed on NVIDIA RTX 3080 Ti in both Compatibility/OpenGL 3.3 and the project default Forward+/D3D12. capture_habitat_visual_readability.gd captures context, geometry, close terrain and overview views; PNGs are renderer-prefixed in ignored var/captures/habitat-visual-readability. The local geometry/context/terrain images were inspected. Compatibility is brighter than Forward+; both show distinct resource profiles, workbench scale and tray rims. Existing workbench overlap partially occludes the terrain outlines; no marker is relocated.

The existing capture_habitat_target_feedback.gd also passed through actual native engine picking and GUI dispatch in both renderers: click selects, double-click requests, UI focus suppresses world action and GUI activation remains functional. Automated synthetic native events do not establish human acceptance or physical-controller ergonomics.

No ports were used or reserved, and none require release. No live services, Linux native rendering, export acceptance or deployment were tested locally. PNGs/logs stay ignored; no media/LFS/public upload. Remote checks must be read against the final feature head and reported separately.
