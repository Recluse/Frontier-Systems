# Owned equipment access guidance milestone

Successor to merged PR88 (d50f702d2fe67e129db2e605a2db4492bdaf1453).
Scope: PlayerInventoryPresentation, existing inventory panel hints and its paid
nested-item regression. Canonical inventory ownership, tick processing, schemas,
persistence, transport and action prerequisites are unchanged.

## Behavior and assessment

The existing transfer blocker already covers equip source and unequip source and
destination. This milestone adds operation-specific explanations rather than
changing admission. Equip uses the selected item's containing path, the body root
and selected slot; the move destination selection is unused. Unequip identifies
the selected slot's actual observed occupant, its source and the selected owned
destination, independently of the selected inventory item. Hand selection and
switching do not move items or open containers.

Hints quote only the existing bounded owned v4 boolean path and five-second,
revision/tick freshness fence. Unknown, legacy, incomplete, older and aged
evidence remains unknown. Closed shell exterior access stays distinct from
contained-item access. Open paths never promise fit, hands, reach or acceptance.
No new controls, open/retry behavior or optimistic equipment state are added.

Submission-time slot occupant and active-hand observations are detached text
retained in existing pending/receipt feedback. New observations may show different
equipment but cannot rewrite that submitted identity. Command payloads are unchanged.

## Verification

The existing no-port player_inventory_access_guidance_test uses finite extraction,
energy-paid refining/printing and a real physical plate. New cases exercise
closed-ancestor equip rejection, reopen/equip, closed unequip destination rejection,
hand selection/switch without ledger movement, closed-shell same-root equipment
changes, and a pending unequip whose newer observed slot occupant differs.
Rejections preserve the exact owner; equipment preserves paid material, energy
and payload. Existing incomplete/stale/legacy/aged checks also cover equipment hints.

Run the versioned Windows Godot 4.7.2 runner with these nine tests:
player_inventory_access_guidance_test, active_hand_tool_feedback_test,
player_inventory_closure_test, player_inventory_feedback_test,
player_inventory_handoffs_test, player_inventory_transfer_layout_test,
player_inventory_transfer_preview_test, player_inventory_usability_test,
integrated_panel_layout_test (each with .gd).
Logs/JUnit: ignored var/ci/equipment-access-verified.
Final local and exact-head Windows/Linux CI results are reported with the handoff.

Source review, runtime regression and actual-shell desktop/narrow focus/scroll
layout tests establish this presentation change without captures. No listener,
fixed port, external service, public media or deployment is used. Human tutorial
gate remains awaiting human; human/controller/VR, live network and Linux graphical
acceptance are unverified.

## Handoff

Managed worktree inventory-equipment-access; branch
inventory-equipment-access-guidance; draft PR92 targets dev-master.
Coordinator owns merge. Retain the worktree for review and exact-head evidence.
Other concurrent machinery and disconnect-recovery scopes are untouched.