# Environmental extraction before terrain mining

The first playable prioritizes extracting resources from finite environmental sources into portable containers, transporting them and refining their contents. Terrain deformation and SS13-inspired excavation follow this route. All implementation is first-party; no reference game's code or assets are used.

## Implemented interaction

The production HUD defaults to **Extract, store, refine and recycle**. Select an owned canister and a mass up to 1 kg. Click an iron ore, ice or regolith source in the habitat preview to select it; double-click requests extraction into the selected canister. The HUD button uses the same command. Exhausted sources disappear and stop accepting mouse picking.

`extract` requires exact `deposit_id`, `carrier_id`, `amount_milligrams` and `expected_revision` fields. The fixed-tick handler resolves source reach through the inventory actor's canonical logical position. Sources have stable fixture positions relative to the inventory preview origin. The actor must be conscious, have an available unreserved manipulator and own the physical receiving canister. A client cannot supply yield, source position or an authoritative after-state.

Extraction prepares one candidate that debits source mass, adds exactly that mass to the canister and spends finite energy at 250 J/kg rounded upward to whole joules, with a minimum 1 J application cost. The drill power flag must be enabled. Single-material compatibility, carrier capacity, gas pressure, carried mass and equipment constraints are validated before committing any change. Failure changes neither source, receiver, energy nor receipt history.

This initial extraction action is a discrete fixed-tick transfer, not a sustained drilling animation or timed hand-tool task. The existing timed mounted-drill `mine` command remains available internally for development, but the primary HUD route no longer mines directly into refinery stock. Timed/manual extraction, handheld tools and interruption remain later integration work.

## Transport and refining

The receiver is a real inventory canister with stable item identity. Drop, pickup and transfer continue to move its payload through that identity. Bring it within workstation reach and unload its material, then run a trusted recipe. Refining still reserves feedstock and completes in timed powered batches. Recycling and crafting use the recovered depot material through the same conservation owner.

Owned canister contents and shared production status are readable away from the workstation. The HUD distinguishes workstation actions from extraction: source reach enables extraction independently, while processing, unloading, construction and other station actions require workstation reach. Other players' cargo is omitted. The desktop scene enables its development walker-to-inventory bridge by default, including position sampling in overview mode; the **Link inventory actor to walker** checkbox can disable it for debugging. See [the local guide and movement binding](local-production-guide.md). This paragraph describes the legacy lab. The cooperative scene uses authenticated bounded host movement; detailed collision authority remains future work.

## Persistence and limitations

Extraction uses production v2's existing source, cargo, energy and receipt records; it adds no new snapshot fields. Previously reserved mounted-drill mass cannot also be extracted because it has already been removed from available source stock. Saved depletion is retained. Terrain cells and geometry topology are unchanged.

Preview ray picking requests an action; it does not bypass server-owned reach. Fixture sources currently share the drill power and energy budget, rather than an independently carried extractor power pack. Detailed source composition, extraction rate, thermal effects, tool wear, 3D hose routing and terrain mining are future work.

Windows two-client extraction, foreign-carrier and capacity rejection, retained retry and restart checks now pass. The graphical guided route also passes; see [acceptance evidence](../development/first-playable-acceptance.md).
