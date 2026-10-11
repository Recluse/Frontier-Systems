# World context overview - internal candidate only

Unedited root-window gameplay capture from verified source `ec0df251d856002b5620b81c39e0c9673c78ddd8` (base `98b5be2`). This is internal evaluation material, not approved for public showcase, website/social distribution or a claim of production readiness.

| File | Verified commit | Capture route and demonstrated behavior | Limitations | Author / license / provenance |
| --- | --- | --- | --- | --- |
| context-overview.png | ec0df251d856002b5620b81c39e0c9673c78ddd8 | `capture_world_context.gd`, 1440x900 actual root window; connected host projection, separated refinery/tray/terrain/resource cards with true-anchor leaders and complete observed values/instructions | Automated Windows desktop evidence, initial fixture, selected inventory overlay row; this frame does not demonstrate native selection, movement or human/VR/controller/Linux graphical acceptance | Codex capture of first-party MIT geometry/UI, Godot 4.7.2 default font; no added third-party creative assets |

The complete graphical route additionally verifies native root-window picking, the unchanged selected-item card, camera movement, 960x700 root resize, hidden labels, accepted pickup/drop, pending-before-ack, stale-revision rejection and actual disconnect. These additional frames remain ignored under `var/captures/world-context`: rejection/debug state and scaled narrow-window UI make them less suitable as representative gallery candidates. No secrets, personal data, imported creative assets, external service data or synthetic resource grants appear in the retained frame.

Reproduce with Godot `--path . --xr-mode off --audio-driver Dummy --script res://tools/godot/capture_world_context.gd --resolution 1440x900`. Separate port 27864 must be free; the tool fails on bind rather than stopping another process, uses ephemeral invite-authenticated in-memory host/client/world state, clears external event configuration and frees them at exit. No gameplay images were published externally.

The original is retained in ignored `var/captures/world-context/selected.png`. The gallery PNG uses Git LFS; `.gdignore` excludes it from Godot import.
