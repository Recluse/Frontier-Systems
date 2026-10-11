# Resource unloading feedback milestone

LocalProductionPanel identifies the receiving destination as the current world/region production.store, the shared workstation stock actually used by unload_cargo. Existing observations contain no receiving station instance ID; guidance explicitly reports that identity unavailable and explains that the power picker does not choose the unload destination. No capacity, fit or completion is inferred.

The Gather / carry section shows selected stable canister/material IDs, exact intended milligrams, scoped host-observed canister contents and selected material stock. Missing fields invalidate the observation rather than becoming empty cargo or zero stock. Removed IDs remain selected and disabled until the same ID returns or the player explicitly selects another. The unchanged command contract is checked against currently observed IDs before submission.

Cargo feedback pins a detached submitted payload, expected revision and receiving store while pending. Current intended controls remain distinct; changing them cannot retarget queued work. The host receipt names the exact command ID, operation, carrier, material, amount and pinned store on success or rejection. Disconnect preserves the exact unknown outcome; a late receipt cannot establish success or submit retries. Guidance supports keyboard focus and Page Up / Down within the existing bounded task scroll.

ProductionSimulationSystem owns tick cadence, resources, conservation and material provenance; InventorySimulationSystem owns physical items and access. This client presentation adds no persistence, schema, network, controller, movement, queue or canonical rule changes and no external service or art asset. Existing failure handling and profiling remain authoritative. First-party code, tests and documentation are MIT.

## Verification

resource_unloading_feedback_test.gd exercises the actual panel and real finite extraction/unloading owner commands, exact material conservation and underflow rejection, changed/removed pending selections, malformed observations, returning IDs, exact receipt, disconnect/late receipt and focus/scroll. Existing canister extraction, workstation resource view and production navigation regressions run through the pinned bounded Godot runner. Local logs and JUnit are ignored under var/ci/unload-*.

Windows/Linux exact-head CI is reported through the attached draft PR. Headless controls do not establish graphical human usability, controller/VR, live multiplayer or deployed behavior. No merge, release, deployment or external send is authorized; retain the isolated managed worktree for review.