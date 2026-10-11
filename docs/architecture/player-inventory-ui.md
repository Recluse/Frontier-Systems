# Player inventory, portable storage and tools

## Cooperative player UI

The cooperative scene now exposes an **Inventory** tab beside **Workstation**, with a draggable sidebar divider and a persistent hand HUD beneath the world view. The desktop defaults to a resizable 1920×1080 window and a 1920×1080 canvas reference; canvas_items/expand handles other aspect ratios. The workstation remains independently scrollable, and each pane fills available space. Existing Default, Terminal and High Contrast themes and local JSON theme mods apply to the cooperative UI through OverlayThemeController.

Inventory shows loose and nested owned possessions. Browse a specific container or double-click a backpack/pouch to open its direct contents. Inspect condition, loaded mass, volume, storage capacity and canister material. Select a destination to move an unequipped item, or to receive an unequipped slot/world pickup. Equipment compatibility, nesting cycles, weight/volume limits, ownership and consciousness remain canonical checks. Equipped storage retains its contents through pickup/drop and relocation.

Select an equipment slot to equip/unequip, make a hand active or switch hands. Nearby world storage appears only within server reach. Collect/drop uses the existing world inventory command contract; the UI cannot teleport items or access another player's private storage. Stale concurrent revisions fail visibly and require a fresh selection/retry.

## Tool interaction

New cooperative worlds seed each crew with a backpack and a resource extractor. Crew two retains the existing nested pouch/crowbar fixture. Tools are normal inventory items with trusted catalog tags, condition, mass and equipment compatibility.

Equip the extractor in a hand, make that hand active, carry a canister and approach a resource site. Choose the source and receiving canister, then **Extract 1 kg using active tool**. `tool_extract` uses the same finite deposit/cargo/energy transaction as mounted extraction, plus server-owned active-hand tool validation. A missing, zero-condition, wrong-hand, wrong-tag or grip-reserved tool cannot authorize this action. Existing mounted drill extraction remains usable without the handheld tool; the extractor currently shares its finite drill power/energy budget. Independent batteries, continuous extraction and tool wear are future work.

The crowbar can be equipped and moved, but cooperative door-prying actions are not yet wired into this player panel. It is not advertised as a functioning mining tool.

## Authority and observation contract

`PlayerInventoryPanel` consumes authenticated observations and submits closed `inventory/self`, `inventory/world` or `production/tool_extract` intents. It supplies no body principal, grants, item tags, output quantities or authoritative after-state. The host owns identity and owners revalidate each action during fixed ticks. Pending panel actions are bounded to one; completion/error text remains until another action. Lists rebuild only when relevant inventory/production revisions, carried mass or nearby container visibility change.

The host opts into `inventory-own-observation-v3.schema.json`: v2 fields plus inventory_revision, owned container_records (capacity/load) and item_details (trusted tags/dimensions/loaded mass). Existing local callers keep v2 by default through `own_inventory_observation(context, include_details=false)`. No snapshot version change is needed. Presentation records remain disposable, and production payload mass is counted once.

## Saved worlds and verification status

The component section integrates the observed prerequisite helper for fabrication, fit, detach and recycling. It distinguishes owned loose parts from mounted parts, quotes only observed stock/energy specifications, and shows current capability availability. Blueprint/component/mount/loose-part selections preserve stable IDs as unavailable when records disappear; changing the inspected tool requires explicit component/mount selection. All component pickers freeze while an action is pending, and pending component IDs/revisions remain pinned until the matching host receipt. See [inventory component prerequisites](../development/inventory-component-prerequisites-milestone.md) for authority and verification scope.

New equipment is seeded **only for new cooperative worlds**. Existing saves preserve their items and are not silently granted tools/backpacks. Choose a new `-WorldName` to see the starter kit while retaining old worlds. Client and host should run the same source revision; protocol negotiation for mixed builds is future work.

Component presentation now wraps full selected IDs outside clipped pickers, flows action rows within the pane, follows keyboard focus while scrolling, and reveals labeled exact pending fields after layout settles. Focus the Inventory scroll pane to navigate long observed prerequisites with the configured UI Up/Down bindings. Component pending actions also retire item-list keyboard focus until the matching receipt. See [inventory panel usability](../development/inventory-panel-usability-milestone.md) for the seven focused Windows checks and native Default-theme engine fixture at desktop/narrow pane sizes. This evidence uses injected input and real paid domain commands; integrated client/network, human, controller/VR and Linux graphical acceptance remain unverified. Earlier first-playable screenshots describe their own revisions.

## Cursor and controls

Hold Left Alt (default) to access panels during navigation. The Settings tab provides rebinding and sensitivity; see [player controls](player-controls.md). Inventory, hand and tool shortcuts use the same configured action registry.
