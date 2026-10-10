# Local grip controls

## Client composition

`LocalGripPanel` is a disposable native Godot control under `src/presentation/locomotion/`. The existing `LocalInventoryPanel` composes it inside `hud.inventory`; appearance themes and section collapse/reordering apply without adding a new section or migrating layout preferences. It uses first-party labels and built-in UI widgets without new creative dependencies.

The body picker selects the actor or target **development principal**. This is the existing debug-only two-body fixture, not an ability to control another player in production. The panel observes the selected body's hands and sustained sessions, plus the public logical fixture targets. It does not read world snapshots, inspect inventory item contents or write canonical state directly.

## Available actions

- Pick a target, a free profile hand and a supported action; submit a grip/join intent.
- Join the existing target session and its action when another body has already started one. Crate handling defaults to `move_world_object`; ladder handling defaults to `pull_along`.
- Release a selected session belonging to the chosen body, including paused recovered sessions.
- Resume a paused **solo** session after fresh checks. Cooperative recovery requires individual releases and new explicit joins; group resume is disabled.

Status distinguishes free/occupied/reserved hands and paused, waiting/unavailable or capability-ready sessions. Capability-ready means the current prototype gate passes; it does not report object movement. Explanatory text identifies the fixture's current behavior: grips reserve hands and evaluate capability, while body/object forces remain pending.

Join disables when no free hand exists, the target is outside logical reach, that body already belongs to the target session or the target session is paused. Release remains available for owned sessions without contact. Resume requires one participant, paused state and reachable target. The server derives all physical observations and authorizes the principal again when the queued command applies.

## Observations and pending commands

The scoped `local_grip_observation()` emits v2: `schema_version`, `grip_revision`, `sessions`, `hands` and `targets`. Session projections include only this body's memberships and own hand IDs, with a participant count rather than other people's hand/inventory records. Hand records report `free`, `occupied` or `reserved`. Public development target records include reach, supported actions and existing session identity/action/paused state so independent contributors can join one target owner. Out-of-reach fixture targets remain listed but unavailable. This surface remains closed to production sessions.

The schema is `inventory-grip-observation-v2.schema.json`; v1 consumers may ignore the additive hands/targets data, but new consumers must expect v2. The observation is derived and never persisted as canonical state. Refresh runs at most 10 Hz and also occurs at click time. Selection persists by stable IDs. Native theme styles are inherited from the inventory section.

One outstanding command is permitted per panel. Pending commands disable body/action selectors and buttons, preventing repeated clicks from duplicating an intent. Unique command IDs and session IDs use the panel nonce and the world's local sequence. The command-completion signal clears only this panel's pending request and reports acceptance or rejection. Server revision/receipt checks arbitrate other panels or inventory actions; UI disabling is not authority. Closing the world clears observations/selections/pending state and disables controls.

## Verification

Windows headless import and `local_grip_panel_test.gd` cover parent composition, read-only refresh, repeated-click guards, body scoping, cooperative session joining, waiting/ready status, explicit release, ladder action selection, paused solo recovery/resume, click-time contact loss and world-close cleanup. Runtime and existing inventory/presentation regressions are checked separately. CI includes the focused script on Windows/Ubuntu; Linux execution, remote CI, graphical/input QA and real grip physics remain pending.
