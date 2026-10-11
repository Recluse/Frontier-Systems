extends VBoxContainer
class_name MachineryPanel
signal placement_feedback_changed(feedback: Dictionary)

## Read-only observation controls; every action is an authenticated queued intent.
var _world: WorldRuntime
var _record: Dictionary = {}
var _design_signature: String = ""
var _machine := OptionButton.new()
var _part := OptionButton.new()
var _socket := OptionButton.new()
var _other := OptionButton.new()
var _kind := OptionButton.new()
var _recipe := OptionButton.new()
var _eject_amount := SpinBox.new()
var _mode := OptionButton.new()
var _axes: Array[SpinBox] = []
var _status := Label.new()
var _feedback := Label.new()
var _pending: String = ""
var _wall := OptionButton.new()
var _wall_turn := OptionButton.new()
var _pending_deploy: Dictionary = {}
var _pending_wall: Dictionary = {}
var _placement_kind := OptionButton.new()
var _show_placement := CheckBox.new()
var _placement_status := Label.new()
var _action_buttons: Array[Button] = []
var _preview: MachineryPreview


func configure(world: WorldRuntime) -> void:
	_world = world
	var guide := Label.new()
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.text = "Hand-build a frame, controller, power connector and work head from refined iron at the workbench. Fit sockets and canisters. Deploy a solar frame and wire machines directly or through a router. Equipment printing needs an expander; hand assembly needs only materials. Expanders also add sockets. Removing parts pauses work; restart requires Resume."
	add_child(guide)
	_kind.fit_to_longest_item = false
	_populate_designs({})
	add_child(_kind)
	_button("Hand-build selected part / equipment", "machine_craft")
	_label("Machine frame")
	add_child(_machine)
	_label("Physical module / canister / cable")
	add_child(_part)
	_label("Socket (for canister insertion/removal)")
	add_child(_socket)
	_button("Fit module", "machine_fit")
	_button("Remove module / printed part", "machine_unfit")
	_button("Insert canister", "machine_insert")
	_button("Remove canister", "machine_remove")
	_label("Placement coordinates, metres relative to workbench")
	var row := HBoxContainer.new()
	add_child(row)
	for axis in ["X", "Y", "Z"]:
		var title := Label.new()
		title.text = axis
		row.add_child(title)
		var field := SpinBox.new()
		field.min_value = -100
		field.max_value = 100
		field.step = 0.1
		field.value_changed.connect(func(_value: float) -> void: _refresh_placement())
		row.add_child(field)
		_axes.append(field)
	_mode.add_item("Floor surface", 0)
	_mode.add_item("Freeform", 1)
	add_child(_mode)
	_mode.item_selected.connect(func(_index: int) -> void: _refresh_placement())
	_machine.item_selected.connect(func(_index: int) -> void: _refresh_placement())
	_placement_kind.add_item("Machine placement preview", 0)
	_placement_kind.add_item("Physical wall placement preview", 1)
	add_child(_placement_kind)
	_placement_kind.item_selected.connect(func(_index: int) -> void: _refresh_placement())
	_part.item_selected.connect(func(_index: int) -> void: _refresh_placement())
	_wall.item_selected.connect(func(_index: int) -> void: select_wall(_selected(_wall)))
	_wall_turn.item_selected.connect(func(_index: int) -> void: _refresh_placement())
	_show_placement.text = "Show placement ghost / footprint"
	_show_placement.toggled.connect(func(_shown: bool) -> void: _refresh_placement())
	add_child(_show_placement)
	_placement_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_placement_status)
	visibility_changed.connect(_refresh_placement)
	_button("Use current player position (floor)", "position")
	_button("Deploy assembled frame", "machine_deploy")
	_label("Walls: select an owned physical plate above. Floor panels are 1 × 2 × 0.1 m and snap to the 0.1 m coordinate grid.")
	_wall_turn.add_item("Wall along X", 0)
	_wall_turn.add_item("Wall along Z", 1)
	add_child(_wall_turn)
	_button("Build wall from selected physical plate", "wall_build")
	add_child(_wall)
	_button("Remove selected wall and recover plate", "wall_remove")
	_button("Pack machine with its nested contents", "machine_pack")
	_label("Other cable endpoint")
	add_child(_other)
	_button("Connect selected cable", "machine_wire")
	_button("Disconnect selected cable", "machine_unwire")
	_button("Enable machine / router", "enable")
	_button("Isolate machine / router", "disable")
	for id in ["extract.iron", "extract.ice", "extract.regolith", "refine.iron", "refine.ice", "refine.regolith", "chemical.electrolysis.micro", "chemical.nutrients", "craft.plate", "salvage.plate"]:
		_recipe.add_item("Electrolyze 10 g water (separate H2 / O2 canisters)" if id == "chemical.electrolysis.micro" else id)
		_recipe.set_item_metadata(_recipe.item_count - 1, id)
	add_child(_recipe)
	_button("Run powered canister batch", "machine_run")
	_button("Resume batch after restart", "machine_resume")
	_button("Cancel batch (inputs stay in canisters)", "machine_cancel")
	_button("Print selected part into machine storage", "machine_print")
	_label("Autolathe: fit an autolathe head, power and controller. Feed owned plates or empty parts into its 2 kg solid hopper.")
	_button("Feed selected physical plate / empty part", "machine_autolathe_feed")
	_button("Autolathe: fabricate selected design", "machine_autolathe_make")
	_eject_amount.min_value = 1
	_eject_amount.max_value = 2000
	_eject_amount.value = 100
	_eject_amount.suffix = " g iron"
	add_child(_eject_amount)
	_button("Eject iron into selected owned canister", "machine_autolathe_eject")
	_button("Recycle empty owned part into workbench iron", "machine_recycle")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	add_child(_feedback)
	move_child(_status, 1)
	move_child(_feedback, 2)
	_world.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void:
		if String(command.command_id) == _pending:
			_pending = ""
			_feedback.text = "Completed" if result.is_success else result.message
			if (not _pending_deploy.is_empty() or not _pending_wall.is_empty()) and result.is_success:
				_show_placement.set_pressed_no_signal(false)
			_pending_deploy.clear()
			_pending_wall.clear()
			_refresh_placement()
	)

	if world is RemoteWorldRuntime:
		(world as RemoteWorldRuntime).connection_closed.connect(func(message: String) -> void:
			observe({})
			_show_placement.set_pressed_no_signal(false)
			_feedback.text = message
			_status.text = "Machinery observation unavailable."
			_refresh_placement()
		)


