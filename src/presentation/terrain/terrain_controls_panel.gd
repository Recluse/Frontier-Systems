extends VBoxContainer
class_name TerrainControlsPanel

## Presentation only. Uncertain work keeps the adapter's exact original intent.
var _remote: RemoteWorldRuntime
var _record: Dictionary = {}
var _target := OptionButton.new()
var _escrow := OptionButton.new()
var _amount := SpinBox.new()
var _status := Label.new()
var _feedback := Label.new()
var _lifecycle := Label.new()
var _selected_escrow_id: String = ""
var _selected_parcel_id: String = ""
var _dig := Button.new()
var _fill := Button.new()
var _claim := Button.new()
var _parcels := OptionButton.new()
var _return := Button.new()
var _retry := Button.new()
var _waiting: bool = false
var _request_id: String = ""


func configure(remote: RemoteWorldRuntime) -> void:
	_remote = remote
	add_theme_constant_override("separation", 10)
	var guide := Label.new()
	guide.text = "Finite terrain · fabricate a shovel from refined iron at the workstation, equip it in your active hand, and leave the other hand free. Stand within 1.5 m of a marker. Digging holds dirt in your own terrain escrow; filling returns it to a cell. Claim a whole escrow transfer as a portable parcel with a free hand. Return a held whole parcel to your escrow before filling. Returned transfers are fill-only and cannot be claimed again. Production consumption is deferred."
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(guide)
	for label in [_status, _feedback, _lifecycle]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_status)
	_target.fit_to_longest_item = false
	_target.add_item("Source dirt cell")
	_target.set_item_metadata(0, "terrain.dirt.source")
	_target.add_item("Fill dirt cell")
	_target.set_item_metadata(1, "terrain.dirt.fill")
	_target.item_selected.connect(func(_index: int) -> void: _refresh())
	add_child(_target)
	var amount_label := Label.new()
	amount_label.text = "Amount in kg (maximum 1 kg per command)"
	amount_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(amount_label)
	_amount.min_value = 0.001
	_amount.max_value = 1.0
	_amount.step = 0.001
	_amount.value = 0.25
	_amount.value_changed.connect(func(_value: float) -> void: _refresh())
	add_child(_amount)
	_dig.text = "Dig cell into own escrow"
	_dig.pressed.connect(_send.bind("excavate"))
	add_child(_dig)
	var escrow_label := Label.new()
	escrow_label.text = "Own escrow · excavation or returned fill-only (private)"
	escrow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(escrow_label)
	_escrow.fit_to_longest_item = false
	_escrow.item_selected.connect(func(index: int) -> void:
		_selected_escrow_id = _escrow.get_item_metadata(index)
		_refresh()
	)
	add_child(_escrow)
	_fill.text = "Fill cell from own escrow"
	_fill.pressed.connect(_send.bind("fill"))
	add_child(_fill)
	_claim.text = "Claim whole escrow parcel"
	_claim.pressed.connect(_claim_selected)
	add_child(_claim)
	_parcels.fit_to_longest_item = false
	var parcel_label := Label.new()
	parcel_label.text = "Carried returnable parcel · whole item"
	parcel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(parcel_label)
	_parcels.item_selected.connect(func(index: int) -> void:
		_selected_parcel_id = _parcels.get_item_metadata(index)
		_refresh()
	)
	add_child(_parcels)
	_return.text = "Return whole carried parcel"
	_return.pressed.connect(_return_selected)
	add_child(_return)
	_retry.text = "Retry original unresolved intent"
	_retry.pressed.connect(_retry_original)
	add_child(_retry)
	add_child(_lifecycle)
	add_child(_feedback)
	_remote.command_completed.connect(_completed)
	_remote.connection_closed.connect(func(_message: String) -> void:
		_record = {}
		_waiting = false
		_feedback.text = "Disconnected. The original unresolved terrain intent is retained; reconnect with the same invite to reconcile it."
		_populate_selections({})
		_refresh()
	)
	_refresh()


