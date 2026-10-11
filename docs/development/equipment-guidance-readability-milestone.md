# Equipment guidance readability

Successor to merged PR92, e7ff715ab6e5d504207854293186810d41327ac6.
Scope: existing PlayerInventoryPanel equipment placement and disposable copy.

## Assessment and change

The actual client-shell baseline at 1920x1080 and 1100x720 measured 933 px / 36
lines of Equipment guidance; at 900x640 it measured 985 px / 38 lines, exceeding
the 665 px and 585 px narrow shell viewports. Four closure-path hints each repeated
host-authority and knowledge/access caveats. The guidance was above inventory
browsing, separated from its equipment slot/actions by item and closure controls.

Equipment guidance now immediately precedes the existing slot selector. Compact
path rows retain operation-specific source, destination, slot occupant and closed
ancestor IDs or explicit unknown state. Shared caveats appear once, covering
closure versus physical access, fit, hands, reach, revision, explicit opening and
refresh, and shell exterior versus contents. Equip still excludes the selected
storage destination; unequip still uses the actual slot occupant. Active hand,
selected item/slot, observed bindings, pending submission identity and complete
receipt/rejection/uncertainty feedback remain visible. No controls, automatic
actions, admission rules, owner, transport, schema or canonical runtime change.
Other transfer hints and prerequisite rejection explanations retain their full copy.

## Verification

Pinned Windows Godot 4.7.2 existing runner import/startup and focused checks:
active_hand_tool_feedback_test, player_inventory_access_guidance_test,
player_inventory_transfer_layout_test, player_inventory_feedback_test,
player_inventory_closure_test and integrated_panel_layout_test (each .gd).
Results and exact-head Windows/Linux CI are reported with the PR handoff.

The active-equipment actual-shell regression measures 803 px / 31 lines at all
three sizes with a complete 128-character active item ID, checking wrapped text
and focus reveal. The existing paid access regression now uses the actual client
shell with an injected socket-free remote. It preserves finite extraction,
energy-paid refining/printing, exact material/item provenance, closed and unknown
ancestry, independent selected item and slot occupant, frozen pending observation
and payload, matching receipt, and conservation. New desktop/narrow Tab, focus
and scroll checks preserve selections, queue no command and leave the canonical
world unchanged; the matching paid receipt is fully revealed at 900x640.

Source review and these runtime/layout checks resolve the copy/placement behavior;
no screenshot/video is required. No listener, port lease, public media or deployment.
Human tutorial gate remains awaiting human. Human usability, controller/VR,
live network and Linux graphical acceptance remain unverified.

## Handoff

Branch equipment-guidance-readability targets dev-master in an attached draft PR.
Coordinator owns merge. Retain the managed worktree for review and CI evidence.
Machinery PR93 and transport PR94 files are outside this change.