func observe(record: Dictionary) -> void:
	_record = record
	if record.is_empty():
		_show_placement.set_pressed_no_signal(false)
		for picker in [_machine, _part, _wall, _other, _socket]: picker.clear()
		_refresh_placement()
		return
	_populate_designs(record["production"].get("blueprints", {}))
	var machinery: Dictionary = record["production"]["machinery"]
	var frames: Dictionary = {}
	var parts: Dictionary = {}
	var sockets: Dictionary = {}
	for id in machinery["parts"]:
		var kind: String = machinery["parts"][id]["kind"]
		parts[id] = "%s · %s" % [kind, id.right(8)]
		if kind == "frame": frames[id] = parts[id] + (" deployed" if machinery["placements"].has(id) else " packed")
		if kind == "socket": sockets[id] = parts[id]
	for physical in machinery["inventory_items"] + record["inventory"]["items"]:
		if not parts.has(physical["item_id"]):
			parts[physical["item_id"]] = "%s · %s" % [PlayerInventoryPanel.NAMES.get(physical["definition_id"], physical["definition_id"]), physical["item_id"]]
	_fill(_machine, frames)
	_fill(_other, frames)
	_fill(_part, parts)
	_fill(_socket, sockets)
	var walls: Dictionary = {}
	for id in record["production"]["walls"]: walls[id] = "Wall %s · %s" % [id.right(8), str(record["production"]["walls"][id]["position"])]
	_fill(_wall, walls)
	var lines: PackedStringArray = []
	for id in machinery["placements"]:
		var placement: Dictionary = machinery["placements"][id]
		var fitted: PackedStringArray = []
		for module in machinery["mounts"]:
			if machinery["mounts"][module] == id: fitted.append(machinery["parts"][module]["kind"])
		lines.append("%s: %s · %d J · %s" % [id.right(8), "enabled" if placement["enabled"] else "isolated", placement["energy"], ", ".join(fitted)])
		if machinery["jobs"].has(id): lines.append("  %s · %d ticks · %s" % [machinery["jobs"][id]["recipe"], machinery["jobs"][id]["progress"], "paused" if machinery["jobs"][id]["paused"] else "running or awaiting parts/power/capacity"])
	for id in machinery["cargo"]:
		var content: PackedStringArray = []
		for material in machinery["cargo"][id]:
			if int(machinery["cargo"][id][material]) > 0: content.append("%s %.3f kg" % [material, float(machinery["cargo"][id][material]) / 1000000.0])
		lines.append("%s: %s" % [id, ", ".join(content)])
	_status.text = "\n".join(lines)
	_refresh_placement()


