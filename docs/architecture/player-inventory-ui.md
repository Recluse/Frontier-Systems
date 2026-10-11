# Player inventory, portable storage and tools

## Cooperative player UI

The cooperative scene now exposes an **Inventory** tab beside **Workstation**, with a draggable sidebar divider and a persistent hand HUD beneath the world view. The desktop defaults to a resizable 1920×1080 window and a 1920×1080 canvas reference; canvas_items/expand handles other aspect ratios. The workstation remains independently scrollable, and each pane fills available space. Existing Default, Terminal and High Contrast themes and local JSON theme mods apply to the cooperative UI through OverlayThemeController.

Inventory shows loose and nested owned possessions. Browse a specific container or double-click a backpack/pouch to browse its direct contents. Inspect condition, loaded mass, volume, storage capacity and canister material. Select a destination to move an unequipped item, or to receive an unequipped slot/world pickup. Equipment compatibility, nesting cycles, weight/volume limits, ownership and consciousness remain canonical checks. Equipped storage retains its contents through pickup/drop and relocation.

Physical closure has its own explicit owned-container selector and Open/Close buttons. Stable selected IDs survive reordering, missing targets and disconnect without retargeting. Detailed v3 observations do not establish closure state; known legacy storage can receive an explicit request whose acceptance remains host-only. Detailed v4 establishes open/closed only from its boolean field. Missing v4 fields, stale/aged frames and disconnect show unavailable state and disable requests. Full owned descendant knowledge remains visible even when physical access is closed; closure is not a lock and grants no world/other-body access.

The panel submits existing `open_container` / `close_container` intents with exact `{container_id, expected_revision}` payloads. The cooperative host admits these two operations through its existing authenticated inventory command route; it derives context from the invite slot and applies unchanged queue checks. One pending command freezes controls; full operation, container, revision and request ID remain readable in wrapped keyboard-focusable feedback. Only a matching command ID, operation and payload resolves closure feedback. Receipts do not predict observed closure; disconnect preserves exact uncertainty and ignores late completion. No automatic retry occurs. The shared owner checks hands, ancestor access and revision, cancels affected work and conserves matter through the authoritative tick path. See [observed container controls milestone](../development/observed-container-controls-milestone.md).

Select an equipment slot to equip/unequip, make a hand active or switch hands. Nearby world storage appears only within server reach. Collect/drop uses the existing world inventory command contract; the UI cannot teleport items or access another player's private storage. Stale concurrent revisions fail visibly and require a fresh selection/retry.

## Tool interaction

New cooperative worlds seed each crew with a backpack and a resource extractor. Crew two retains the existing nested pouch/crowbar fixture. Tools are normal inventory items with trusted catalog tags, condition, mass and equipment compatibility.

Equip the extractor in a hand, make that hand active, carry a canister and approach a resource site. Choose the source and receiving canister, then **Extract 1 kg using active tool**. `tool_extract` uses the same finite deposit/cargo/energy transaction as mounted extraction, plus server-owned active-hand tool validation. A missing, zero-condition, wrong-hand, wrong-tag or grip-reserved tool cannot authorize this action. Existing mounted drill extraction remains usable without the handheld tool; the extractor currently shares its finite drill power/energy budget. Independent batteries, continuous extraction and tool wear are future work.

The crowbar can be equipped and moved, but cooperative door-prying actions are not yet wired into this player panel. It is not advertised as a functioning mining tool.

## Authority and observation contract

`PlayerInventoryPanel` consumes authenticated observations and submits closed `inventory/self`, `inventory/world` or `production/tool_extract` intents. It supplies no body principal, grants, item tags, output quantities or authoritative after-state. The host owns identity and owners revalidate each action during fixed ticks. Pending panel actions are bounded to one; completion/error text remains until another action. Lists rebuild only when relevant inventory/production revisions, carried mass or nearby container visibility change.

The host opts into detailed owned observations: legacy `inventory-own-observation-v3.schema.json` adds inventory_revision, owned container_records (capacity/load) and item_details (trusted tags/dimensions/loaded mass); closure-enabled `inventory-own-observation-v4.schema.json` additionally supplies container `is_open`. Existing local callers keep v2 by default through `own_inventory_observation(context, include_details=false)`. Canonical closure persistence is documented in [physical inventory closure](closed-inventory-containers.md); this UI adds no snapshot version. Presentation records remain disposable, and production payload mass is counted once.

