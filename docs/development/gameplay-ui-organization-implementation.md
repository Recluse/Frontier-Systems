# Gameplay UI organization implementation

Presentation milestone following the owner request in `gameplay-ui-organization-milestone.md`.

## Scope

The integrated FirstPlayable client starts with its interaction drawer closed. Persistent hands, connection and command uncertainty remain beside the scene; inventory/equipment, workstation and construction share one on-demand drawer. World selection opens the relevant drawer after its layout settles without stealing keyboard focus. Closing a focused drawer returns focus to its visible toggle. Inventory/settings bindings open or close their panels; Escape closes the drawer.

Help, expanded target instructions and floating world captions start collapsed. Settings provides explicit caption/guidance toggles plus theme, camera and checkpoint controls. Inventory owns tray actions. Selected names and markers remain available with compact targeting. The bounded persistent feedback area mirrors existing receipts and retains production disconnect request/recipe/revision details across panel recreation; its keyboard scroll exposes long text. Panel instances, stable IDs and pending dictionaries survive drawer navigation. No canonical simulation, transport authorization or persistence schema changes.

## Provenance

Independently authored Godot layout and controls under the project MIT license. Behavioral requirements come from the owner-authored milestone's Stationeers and SS13 notes. No upstream source, text, bindings or artwork copied; no Baystation source consulted; no generative art used. Existing procedural engine visuals and project theme are retained.

## Acceptance record

Windows Godot `4.7.2.stable.official.ed1daf0bf`, repository bounded import/startup and focused checks passed during implementation:

- `gameplay_ui_organization_test.gd`: actual bootstrap at 1920x1080 and 1100x700; scene occupies at least 55% of each dimension with the drawer open or closed, the inspected workstation stays in the scene camera, only the chosen panel is visible, hands/connection persist, focus returns on close, long record/error text scrolls, and transfer/production request recovery survives reconnect without replay. Canonical snapshots stay unchanged by navigation, rejection and abandoned intents.
- `integrated_panel_layout_test.gd`, `engineering_guidance_layout_test.gd`, `engineering_loop_shell_test.gd`: real domain fixtures, nested focus/scroll, paid extraction/refining/materialization/construction, exact targets and checkpoint outcomes. The integrated layout and inventory shell use 1100x700 alongside desktop acceptance.
- `client_inventory_shell_test.gd`, `active_hand_tool_feedback_test.gd`, `player_inventory_access_guidance_test.gd`, `player_inventory_transfer_layout_test.gd`, `machinery_operation_feedback_test.gd`, `checkpoint_confirmation_feedback_test.gd`, `manual_reconnect_adapter_test.gd`, `reconnect_workstation_navigation_test.gd`, `world_pointer_picking_test.gd`, `selected_target_controls_test.gd`, `habitat_target_feedback_test.gd`, `desktop_controls_help_test.gd`: existing equipment, actual input routing, receipt, recovery, targeting and help contracts. Expanded targeting retains its separate opt-in acceptance.

Native `gl_compatibility` captures use the versioned `capture-integrated-panels.ps1 -Route organization` runner, actual client bootstrap and procedural engine geometry, injected keyboard/selection and a recording transport. Internal PNGs/log/HEAD-and-dirty manifest live in ignored `var/ci/integrated-panel-render`. Desktop/narrow closed, workstation, transfer pending, long rejection, construction and reconnect views were inspected; final clean-head capture provenance is recorded by that runner. No ports were bound and no public media or deployment was performed.

The full required CI run also identified two existing fixtures that still assumed always-visible controls. `held_look_ui_activation_test.gd` now opens Settings to click the actual camera button, then Construction before testing held-look editor activation. `player_movement_feedback_test.gd` checks the visible persistent receipt and bounded scroll viewport while the drawer is closed. Both focused checks passed on Windows after adaptation; their original input/authority assertions remain intact.

PR #106 packages the milestone; exact-head required CI is checked before coordinator handoff. Graphical first-person live-network runners were adapted to open the drawer explicitly but were not run. Automated native rendering and domain tests do not establish human usability, physical keyboard/controller/VR, live-network recovery or Linux graphical acceptance. Human usability remains unverified until a player is available.