func _send(action: String) -> void:
	if _record.is_empty() or not _pending.is_empty(): return
	if action == "position":
		for index in range(3): _axes[index].value = 0 if index == 1 else float(_record["position"][index]) / 1000.0
		return
	if action in ["wall_build", "wall_remove"]: _placement_kind.select(1)
	var operation: String = action
	var payload: Dictionary = {"expected_revision": _record["production"]["state_revision"]}
	if action not in ["machine_craft", "machine_recycle", "wall_build", "wall_remove"]: payload["machine_id"] = _selected(_machine)
	match action:
		"wall_build": payload.merge({"item_id": _selected(_part), "position": [roundi(_axes[0].value * 1000), roundi(_axes[1].value * 1000), roundi(_axes[2].value * 1000)], "quarter_turn": _wall_turn.selected})
		"wall_remove": payload["wall_id"] = _selected(_wall)
		"machine_craft", "machine_print", "machine_autolathe_make": payload["kind"] = _selected(_kind)
		"machine_recycle", "machine_autolathe_feed": payload["item_id"] = _selected(_part)
		"machine_fit", "machine_unfit", "machine_insert", "machine_remove":
			payload["item_id"] = _selected(_part)
			payload["socket_id"] = _selected(_socket)
		"machine_deploy":
			payload["position"] = [roundi(_axes[0].value * 1000), roundi(_axes[1].value * 1000), roundi(_axes[2].value * 1000)]
			payload["mode"] = "surface" if _mode.selected == 0 else "freeform"
		"machine_wire": payload.merge({"item_id": _selected(_part), "other_id": _selected(_other)})
		"machine_unwire": payload["item_id"] = _selected(_part)
		"machine_autolathe_eject": payload.merge({"item_id": _selected(_part), "amount_milligrams": roundi(_eject_amount.value * 1000)})
		"machine_run": payload["recipe"] = _selected(_recipe)
		"enable", "disable":
			operation = "machine_enable"
			payload["enabled"] = action == "enable"
	var command := ProductionDevelopmentCommand.new()
	command.command_id = StringName("machinery-%s" % _world.next_local_request_id())
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", _world.world_id, _world.region_id)
	command.operation = operation
	command.payload = payload
	var queued: ServiceResult = _world.enqueue_command(command)
	_pending = String(command.command_id) if queued.is_success else ""
	_feedback.text = "Queued " + action + "; waiting for host" if queued.is_success else queued.message
	if action == "machine_deploy" and queued.is_success:
		_pending_deploy = payload.duplicate(true)
		_pending_deploy["display_size"] = MachineryPlacementFeedback.envelope(_record["production"]["machinery"], payload["machine_id"])
	if action in ["wall_build", "wall_remove"] and queued.is_success:
		_pending_wall = payload.duplicate(true)
		_pending_wall["operation"] = action
		if action == "wall_remove":
			_pending_wall.merge(_record["production"]["walls"].get(payload["wall_id"], {"position": [0, 0, 0], "quarter_turn": 0}))
	_refresh_placement()


func select_machine(id: String) -> void:
	for index in range(_machine.item_count):
		if _machine.get_item_metadata(index) == id:
			_machine.select(index)
			if _pending.is_empty(): _placement_kind.select(0)
			_refresh_placement()
			return