## Saved worlds and verification status

The component section integrates the observed prerequisite helper for fabrication, fit, detach and recycling. It distinguishes owned loose parts from mounted parts, quotes only observed stock/energy specifications, and shows current capability availability. Blueprint/component/mount/loose-part selections preserve stable IDs as unavailable when records disappear; changing the inspected tool requires explicit component/mount selection. All component pickers freeze while an action is pending, and pending component IDs/revisions remain pinned until the matching host receipt. See [inventory component prerequisites](../development/inventory-component-prerequisites-milestone.md) for authority and verification scope.

New equipment is seeded **only for new cooperative worlds**. Existing saves preserve their items and are not silently granted tools/backpacks. Choose a new `-WorldName` to see the starter kit while retaining old worlds. Client and host should run the same source revision; protocol negotiation for mixed builds is future work.

Component presentation now wraps full selected IDs outside clipped pickers, flows action rows within the pane, follows keyboard focus while scrolling, and reveals labeled exact pending fields after layout settles. Focus the Inventory scroll pane to navigate long observed prerequisites with the configured UI Up/Down bindings. Component pending actions also retire item-list keyboard focus until the matching receipt. See [inventory panel usability](../development/inventory-panel-usability-milestone.md) for the seven focused Windows checks and native Default-theme engine fixture at desktop/narrow pane sizes. This evidence uses injected input and real paid domain commands; integrated client/network, human, controller/VR and Linux graphical acceptance remain unverified. Earlier first-playable screenshots describe their own revisions.

## Cursor and controls

Equipment controls and hand-tool extraction show the host-observed active hand
and equipped item separately from selected inventory item and equipment slot.
Missing, older, disconnected or five-second non-advancing observations remove
these active-equipment claims. Pending commands require their matching receipt;
equipment display follows fresh observations and predicts no engineering readiness.
See [active hand/tool feedback](../development/active-hand-tool-feedback-milestone.md)
for the presentation-only freshness boundary and actual-shell verification.

Hold Left Alt (default) to access panels during navigation. The Settings tab provides rebinding and sensitivity; see [player controls](player-controls.md). Inventory, hand and tool shortcuts use the same configured action registry.

Transfer selections now show exact observed source, owned destination and equipment
slot IDs together, with loaded item mass and destination load/capacity. Tray drop and
collection have separate summaries so their different destinations stay explicit.
Unavailable observation fields remain unavailable; the panel predicts no fit or
authoritative outcome. See [inventory transfer preview](../development/inventory-transfer-preview-milestone.md).

Transfer/capacity summaries, tray status and host receipts accept keyboard focus.
Use Tab/Shift+Tab to review them and Up/Down or Page Up/Page Down to scroll
the Inventory pane while keeping guidance focused, including receipts taller
than the pane. Enabled action buttons remain in the same relative order and
focus-following scrolling reveals them. See [transfer layout verification](../development/inventory-transfer-layout-milestone.md).

Maintenance target feedback now identifies the inspected item, selected repair
part and loose part separately from the host-observed mount occupant. Repair and
work intents retain exact submitted fields through matching receipts. Work source,
canister and cycle selections are distinct from an existing host reservation and
its completed counts. Missing inventory frames and disconnect remove these scoped
claims; no after-state, compatibility or reach is inferred. See
[maintenance target feedback](../development/tool-maintenance-target-feedback-milestone.md)
for actual-panel authority, keyboard review and verification limits.

Owned transfer hints quote the exact v4 boolean closure path from the same scoped
observation and existing five-second/revision/tick freshness fence used by closure
and active-equipment guidance. A closed source or destination ancestor is named
by stable ID in the preview and existing action prerequisite. Browsing known
descendants stays available. Unknown, incomplete or legacy closure does not mean
open and does not replace host validation. An observed open path is only closure
evidence, never a promise of hands, reach, capacity or transfer success. Moving a
closed shell checks its containing path, not the shell's contents. No hint opens,
retries or changes a target or pending request. See
[owned nested access guidance](../development/owned-nested-transfer-access-guidance-milestone.md).
