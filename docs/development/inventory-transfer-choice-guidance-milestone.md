# Inventory transfer choice guidance milestone

Successor to merged PR95, base 856df31112f23cd4e8c08306152e884adcfc5193.

Assessment: the owned Move preview repeated the destination capacity immediately above it and displayed an equipment slot and occupant that Move does not submit. Browsing was labeled knowledge but did not explicitly distinguish viewing from physical access.

The existing browse label now explains that viewing opens and moves nothing. The existing destination label identifies physical transfer into owned storage. The Move preview retains exact selected item/source/destination, loaded mass and freshness-fenced closure paths; capacity remains once beside the destination selector. Equipment retains its separate slot/occupant guidance. Tray collection keeps its own capacity evidence.

Scope is disposable presentation and directly relevant tests. No controls, schemas, command payloads, authority, transport, automatic open/retry, or predictions change. PR96 machinery recovery and PR97 extraction fixtures are excluded.

Verification pending: pinned Windows checks, paid nested actual-shell keyboard/focus/scroll/conservation, and exact-head Windows/Linux CI. No port or captures needed unless uncertainty arises. Human tutorial gate awaits human; controller/VR, live network and Linux graphical acceptance remain unverified. Coordinator owns merge. Keep the isolated worktree for review.

## Local verification

Pinned Windows Godot 4.7.2 import/startup and player_inventory_transfer_preview_test, player_inventory_closure_test, player_inventory_feedback_test, player_inventory_handoffs_test, player_inventory_usability_test and integrated_panel_layout_test passed in var/ci/transfer-choice. Final paid player_inventory_access_guidance_test passed in var/ci/transfer-choice-final; the final layout test is reported in the handoff.

The paid nested fixture observes closed-ancestor rejection, reopening and actual successful transfer with exact item/provenance and paid material/energy/payload conservation. It now reads/focuses/pages the move/capacity guidance at 1920x1080, 1100x720 and 900x640 while the actual nested paid plate is selected and again during pending equipment identity checks. Complete pending payload, unrelated receipt, host rejection and disconnect uncertainty are covered by the existing actual-shell transfer layout test at desktop/narrow sizes.

The first layout run failed only its old expectation that Move quotes the unused equipment slot; that expectation was updated. No runtime acceptance or fixture resources were changed.

No configuration changes, sockets, captures, public media or deployment. Required remote CI will be checked against the final head; local headless input/layout tests do not establish human/controller/VR or Linux graphical acceptance. PR98 remains draft and Coordinator owns merge.