func select_wall(id: String) -> void:
	for index in range(_wall.item_count):
		if _wall.get_item_metadata(index) == id:
			_wall.select(index)
			if _pending.is_empty():
				_placement_kind.select(1)
				_show_placement.set_pressed_no_signal(false)
			_refresh_placement()
			return


func _button(title: String, action: String) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(_send.bind(action))
	_action_buttons.append(button)
	add_child(button)


func _label(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)


static func _selected(picker: OptionButton) -> String:
	return String(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""


static func _fill(picker: OptionButton, entries: Dictionary) -> void:
	var selected: String = _selected(picker)
	picker.clear()
	for id in entries:
		picker.add_item(entries[id])
		picker.set_item_metadata(picker.item_count - 1, id)
		if id == selected: picker.select(picker.item_count - 1)


## Designs come from the scoped server observation, never a client-authored bill.
func _populate_designs(blueprints: Dictionary) -> void:
	var signature: String = JSON.stringify(blueprints, "", true)
	if signature == _design_signature: return
	_design_signature = signature
	var selected: String = _selected(_kind)
	_kind.clear()
	for kind in MachineryWorkshop.KINDS:
		_kind.add_item("%s (%.2f kg iron)" % [kind, float(MachineryWorkshop.KINDS[kind]) / 1000000.0])
		_kind.set_item_metadata(_kind.item_count - 1, kind)
	for id in blueprints:
		var bill: PackedStringArray = []
		for material in blueprints[id]["materials"]: bill.append("%.2f kg %s" % [float(blueprints[id]["materials"][material]) / 1000000.0, material])
		_kind.add_item("%s (%s)" % [blueprints[id]["name"], ", ".join(bill)])
		_kind.set_item_metadata(_kind.item_count - 1, id)
	for index in range(_kind.item_count):
		if _kind.get_item_metadata(index) == selected: _kind.select(index)



## Explicit scene-owned binding; no global intent bus or canonical state mutation.
func bind_preview(preview: MachineryPreview) -> void:
	_preview = preview
	placement_feedback_changed.connect(preview.present_feedback)
	_refresh_placement()


func _exit_tree() -> void:
	if is_instance_valid(_preview):
		_preview.present_feedback({})


func _refresh_placement() -> void:
	var waiting: bool = not _pending.is_empty()
	for button in _action_buttons: button.disabled = waiting or _record.is_empty()
	for field in _axes: field.editable = not waiting
	_mode.disabled = waiting
	_machine.disabled = waiting
	for picker in [_part, _wall, _wall_turn, _placement_kind]: picker.disabled = waiting
	if _axes.size() != 3: return
	var coords: Array = [roundi(_axes[0].value * 1000), roundi(_axes[1].value * 1000), roundi(_axes[2].value * 1000)]
	var machine_id: String = _selected(_machine)
	var mode: String = "surface" if _mode.selected == 0 else "freeform"
	if not _pending_deploy.is_empty():
		coords = _pending_deploy["position"].duplicate()
		machine_id = _pending_deploy["machine_id"]
		mode = _pending_deploy["mode"]
	var feedback: Dictionary = MachineryPlacementFeedback.describe(_record, machine_id, coords, mode, _show_placement.button_pressed, not _pending_deploy.is_empty(), _pending_deploy.get("display_size", Vector3.ZERO))
	if not _pending_wall.is_empty() or (_pending_deploy.is_empty() and _placement_kind.selected == 1):
		var plate_id: String = _pending_wall.get("item_id", _selected(_part))
		var wall_id: String = _pending_wall.get("wall_id", _selected(_wall))
		var turn: int = int(_pending_wall.get("quarter_turn", _wall_turn.selected))
		if not _pending_wall.is_empty(): coords = _pending_wall["position"].duplicate()
		feedback = WallPlacementFeedback.describe(_record, plate_id, wall_id, coords, turn, _show_placement.button_pressed or _pending_wall.get("operation", "") == "wall_build", _pending_wall)
	_placement_status.text = feedback["text"]
	if not is_visible_in_tree(): feedback = {}
	placement_feedback_changed.emit(feedback)