func observe(record: Dictionary) -> void:
	_record = record.duplicate(true) if TerrainObservationValidation.valid(record.get("terrain")) and record.has("inventory") and record.has("tools") else {}
	_populate_selections(_record.get("terrain", {}))
	_refresh()


func _populate_selections(terrain: Dictionary) -> void:
	var transfers: Dictionary = terrain.get("transfers", {})
	_escrow.clear()
	for id in transfers:
		_escrow.add_item("%s · %s" % [id, "returned: fill-only" if terrain.get("fill_only_transfers", []).has(id) else ("excavation" if terrain.get("schema_version") == 3 else "legacy")])
		var index: int = _escrow.item_count - 1
		_escrow.set_item_metadata(index, id)
		if _selected_escrow_id.is_empty(): _selected_escrow_id = id
		if id == _selected_escrow_id: _escrow.select(index)
	if not transfers.has(_selected_escrow_id): _escrow.select(-1)
	if _escrow.item_count == 0:
		_escrow.add_item("Escrow unavailable" if terrain.is_empty() else "No own escrow")
		_escrow.set_item_metadata(0, "")
		_escrow.set_item_disabled(0, true)
	var parcels: Dictionary = terrain.get("returnable_parcels", {})
	_parcels.clear()
	for id in parcels:
		_parcels.add_item(id)
		_parcels.set_item_metadata(_parcels.item_count - 1, id)
		if _selected_parcel_id.is_empty(): _selected_parcel_id = id
		if id == _selected_parcel_id: _parcels.select(_parcels.item_count - 1)
	if not parcels.has(_selected_parcel_id): _parcels.select(-1)
	if _parcels.item_count == 0:
		_parcels.add_item("Returnable parcels unavailable" if terrain.get("schema_version") != 3 else "No carried returnable parcel")
		_parcels.set_item_metadata(0, "")
		_parcels.set_item_disabled(0, true)


func _refresh() -> void:
	_dig.disabled = true
	_fill.disabled = true
	_claim.disabled = true
	_return.disabled = true
	_retry.disabled = true
	var available: bool = not _record.is_empty() and _remote.terrain_observation(null).is_success
	_lifecycle.text = TerrainParcelLifecycleView.describe(_record["terrain"] if available else {}, _selected_escrow_id, _selected_parcel_id, _remote.terrain_pending_intent(), _waiting)
	if _record.is_empty() or not _remote.terrain_observation(null).is_success:
		_status.text = "Waiting for authenticated terrain observation."
		return
	var terrain: Dictionary = _record["terrain"]
	var id: String = _target.get_item_metadata(_target.selected)
	var cell: Dictionary = terrain["cells"][id]
	var inventory: Dictionary = _record["inventory"]
	var held: String = "empty"
	for binding in inventory["equipped"]:
		if binding["slot_id"] != inventory["active_hand_slot_id"]: continue
		held = binding["item_id"]
		for item in inventory["items"]:
			if item["item_id"] == held: held = "%s (%s)" % [PlayerInventoryPanel.NAMES.get(item["definition_id"], "Equipment"), held]; break
	var own_mass: int = 0
	for transfer in terrain["transfers"].values(): own_mass += int(transfer["mass_milligrams"])
	_status.text = "%s · position %s mm\n%s · remaining %s / capacity %s · cell revision %d\nOwn escrow total %s · active tool %s\nInventory revision %d · tool revision %d\nHost work capability: %s" % [id, str(cell["position_millimetres"]), cell["state"]["material_id"], TerrainParcelLifecycleView.mass(int(cell["state"]["mass_milligrams"])), TerrainParcelLifecycleView.mass(int(cell["capacity_milligrams"])), cell["state"]["state_revision"], TerrainParcelLifecycleView.mass(own_mass), held, inventory["inventory_revision"], _record["tools"]["state_revision"], "ready" if cell["work_ready"] else cell["work_message"]]
	var unresolved: bool = not _remote.terrain_pending_intent().is_empty()
	_retry.disabled = _waiting or not unresolved
	if not unresolved and not _waiting and terrain.get("schema_version") in [2, 3] and not terrain["materialize_sequence_exhausted"] and terrain["materialize_ready"] and _escrow.selected >= 0:
		_claim.disabled = not terrain["transfers"].has(_escrow.get_item_metadata(_escrow.selected)) or terrain.get("fill_only_transfers", []).has(_escrow.get_item_metadata(_escrow.selected))
	if not unresolved and not _waiting and terrain.get("schema_version") == 3 and terrain["return_ready"] and not terrain["return_sequence_exhausted"] and _parcels.selected >= 0:
		_return.disabled = not terrain["returnable_parcels"].has(_parcels.get_item_metadata(_parcels.selected))
	if unresolved or _waiting or terrain["request_sequence_exhausted"] or not cell["work_ready"]: return
	var mass: int = roundi(_amount.value * 1000000.0)
	_dig.disabled = cell["state"]["mass_milligrams"] < mass
	if _escrow.selected >= 0:
		var transfer: String = _escrow.get_item_metadata(_escrow.selected)
		if terrain["transfers"].has(transfer): _fill.disabled = terrain["transfers"][transfer]["mass_milligrams"] < mass or cell["capacity_milligrams"] - cell["state"]["mass_milligrams"] < mass


