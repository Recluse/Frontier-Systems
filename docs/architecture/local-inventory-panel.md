# Local inventory interaction panel

## Runnable client interface

`LocalInventoryPanel` adds a **Local inventory demo** section to the existing client HUD. It uses the same theme/layout/section contracts as the other controls. The panel operates on the two logical inventory fixture bodies, independently of the walking preview capsule. Headless bootstrap creates no panel.

The panel shows the actor's directly carried items, loaded mass, active-hand selection, its current job state/progress and command outcome. It supports searching the target backpack/pouch, taking a selected searched item, inserting a selected owned item into the target pouch and placing an owned item in the target's left hand. Additional controls simulate target resistance and movement away/return, cancel/resume the actor's unfinished job, and close a live search.

The own-item list now includes nested possessions for self actions, and [world pickup/drop controls](world-inventory-interactions.md) show reachable tray roots and direct contents. Fitted pickup uses the existing slot selector.

These remain debug local fixture commands. The target-control buttons intentionally simulate another body's reaction for development; they are not production permissions to move another player. [Self inventory controls](self-inventory-actions.md) now add hand switching, slot equipping and owned storage movement. Player physics, a full wearable UI, drag-and-drop inventory and a network client adapter remain pending.

## Observation and command boundary

The widget reads `local_observation(context)`, `own_inventory_observation(context)` and `read_search(context, view_id)` from the registered inventory runtime. It never captures a world/ledger snapshot for display. Own observation v2 includes the bound body's nested possessions, owned container/slot choices, equipment metadata and derived loaded mass. Job/outcome observations are principal-scoped. Search item summaries always come from the live scoped view.

Actions enqueue `InventoryDevelopmentCommand` through `WorldRuntime`; presentation callbacks never invoke ledger mutations. New start intents capture a fresh inventory revision. UI request IDs combine a local panel nonce and request sequence. Pending-start and current-job guards prevent repeated clicks from losing a search grant or submitting duplicate concurrent work.

Search reads refresh at most ten times per second. Expired/revoked views clear item rows and disable Take. Take also revalidates at click time and verifies that its selected stable ID remains in the fresh direct-content result. Insertion/equipment intents are revalidated by the authoritative tick path. The widget stores view IDs and presentation copies, not a durable search grant. Legitimately displayed data can remain visible until the next refresh; mechanical access still checks canonical state.

Stable item selection is preserved during refresh, and unchanged lists are not rebuilt. Theme definitions now include semantic `ItemList` colors, panels and selection styles. Collapsing the HUD section does not cancel jobs; the observer continues refreshing while hidden. Explicit Cancel my job stops unfinished work, while Close live search closes only an existing view. Closing the world clears rows and disables action controls.

Current observation contracts are `inventory-local-observation-v1.schema.json` and `inventory-own-observation-v2.schema.json`, alongside the existing scoped-search schema. The own v1 schema remains historical. They describe internal development observations, not an enabled production endpoint.

## Manual walkthrough

1. Run the normal Godot client. Expand Local inventory demo if necessary.
2. Search target backpack. After two seconds, the list shows the pouch; it does not show the crowbar inside it.
3. Search target pouch separately. Select the crowbar and Take selected searched item; after three seconds it appears among the actor's carried items.
4. Select that owned item and Put selected owned item in target pouch. After two seconds it leaves the actor's list.
5. Start another take and press Target resists before completion. The attempt interrupts without transferring the item. Target steps away/returns tests distance and action-epoch interruption.
6. Let a completed search expire after five seconds; its rows clear. Cancel/resume controls can exercise unfinished/recovered work. Reset sections and theme/layout controls remain available above the customizable stack.

## Section compatibility

Shipped Expanded/Compact profiles now include `hud.inventory`. The section controller performs one additive migration for earlier profiles missing exactly this new registered section: append it expanded while preserving the existing order/collapse flags. The rule applies to saved preferences and local section mods. Otherwise incomplete/unknown profiles still reject, and required status/feedback collapse remains forbidden. Subsequent explicit edits/reset save the new complete profile.

## Verification and remaining work

Windows Godot 4.7.2 import/checks and `local_inventory_panel_test.gd` passed. The test uses the actual UI callbacks and fixed-tick command queue to verify direct versus nested search, repeat-click handling, take/return, expiry, click-time resistance, read-only refresh and shutdown cleanup. Existing habitat layout and section checks passed, including additive profile migration; theme checks cover list palette inheritance. Windows/Ubuntu CI includes the panel test.

Native graphical readability, mouse/keyboard usability, Linux execution and networked multiplayer are not locally verified. Next: self-inventory actions and hand/equipment controls, real body/physical-access producers and production observer/command transport, then further construction/material gameplay.
