# Owned nested transfer access guidance milestone

Scope: disposable owned-inventory guidance for proposed physical transfers, using exact v4 host observations and the existing freshness fence. Known descendant contents remain browsable when closed ancestors block access. The host remains the only acceptance authority.

No canonical state, schema, transport, persistence, automatic open/retry, other-body UI or world-container closure controls change. Pending identity and stable targets retain existing behavior.

Acceptance: closed source/destination ancestor hints, unavailable/stale/legacy closure uncertainty, real paid nested rejection/reopen transfers with item/provenance conservation, and existing keyboard/narrow layout checks. No listeners required. Human tutorial readiness, controller/VR and Linux graphical acceptance remain unverified.

## Implemented behavior

PlayerInventoryPresentation quotes a bounded path of exact owned v4 boolean observations, using existing item and owned-container lookups. The same evidence helper supplies transfer previews and existing action prerequisites; it cannot change canonical closure or authorize a transfer. A known closed source/destination container or ancestor is named by stable ID. The panel passes its existing active-equipment/closure freshness-fenced observation and refreshes hints on expiry or an otherwise identical new frame. Missing, malformed, legacy, older, cyclic or aged observations mean unknown. Moving a closed shell checks its containing path rather than accessing its contents.

The canonical inventory owner, tick processing, schema/save versions, transport and receipt matching are unchanged. No new listeners, controls, assets or external services were introduced. No changes touch MachineryPanel or durable checkpoint acceptance owned by PR87/PR82.

## Verification

Windows Godot 4.7.2 import/startup and eight scoped tests passed. The final helper/panel code passed player_inventory_closure_test, player_inventory_feedback_test, player_inventory_handoffs_test, player_inventory_transfer_layout_test, player_inventory_transfer_preview_test, player_inventory_usability_test and integrated_panel_layout_test with the versioned runner and ignored logs/JUnit in var/ci/owned-access-verified. The new player_inventory_access_guidance_test passed after the final test-only monotonic-clock correction with logs/JUnit in var/ci/owned-access-monotonic.

Reproduce with tools/ci/run-godot-checks.ps1 -Godot <pinned Godot 4.7.2 console executable> -TestNames <the eight filenames above with .gd> -TestTimeoutSeconds 120. No listeners are used.

The new fixture picks up the existing target canister, extracts two finite ore batches, pays refining/printing costs and materializes a physical plate, then moves the starter crowbar out of the pouch to make space through an actual inventory command. It adds no fixture resources or capacity grants. Closed-ancestor removal/insertion fails atomically; reopening permits both transfers. All exact item IDs/provenance fields and paid payload/material/energy fields are conserved except the intended plate location. The same panel keeps known descendants browsable while showing the ancestor blocker. Regressions cover earlier revisions, missing/malformed fields, absent paths/root ownership, cyclic paths, legacy v3, actual monotonic expiry, unavailable observations, and a closed shell's exterior.

Initial fixture iterations failed because the canister was still in the tray, pouch volume was occupied, and a SceneTree timer resumed before the monotonic freshness deadline. Those test setup assumptions were corrected using actual commands and the panel clock; no runtime authority/capacity was changed to make the test pass.

Existing closure/receipt tests preserve stable targets, pending exact operation/payload identity, disconnect uncertainty and no automatic retry. Existing real-shell layout tests verify focus/scroll/wrapping at desktop and narrow widths. Source review and runtime/layout checks resolve the scoped behavior without captures. Human tutorial readiness, live network/service, physical controller/VR and Linux graphical acceptance remain unverified. Exact-head remote CI is reported separately; local checks do not establish CI or release readiness.

## Handoff

Managed worktree and branch owned-inventory-access-guidance; draft PR #88 targets dev-master. Leave merge to Coordinator. Retain worktree for review; no release, deployment, public media or AI art.
