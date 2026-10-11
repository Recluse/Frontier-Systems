# Inventory tray handoffs and owned storage milestone

Base: origin/dev-master at `0922ed44498af3eca2bd815e54628756e475be17` (terrain preview merge). Feature branch: `inventory-tray-handoffs`; draft PR targets `dev-master`.

## Behavior

- All-owned browsing includes nested possessions; specific-container browsing shows direct contents. Stable item and storage IDs distinguish otherwise identical labels. Nearby browsing shows direct contents of the selected host-observed tray, with no other-body/private inventory lookup.
- Item, source, destination, equipment/hand slot and tray selections survive observation reordering by ID. Vanished choices clear and remain unselected until explicitly chosen again. A returning container never silently becomes a new command target. Reconnect initializes from a fresh observation.
- Existing pickup, drop and owned move controls explain missing local prerequisites through disabled buttons/tooltips and callback guards. Equipment remains the existing equip/unequip/select/switch-hand contract. Destination load/capacity is labeled as observed; tray capacity, hidden nested contents, slot compatibility, ancestry/tag limits and current reach/revision remain host decisions.
- Submitted self targets are retained separately from refreshed presentation rows, matching existing pickup/drop pending target behavior. Disappearance cannot imply success. Only matching command completion resolves pending feedback. Rejection reports the host reason; disconnect clears disposable targets and states that the outcome is unknown. An unavailable queue creates no pending target.

## Authority and scope

`SharedInventoryCoordinator`/`InventorySimulationSystem` retain canonical ownership, container ancestry, equipment, capacity, revision and receipt validation on fixed simulation ticks. Presentation consumes scoped own-v3/world-v2 observations and sends the existing self/world payloads; no schemas, persistence, permissions or item actions change. The presentation helper is disposable and has no tick or persistence owner. Existing component maintenance, production, world preview, input targeting, habitat and terrain controls are untouched. No art assets, captures, ports or media uploads were created.

## Verification

Windows Godot 4.7.2: bounded runner import and runtime startup, plus `player_inventory_feedback_test.gd`, new `player_inventory_handoffs_test.gd`, `self_inventory_runtime_test.gd`, `world_inventory_runtime_test.gd` and `shared_inventory_coordinator_test.gd` pass. The new test exercises actual nested move, tray drop/collection, insufficient-volume rejection and stale revision rejection through the simulation command queue. It checks owner/receipt preservation on rejection, foreign/private visibility, stable selections, disappeared items, pending targets, unavailable queue and late completion after disconnect. Test worlds and recording transport are isolated; no live services are used.

Existing `.github/workflows/ci.yml` discovers the new test on Windows and Linux. Remote CI must be checked against the final pushed head separately; this document does not claim an older or pending run verifies it. Local Linux, graphical mouse/controller usability, live multiplayer and packaged artifact acceptance were not run. No merge, integration-branch push or deployment is authorized by this milestone.