func _send(operation: String) -> void:
	if _record.is_empty() or _waiting or not _remote.terrain_pending_intent().is_empty() or (_fill.disabled if operation == "fill" else _dig.disabled): return
	var terrain: Dictionary = _record["terrain"]
	var id: String = _target.get_item_metadata(_target.selected)
	var command := TerrainCommand.new()
	command.request_number = int(terrain["next_request_number"])
	command.command_id = StringName("terrain-client-%d" % command.request_number)
	command.operation = operation
	command.payload = {"cell_id": id, "expected_cell_revision": terrain["cells"][id]["state"]["state_revision"], "amount_milligrams": roundi(_amount.value * 1000000.0), "transfer_id": _escrow.get_item_metadata(_escrow.selected) if operation == "fill" and _escrow.selected >= 0 else "", "expected_inventory_revision": _record["inventory"]["inventory_revision"], "expected_tool_revision": _record["tools"]["state_revision"]}
	_queued(_remote.enqueue_command(command), String(command.command_id))


func _claim_selected() -> void:
	if _record.is_empty() or _waiting or not _remote.terrain_pending_intent().is_empty() or _escrow.selected < 0 or _claim.disabled: return
	var terrain: Dictionary = _record["terrain"]
	var command: SimulationCommand = TerrainTransportCodec.command(int(terrain["next_materialize_request_number"]), "materialize", {"transfer_id": _escrow.get_item_metadata(_escrow.selected), "expected_inventory_revision": _record["inventory"]["inventory_revision"]})
	_queued(_remote.enqueue_command(command), String(command.command_id))


func _return_selected() -> void:
	if _record.is_empty() or _waiting or not _remote.terrain_pending_intent().is_empty() or _return.disabled or _parcels.selected < 0: return
	var command: SimulationCommand = TerrainTransportCodec.command(int(_record["terrain"]["next_return_request_number"]), "return", {"item_id": _parcels.get_item_metadata(_parcels.selected), "expected_inventory_revision": _record["inventory"]["inventory_revision"]})
	_queued(_remote.enqueue_command(command), String(command.command_id))


func _retry_original() -> void:
	var intent: Dictionary = _remote.terrain_pending_intent()
	if intent.is_empty() or _waiting: return
	_queued(_remote.retry_terrain_intent(), TerrainTransportCodec.request_id(int(intent["request_number"]), intent["operation"]))


func _queued(result: ServiceResult, id: String) -> void:
	_waiting = result.is_success
	_request_id = id if result.is_success else ""
	_feedback.text = "Waiting for host confirmation…" if result.is_success else result.message
	_refresh()


func _completed(command: SimulationCommand, result: ServiceResult) -> void:
	if not TerrainTransportCodec.is_terrain(command) or String(command.command_id) != _request_id: return
	_waiting = false
	_request_id = ""
	_feedback.text = "Host accepted original intent; current observation determines parcel presence and escrow." if result.is_success else "Rejected %s: %s" % [result.error_code, result.message]
	_refresh()
