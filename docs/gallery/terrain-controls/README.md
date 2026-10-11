# Cooperative terrain controls

Selected native verification capture, inspected for readable controls and cell feedback. It shows a completed 0.250 kg dig/fill cycle: source 1.750 kg, fill 0.250 kg, no remaining own escrow, and an equipped fabricated shovel. No invite keys, host URLs, save paths or player-identifying text are visible; the equipment ID is an in-game generated identifier.

| File | Verified commit | Capture route and demonstrated behavior | Limitations | Author / license / provenance |
| --- | --- | --- | --- | --- |
| [terrain-dig-fill.png](terrain-dig-fill.png) | `92fae3a9d793863c5fae5fd5ef516ebf47a0b98c` (runtime and capture-route source) | `tools/ci/run-first-playable-render-check.ps1 -Route terrain -TimeoutSeconds 120`, pinned Godot 4.7.2; actual finite-material shovel fabrication, inventory equip/select-hand, local physical walking and authenticated dig/fill button signals passed. Native Windows OpenGL Compatibility, NVIDIA RTX 3080 Ti; 1920×1080. | One scripted graphical client; two-peer authorization/retry acceptance is separate native evidence. Labels float above the existing workbench as advisory presentation. No terrain mesh/collision edits, physical terrain inventory, production transfer, VR/controller or human usability acceptance is demonstrated. | Codex verification capture for Valgorithms/Frontier Systems, MIT. Rendered from this project's first-party procedural scene/UI using its existing Godot runtime. No copied creative assets were added and the screenshot was not fabricated or image-edited. |

PNG SHA-256 / Git LFS object ID: `9d4806b4853b766e68d55dce3efb731f89f9f4c0ca6af2548d8ca46222bf90aa`; **252,879 bytes**. The native route's output was viewed directly before selection. Unrelated workstation labels are hidden by the actual Terrain tab; the scripted inspection camera frames both cell labels.

The PNG is stored through Git LFS. `.gdignore` excludes this documentation-only media from game imports/exports, so CI does not treat an LFS pointer as a runtime texture. There is no duplicate capture under `reports/terrain-controls`.

See [milestone contracts and verification](../../development/terrain-controls-milestone.md) for finite ownership, principal-scoped escrow, retry semantics and the complete acceptance limits. Gallery retention does not authorize public website publication.
