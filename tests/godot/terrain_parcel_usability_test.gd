extends "res://tests/godot/terrain_portable_test.gd"

var _panel: TerrainControlsPanel
var _remote: ObservedRemote


func _run() -> void:
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	_bind(world)
	_context = _session("local-inventory-actor", ["inventory.operate", "terrain.operate"])
	_check(world.start_simulation().is_success, "world starts")
	_remote = ObservedRemote.new()
	root.add_child(_remote)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 720)
	root.add_child(viewport)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(320, 720)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	viewport.add_child(scroll)
	_panel = TerrainControlsPanel.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_panel)
	_panel.configure(_remote)
	_observe()
	_check(_panel._lifecycle.text.contains("None observed.") and _panel._return.disabled, "empty authenticated lifecycle")
	for _batch in range(3):
		_move([-3000, 0, -1000])
		_produce("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		_move([0, 0, 0])
		_produce("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		_produce("process", {"recipe_id": "refine.iron"})
		for _tick in range(120): _step()
	_produce("fabricate_equipment", {"blueprint_id": "equipment.shovel"})
	_shovel = _production.capture_snapshot().value["structures"].keys()[0]
	_self("equip", _shovel, "body.human-2", "hand.left")
	_self("select_hand", "", "", "hand.left")
	_send("excavate", _payload("terrain.dirt.source", 777777), _next())
	_send("excavate", _payload("terrain.dirt.source", 123456), _next())
	_observe()
	_check(_panel._lifecycle.text.contains("777777 mg (0.777777 kg)") and _panel._lifecycle.text.contains("material.dirt"), "exact observed material and odd mass")
	_check(_panel._selected_escrow_id == "terrain-transfer-1" and not _panel._claim.disabled, "excavation can be claimed")
	var reordered: Dictionary = _view()
	var transfers: Dictionary = reordered["terrain"]["transfers"]
	reordered["terrain"]["transfers"] = {"terrain-transfer-2": transfers["terrain-transfer-2"], "terrain-transfer-1": transfers["terrain-transfer-1"]}
	_panel.observe(reordered)
	_check(_panel._escrow.get_item_metadata(_panel._escrow.selected) == "terrain-transfer-1", "reorder preserves stable escrow identity")
	_claim(_claim_payload("terrain-transfer-1"), 1)
	_check(_last.is_success, "actual claim settles")
	_observe()
	_check(_panel._selected_escrow_id == "terrain-transfer-1" and _panel._escrow.selected == -1 and _panel._claim.disabled and _panel._fill.disabled, "removed escrow never silently targets remaining transfer")
	_check(_panel._lifecycle.text.contains("terrain-transfer-1 · no longer observed"), "removed escrow is explained")
	_check(not _panel._return.disabled and _panel._selected_parcel_id == "terrain-item-1", "actual carried claim enables return")
	var blocked: Dictionary = _view()
	blocked["terrain"]["return_ready"] = false
	blocked["terrain"]["return_message"] = "An unreserved manipulator is required."
	_panel.observe(blocked)
	_check(_panel._return.disabled and _panel._lifecycle.text.contains(blocked["terrain"]["return_message"]), "observed host return prerequisite is shown verbatim")
	_observe()
	var actor: AuthenticatedCommandContext = _context
	_world_move("drop", "terrain-item-1", "", "")
	_observe()
	_check(_panel._return.disabled and _panel._selected_parcel_id == "terrain-item-1", "tray parcel is not returnable and stable item remains selected")
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_world_move("pickup", "terrain-item-1", "body.human-1", "")
	_observe()
	_check(not _panel._return.disabled and _panel._lifecycle.text.contains("777777 mg"), "actual new holder sees complete parcel")
	var before: Dictionary = _canonical()
	_panel._return.emit_signal("pressed")
	var original: Dictionary = _remote.terrain_pending_intent()
	_check(original["operation"] == "return" and original["payload"]["item_id"] == "terrain-item-1" and _panel._lifecycle.text.contains("Unresolved return #1"), "real button freezes original ID/revision and displays intent")
	_check(_panel._return.disabled and _panel._claim.disabled and _panel._fill.disabled and _canonical() == before, "presentation queues only; never mutates world")
	_remote.command_completed.emit(_remote.sent, ServiceResult.failure(&"stale_revision", "Observed inventory revision changed."))
	_check(_panel._feedback.text.begins_with("Rejected stale_revision") and _panel._lifecycle.text.contains(str(original["payload"]["expected_inventory_revision"])), "rejection preserves original revision while unresolved")
	_remote._terrain_record = {}
	_remote.connection_closed.emit("test")
	_check(_panel._retry.disabled and _panel._return.disabled and _panel._lifecycle.text.contains("unknown, not confirmed empty"), "disconnect clears scoped data but describes uncertainty")
	_check(_remote.terrain_pending_intent() == original and _panel._selected_parcel_id == "terrain-item-1", "disconnect retains original intent and selection")
	_observe()
	_check(not _panel._retry.disabled and _panel._return.disabled, "fresh reconnect observation allows only original retry")
	_panel._retry.emit_signal("pressed")
	_check(_remote.terrain_pending_intent() == original and _remote.retries == 1, "retry keeps original payload")
	_remote._terrain_intent = {}
	_remote.command_completed.emit(_remote.sent, ServiceResult.success({}))
	_return_now()
	_check(_last.is_success, "actual new holder returns")
	_observe()
	_check(_panel._return.disabled and _panel._lifecycle.text.contains("Returned fill-only escrow:\nterrain-transfer-1 · material.dirt · 777777 mg"), "returned escrow is separated from carried state")
	_check(_panel._escrow.selected >= 0 and _panel._claim.disabled, "same reappearing transfer restores selection but cannot rematerialize")
	_context = actor
	_world_move("drop", _shovel, "", "")
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_world_move("pickup", _shovel, "body.human-1", "hand.left")
	_self("select_hand", "", "", "hand.left")
	_observe()
	_check(not _panel._fill.disabled and _panel._claim.disabled, "returned escrow retains ordinary fill gates")
	_send("fill", _payload("terrain.dirt.fill", 123456, "terrain-transfer-1"), _next())
	_observe()
	_check(_panel._lifecycle.text.contains("654321 mg (0.654321 kg)"), "actual partial fill shows exact remaining mass")
	_send("fill", _payload("terrain.dirt.fill", 654321, "terrain-transfer-1"), _next())
	_observe()
	_check(_panel._fill.disabled and _panel._selected_escrow_id == "terrain-transfer-1", "actual full fill leaves stable missing selection")
	_context = actor
	_observe()
	_check(_panel._escrow.selected == -1 and _panel._claim.disabled, "other escrow does not silently replace removed selection")
	_panel._escrow.select(0)
	_panel._escrow.item_selected.emit(0)
	_check(_panel._selected_escrow_id == "terrain-transfer-2" and not _panel._claim.disabled, "explicit user selection chooses remaining excavation")
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_observe()
	# Legacy projections remain display-only inputs, never imported into the owner.
	var record: Dictionary = _view()
	for version in [2, 1]:
		var legacy: Dictionary = record.duplicate(true)
		legacy["terrain"]["schema_version"] = version
		for field in ["returnable_parcels", "fill_only_transfers", "next_return_request_number", "return_sequence_exhausted", "return_ready", "return_message"]: legacy["terrain"].erase(field)
		if version == 1:
			for field in ["next_materialize_request_number", "materialize_sequence_exhausted", "materialize_ready", "materialize_message"]: legacy["terrain"].erase(field)
		_remote._terrain_record = legacy["terrain"].duplicate(true)
		_panel.observe(legacy)
		_check(_panel._return.disabled and _panel._lifecycle.text.contains("unavailable in legacy observation v%d" % version), "legacy does not claim known empty return state")
		_check(_panel._parcels.get_item_text(0) == "Returnable parcels unavailable", "legacy dropdown does not imply known absence")
	_panel.observe({})
	_check(_panel._lifecycle.text.contains("Scoped terrain data unavailable") and _panel._fill.disabled, "unscoped input fails closed")
	_observe()
	var exhausted: Dictionary = _view()
	exhausted["terrain"]["materialize_sequence_exhausted"] = true
	_remote._terrain_record = exhausted["terrain"].duplicate(true)
	_panel.observe(exhausted)
	_check(_panel._lifecycle.text.contains("lifetime claim limit reached") and _panel._lifecycle.text.contains("returning does not free a slot"), "observed ceiling has no invented remaining count")
	await process_frame
	await process_frame
	_check(_panel.size.x <= 320 and _panel._lifecycle.size.x <= 320, "320px headless layout wraps without horizontal expansion")
	before = _canonical()
	for _iteration in range(5): _panel.observe(exhausted)
	_check(_canonical() == before and record == _view(), "repeated presentation does not mutate observations or owners")
	viewport.free()
	_remote.free()
	world.free()
	if _failures == 0: print("Terrain parcel usability: real claim/holder return/fill, exact mass, stable IDs, pending/rejected/reconnect, legacy and narrow headless layout passed.")
	quit(0 if _failures == 0 else 1)


func _view() -> Dictionary:
	return {"terrain": _terrain.observation(_context).value, "inventory": _inventory.own_inventory_observation(_context, true).value, "tools": _tools.capture_snapshot().value["ledger"]}


func _observe() -> void:
	var record: Dictionary = _view()
	_remote._terrain_record = record["terrain"].duplicate(true)
	_panel.observe(record)


func _return_now() -> void:
	var command := TerrainReturnCommand.new()
	command.command_id = &"terrain-return-1"
	command.request_number = 1
	command.payload = {"item_id": "terrain-item-1", "expected_inventory_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]}
	command.authenticated_context = _context
	_check(_world.enqueue_command(command).is_success, "actual return queues")
	_step()


## Test-only effect adapter; sockets and persistent storage are never opened.
class ObservedRemote extends RemoteWorldRuntime:
	var sent: SimulationCommand
	var retries: int = 0

	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		sent = command
		if _terrain_intent.is_empty():
			_terrain_intent = {"operation": command.operation, "request_number": command.request_number, "payload": command.payload.duplicate(true)}
		return ServiceResult.success({})

	func retry_terrain_intent() -> ServiceResult:
		retries += 1
		return enqueue_command(TerrainTransportCodec.command(int(_terrain_intent["request_number"]), _terrain_intent["operation"], _terrain_intent["payload"]))
