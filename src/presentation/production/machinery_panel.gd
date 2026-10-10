extends VBoxContainer
class_name MachineryPanel

## Read-only observation controls; every action is an authenticated queued intent.
var _world: WorldRuntime
var _record: Dictionary = {}
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


func configure(world: WorldRuntime) -> void:
	_world = world
	var guide := Label.new()
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.text = "Hand-build a frame, controller, power connector and work head from refined iron at the workbench. Fit sockets and canisters. Deploy a solar frame and wire machines directly or through a router. Add an expander for large prints and extra sockets. Removing parts pauses work; restart requires Resume."
	add_child(guide)
	for kind in MachineryWorkshop.KINDS:
		_kind.add_item("%s (%.2f kg iron)" % [kind, float(MachineryWorkshop.KINDS[kind]) / 1000000.0])
		_kind.set_item_metadata(_kind.item_count - 1, kind)
	_kind.add_item("Resource canister (printer + expander, 1 kg iron)")
	_kind.set_item_metadata(_kind.item_count - 1, "equipment.canister")
	_kind.add_item("Handheld extractor (printer + expander, 1.5 kg iron)")
	_kind.set_item_metadata(_kind.item_count - 1, "equipment.extractor")
	add_child(_kind)
	_button("Hand-build selected part", "machine_craft")
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
		row.add_child(field)
		_axes.append(field)
	_mode.add_item("Floor surface", 0)
	_mode.add_item("Freeform", 1)
	add_child(_mode)
	_button("Use current player position (floor)", "position")
	_button("Deploy assembled frame", "machine_deploy")
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
	)


func observe(record: Dictionary) -> void:
	_record = record
	var machinery: Dictionary = record["production"]["machinery"]
	var frames: Dictionary = {}
	var parts: Dictionary = {}
	var sockets: Dictionary = {}
	for id in machinery["parts"]:
		var kind: String = machinery["parts"][id]["kind"]
		parts[id] = "%s · %s" % [kind, id.right(8)]
		if kind == "frame": frames[id] = parts[id] + (" deployed" if machinery["placements"].has(id) else " packed")
		if kind == "socket": sockets[id] = parts[id]
	for physical in machinery["inventory_items"]:
		if physical["definition_id"] in ["item.resource-canister.prototype", "item.resource-canister.fabricated", "item.extractor.fabricated", "item.plate.prototype"]: parts[physical["item_id"]] = "%s · %s" % ["extractor" if physical["definition_id"] == "item.extractor.fabricated" else ("plate" if physical["definition_id"] == "item.plate.prototype" else "canister"), physical["item_id"]]
	for physical in record["inventory"]["items"]:
		if physical["definition_id"] in ["item.resource-canister.prototype", "item.resource-canister.fabricated", "item.extractor.fabricated", "item.plate.prototype"]: parts[physical["item_id"]] = "%s · %s" % ["extractor" if physical["definition_id"] == "item.extractor.fabricated" else ("plate" if physical["definition_id"] == "item.plate.prototype" else "canister"), physical["item_id"]]
	_fill(_machine, frames)
	_fill(_other, frames)
	_fill(_part, parts)
	_fill(_socket, sockets)
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


func _send(action: String) -> void:
	if _record.is_empty() or not _pending.is_empty(): return
	if action == "position":
		for index in range(3): _axes[index].value = 0 if index == 1 else float(_record["position"][index]) / 1000.0
		return
	var operation: String = action
	var payload: Dictionary = {"expected_revision": _record["production"]["state_revision"]}
	if action not in ["machine_craft", "machine_recycle"]: payload["machine_id"] = _selected(_machine)
	match action:
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
	_feedback.text = "Queued " + action if queued.is_success else queued.message


func select_machine(id: String) -> void:
	for index in range(_machine.item_count):
		if _machine.get_item_metadata(index) == id:
			_machine.select(index)
			return


func _button(title: String, action: String) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(_send.bind(action))
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
