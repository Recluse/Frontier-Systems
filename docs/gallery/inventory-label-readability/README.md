# Selected inventory label captures

Unedited first-party Windows Godot 4.7.2/D3D12 captures from source `676e7a36c1f0d0522de2d7df590784e29af8d38f`, integrated on base `76671e63384663f73aa08c5a1d41dbcb0f9b19d2`. MIT project geometry/UI, engine default font; no added third-party creative assets. Stored through Git LFS and excluded from Godot import by `.gdignore`.

- `world-selection.png`: actual root-window injected click selects the yellow world canister. Opaque item/root/distance card is readable above the surrounding text; leader endpoint identifies that proxy.
- `camera-moved.png`: same selection and camera shifted 0.7 m; leader follows the actual projected proxy without an observation rebuild.

Reproduce with Godot `--path . --script res://tools/godot/capture_inventory_label.gd --resolution 1440x900`. Port 27862 must be free; the tool refuses a busy port, uses an ephemeral invite-authenticated loopback host, clears event service configuration, and frees its host/client/world at exit. Outputs go to ignored `var/captures/inventory-label`.

These are automated graphical evidence, not human/VR/controller or Linux graphical acceptance. World workstation/terrain/tray text remains cluttered. The screen leader does not claim occlusion, line of sight, physical item coordinates or authoritative reach. Pending pickup/drop, host stale-revision rejection and disconnect also pass in this route, but are not the subject of these retained frames.
