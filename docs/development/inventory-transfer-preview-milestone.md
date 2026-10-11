# Inventory transfer observation preview milestone

Base: origin/dev-master at d41a65fd67aa2aff316a6713bf7dc7f318a1f9e5.
Feature branch: inventory-transfer-preview. Draft PR targets dev-master.

## Behavior and scope

The Inventory panel now groups exact selected item/source, owned destination and
equipment slot IDs beneath the existing destination controls. The nearby section
separately names the owned item/source and selected tray for drop, and the direct
tray item/source and owned destination for collection. Existing controls,
prerequisite tooltips, pending targets and host failure guidance are preserved.

Loaded mass is quoted from own-v3 item_details, including nested contents and
production payload once. Destination load/capacity uses existing container_records.
Missing details, removed selections and hidden world-item loaded mass/tray capacity
are explicitly unavailable. Slot occupancy comes from observed equipped bindings.
There is no projected after-load, fit claim, reach inference from local pose,
automatic transfer or retry.

PlayerInventoryPanel/PlayerInventoryPresentation own disposable display state,
updated only on selection and host observation. Canonical inventory remains owned
by InventorySimulationSystem/SharedInventoryCoordinator on fixed ticks.
Command, schema, persistence, permissions and runtime behavior are unchanged.
No movement/lifecycle expansion, ports, art assets, captures or public media.

## Verification

Windows Godot 4.7.2 bounded runner: import, runtime startup and
player_inventory_transfer_preview_test.gd, player_inventory_handoffs_test.gd,
player_inventory_feedback_test.gd, client_inventory_shell_test.gd all passed.

The new headless fixture instantiates the actual panel in a ScrollContainer and
emits selection signals. It checks source/destination/slot and tray changes,
nested canonical backpack loaded mass, a detached payload observation proving
cargo is not added twice, older observations lacking details, removed and returning
selections, nearby hidden mass, disconnect clearing, zero queued commands and
unchanged full canonical snapshot/input observation. Detached source/payload/tray
fixtures test presentation only; they do not prove those hypothetical world states
are valid canonical snapshots. Existing handoff fixtures exercise real domain
commands and capacity/stale-revision rejection.

The focused inventory-transfer-preview.yml uses pinned Godot, the existing bounded
runner and the same four tests on Windows/Linux, with a ten-minute job deadline.
Existing full CI still applies. Exact pushed-head remote CI is reported separately.
No local Linux, graphical mouse/controller/VR, live multiplayer or packaged artifact
acceptance was run. No merge, integration-branch push or deployment was performed.
The managed worktree remains retained for review.
