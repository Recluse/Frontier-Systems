# Solid-stock autolathe: first implementation

## Player route

1. Extract and refine iron through the existing portable-canister loop. Hand-build a frame, controller, power connector and **autolathe** module (300 g iron). Fit them in Construction and deploy the frame.
2. Connect the frame to a solar generator, directly or through a router. Fabrication uses the existing local energy buffer and cable limits.
3. Manufacture a plate with `craft.plate`, then materialize it as a physical item. Select it in Construction and **Feed selected physical plate / empty part**. A 1 kg plate becomes exactly 1 kg hopper iron. Empty, owned, disconnected machine parts can also be fed for their exact iron bill. This first hopper accepts iron; ore, liquids, gases, tools and occupied containers are rejected.
4. Select an existing machine-part design and **Autolathe: fabricate selected design**. The output appears in frame storage as an unfitted physical item. Use Remove module / printed part to collect it. Add an expander for the trusted equipment designs: resource canister and component-backed handheld extractor.
5. Select an owned empty or iron-containing canister, enter grams and **Eject iron** to recover leftover stock. Empty the hopper and nested storage before recycling its frame. Packing retains all stock and contents.

This is independently implemented first-party MIT behavior. No SS13 code or assets were copied.

## Ownership and contracts

- `SolidMaterialHopper` is a bounded transaction planner. Production owns its material stock; Inventory owns physical identity, nesting and capacity. Commands execute on the authoritative tick with existing authentication, conscious/free-hand, reach, revision and retry rules. No external service is awaited.
- A hopper is an exact existing production cargo record keyed by its physical frame ID. It has all known material keys, only iron nonzero, and a 2,000,000 mg limit. Stock contributes to frame payload mass and the 25 kg fixture conservation budget once. It survives head removal, isolation, packing, player transfer and restart. It shares the existing 32-payload registry limit with portable canisters and plates.
- `machine_autolathe_feed`: machine_id, item_id, expected_revision. The entire owned feed item is consumed atomically; full hoppers or incompatible items leave state untouched. Feeding and ejection are mechanical and do not require electrical power, but require a deployed frame with a functioning autolathe head.
- `machine_autolathe_make`: machine_id, kind, expected_revision. Trusted part/blueprint bills only; operational head, controller and power connector, enabled deployment, adequate local energy, output inventory capacity and registry limits required. Existing equipment creation synchronizes independent tool components. Reject while another processing job is present on the same frame.
- `machine_autolathe_eject`: machine_id, item_id, amount_milligrams, expected_revision. Integer 1..2,000,000 mg into an owned portable canister; capacity and incompatible material checks are atomic.
- Production remains snapshot v6, workshop shape v1. Additive machinery catalog v2 introduces autolathe while preserving every v1 material bill. Restore accepts the original catalog fingerprint only for original kinds, then normalizes to v2. Catalog v1 remains shipped for compatibility. Older binaries cannot read new autolathe saves.
- `production-intent-v1.schema.json` and `machinery-workshop-v1.schema.json` describe the additive intents/kind. The standard command event logging path records these operations. Production profiling exposes `hopper_milligrams`. UI and procedural static-body presentation read authoritative observations.

## Verification and continuation

`tests/godot/autolathe_runtime_test.gd` exercises the finite extraction/refining route, plate ingestion, exact fabrication/recycling bills, physical output, expanded tool construction, full hopper rejection, invalid designs and ejection amounts, disabled/missing heads, reach denial, packed stock, restart and forged contents. It runs automatically on Windows and Linux in CI.

This first slice completes fabrication in one command transaction, like the deployed printer. Timed fabrication queues, multi-material alloys/glass, research-unlocked designs, automatic feed/collection, machine damage and animation remain later slices. Extend the trusted design catalog and hopper policy instead of duplicating inventory or tool owners. Introduce an explicit reserved-material/job migration before adding timed queues; cancellation and restart must preserve reserved matter.
