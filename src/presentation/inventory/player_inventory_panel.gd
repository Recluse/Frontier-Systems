extends VBoxContainer
class_name PlayerInventoryPanel

## Authenticated player UI. All equipment/storage/tool effects are server intents.
const NAMES: Dictionary = {"item.backpack.prototype": "Backpack", "item.pouch.prototype": "Tool pouch", "item.crowbar.prototype": "Crowbar", "item.resource-canister.prototype": "Resource canister", "item.plate.prototype": "Printed plate", "item.extractor.prototype": "Resource extractor", "item.resource-canister.fabricated": "Fabricated resource canister", "item.extractor.fabricated": "Fabricated resource extractor"}
var _remote: RemoteWorldRuntime
var _record: Dictionary = {}
var _production: Dictionary = {}
var _nearby: Dictionary = {}
var _items := ItemList.new()
var _world_items := ItemList.new()
var _source := OptionButton.new()
var _destination := OptionButton.new()
var _slot := OptionButton.new()
var _deposit := OptionButton.new()
var _carrier := OptionButton.new()
var _summary := Label.new()
var _details := Label.new()
var _equipment := Label.new()
var _result := Label.new()
var _buttons: Array[Button] = []
var _pending: String = ""
var _view_key: String = ""
var _tools: Dictionary = {}
var _tool_parts := OptionButton.new()


func configure(remote: RemoteWorldRuntime) -> void:
	_remote = remote
	add_theme_constant_override("separation", 10)
	_label("Inventory · portable storage · tools")
	for label in [_summary, _equipment, _details, _result]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	add_child(_equipment)
	_label("Browse container (double-click a backpack or pouch to open)")
	add_child(_source)
	_source.item_selected.connect(func(_index: int) -> void: _fill_items(); _inspect())
	_items.custom_minimum_size.y = 180
	_items.item_selected.connect(func(_index: int) -> void: _inspect())
	_items.item_activated.connect(_open_storage)
	add_child(_items)
	add_child(_details)
	_label("Equipment slot")
	add_child(_slot)
	var equipment_actions := HBoxContainer.new()
	add_child(equipment_actions)
	_button(equipment_actions, "Equip", _self_action.bind("equip"))
	_button(equipment_actions, "Unequip", _self_action.bind("unequip"))
	_button(equipment_actions, "Switch hand", _self_action.bind("switch_hand"))
	_button(self, "Make selected hand active", _self_action.bind("select_hand"))
	_label("Destination storage")
	add_child(_destination)
	_button(self, "Move selected item into destination", _self_action.bind("move"))
	_label("Nearby storage · approach the tray to collect or drop")
	_world_items.custom_minimum_size.y = 100
	add_child(_world_items)
	var world_actions := HBoxContainer.new()
	add_child(world_actions)
	_button(world_actions, "Collect selected", _world_action.bind("pickup"))
	_button(world_actions, "Drop selected", _world_action.bind("drop"))
	_label("Active tool · resource extractor")
	for id in ["deposit.iron", "deposit.ice", "deposit.regolith"]:
		_deposit.add_item({"deposit.iron": "Iron ore", "deposit.ice": "Ice", "deposit.regolith": "Regolith"}[id])
		_deposit.set_item_metadata(_deposit.item_count - 1, id)
	add_child(_deposit)
	add_child(_carrier)
	_button(self, "Extract 1 kg using active tool", _use_tool)
	_label("Tool component maintenance · select a tool above, then a component")
	add_child(_tool_parts)
	_button(self, "Maintain selected component at workstation", _repair_component)
	_label("Equip the extractor in a hand, make that hand active, carry a canister and approach the source. Mounted extraction remains available through Workstation. Crowbar world interactions are a later integration.")
	add_child(_result)
	remote.command_completed.connect(_completed)
	remote.connection_closed.connect(func(message: String) -> void:
		_record = {}
		_items.clear()
		_world_items.clear()
		_result.text = message
		_update_buttons()
	)
	_update_buttons()


func observe(frame: Dictionary) -> void:
	_record = frame["inventory"]
	_production = frame["production"]
	_nearby = frame["world_items"]
	_tools = frame.get("tools", {})
	var world_containers: Array = []
	for container in _nearby.get("containers", []):
		world_containers.append(container["container_id"])
	var view_key: String = JSON.stringify([_record["inventory_revision"], _record["mass_milligrams"], _production["state_revision"], _tools.get("state_revision", -1), world_containers])
	if view_key == _view_key:
		return
	_view_key = view_key
	_summary.text = "Carried: %.2f kg · %d items" % [float(_record["mass_milligrams"]) / 1000000.0, _record["items"].size()]
	var equipped: PackedStringArray = []
	for binding in _record["equipped"]:
		equipped.append("%s: %s" % [_slot_name(binding["slot_id"]), _item_name(binding["item_id"])])
	_equipment.text = "Active: %s\n%s" % [_slot_name(_record["active_hand_slot_id"]), ", ".join(equipped)]
	var containers: Array = _record.get("container_ids", [])
	_fill_picker(_source, containers, true)
	_fill_picker(_destination, containers)
	_fill_picker(_slot, _record["slot_ids"])
	var previous_carrier: String = str(_carrier.get_item_metadata(_carrier.selected)) if _carrier.selected >= 0 else ""
	_carrier.clear()
	for id in _production.get("cargo", {}):
		_carrier.add_item("Canister %d" % (_carrier.item_count + 1))
		_carrier.set_item_metadata(_carrier.item_count - 1, id)
		if id == previous_carrier:
			_carrier.select(_carrier.item_count - 1)
	_fill_items()
	var selected: String = _selected_id(_world_items)
	_world_items.clear()
	for container in _nearby.get("containers", []):
		for item in container["items"]:
			_world_items.add_item(NAMES.get(item["definition_id"], "Equipment"))
			_world_items.set_item_metadata(_world_items.item_count - 1, {"item_id": item["item_id"], "container_id": container["container_id"]})
			if item["item_id"] == selected:
				_world_items.select(_world_items.item_count - 1)
	_inspect()
	_update_buttons()


func _fill_picker(picker: OptionButton, ids: Array, all_items: bool = false) -> void:
	var previous: Variant = picker.get_item_metadata(picker.selected) if picker.selected >= 0 else null
	picker.clear()
	if all_items:
		picker.add_item("All carried items")
		picker.set_item_metadata(0, "*")
	for id in ids:
		picker.add_item(_slot_name(id) if picker == _slot else _container_name(id))
		picker.set_item_metadata(picker.item_count - 1, id)
		if previous == id:
			picker.select(picker.item_count - 1)


func _fill_items() -> void:
	var selected: String = _selected_id(_items)
	_items.clear()
	if _record.is_empty():
		return
	var source: String = str(_source.get_item_metadata(_source.selected)) if _source.selected >= 0 else "*"
	for item in _record["items"]:
		if source != "*" and item["container_id"] != source:
			continue
		var name: String = str(NAMES.get(item["definition_id"], "Equipment"))
		_items.add_item("%s · %s" % [name, _container_name(item["container_id"])])
		_items.set_item_metadata(_items.item_count - 1, item)
		if item["item_id"] == selected:
			_items.select(_items.item_count - 1)


func _inspect() -> void:
	var id: String = _selected_id(_items)
	_details.text = "Select an item to inspect its condition, mass and contents."
	var selected_part: String = str(_tool_parts.get_item_metadata(_tool_parts.selected)) if _tool_parts.selected >= 0 else ""
	_tool_parts.clear()
	for detail in _record.get("item_details", []):
		if detail["item"]["item_id"] != id:
			continue
		_details.text = "%s · legacy shell condition %d%% · loaded mass %.2f kg\nVolume: %.2f L" % [_item_name(id), int(detail["item"]["condition_permille"]) / 10, float(detail["mass_milligrams"]) / 1000000.0, float(detail["volume_millilitres"]) / 1000.0]
		for container in _record.get("container_records", []):
			if container["owner_item_id"] == id:
				_details.text += "\nStorage: %.2f / %.2f kg · %.2f / %.2f L" % [float(container["load"]["mass_milligrams"]) / 1000000.0, float(container["capacity"]["max_mass_milligrams"]) / 1000000.0, float(container["load"]["volume_millilitres"]) / 1000.0, float(container["capacity"]["max_volume_millilitres"]) / 1000.0]
		if _production.get("cargo", {}).has(id):
			for material in _production["cargo"][id]:
				if _production["cargo"][id][material] > 0:
					_details.text += "\n%s: %.2f kg" % [material, float(_production["cargo"][id][material]) / 1000000.0]
		if _production.get("structures", {}).has(id):
			_details.text += "\nRecoverable construction materials:"
			for material in _production["structures"][id]["materials"]:
				_details.text += " %s %.2f kg" % [material, float(_production["structures"][id]["materials"][material]) / 1000000.0]
	for assembly in _tools.get("assemblies", []):
		if assembly["assembly_id"] != id: continue
		_details.text += "\nComponent condition (authoritative):"
		for part in assembly["parts"]:
			var text: String = "%s · %s · %.4f%%" % [part["name"], part["material_name"], float(part["integrity_ppm"]) / 10000.0]
			_details.text += "\n" + text
			_tool_parts.add_item(text)
			_tool_parts.set_item_metadata(_tool_parts.item_count - 1, part["part_id"])
			if part["part_id"] == selected_part: _tool_parts.select(_tool_parts.item_count - 1)
		for action in assembly["actions"]:
			_details.text += "\n%s: %s" % [action, "available" if assembly["actions"][action]["available"] else "missing " + ", ".join(PackedStringArray(assembly["actions"][action]["missing_functions"]))]


func _open_storage(index: int) -> void:
	var id: String = _items.get_item_metadata(index)["item_id"]
	for container in _record.get("container_records", []):
		if container["owner_item_id"] == id:
			for entry in range(_source.item_count):
				if _source.get_item_metadata(entry) == container["container_id"]:
					_source.select(entry)
					_fill_items()
					_inspect()
					return


func _self_action(operation: String) -> void:
	if _record.is_empty():
		return
	var payload: Dictionary = {"operation": operation, "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": _record["inventory_revision"]}
	if operation in ["equip", "move"]:
		var selected: PackedInt32Array = _items.get_selected_items()
		if selected.is_empty():
			_result.text = "Select an item first."
			return
		var item: Dictionary = _items.get_item_metadata(selected[0])
		payload["item_id"] = item["item_id"]
		payload["source_container_id"] = item["container_id"]
	if operation in ["equip", "unequip", "select_hand"]:
		payload["slot_id"] = _slot.get_item_metadata(_slot.selected)
	if operation in ["move", "unequip"]:
		payload["destination_container_id"] = _destination.get_item_metadata(_destination.selected)
	_submit("self", payload)


func _world_action(operation: String) -> void:
	if _record.is_empty():
		return
	var list: ItemList = _world_items if operation == "pickup" else _items
	var selected: PackedInt32Array = list.get_selected_items()
	if selected.is_empty() or _nearby.get("containers", []).is_empty():
		_result.text = "Select an item and approach accessible world storage."
		return
	var item: Dictionary = list.get_item_metadata(selected[0])
	_submit("world", {"operation": operation, "item_id": item["item_id"], "world_container_id": item["container_id"] if operation == "pickup" else _nearby["containers"][0]["container_id"], "destination_container_id": _destination.get_item_metadata(_destination.selected) if operation == "pickup" else "", "slot_id": "", "expected_revision": _record["inventory_revision"]})


func _use_tool() -> void:
	if _record.is_empty():
		return
	if _carrier.selected < 0:
		_result.text = "Carry a resource canister first."
		return
	_submit("tool_extract", {"deposit_id": _deposit.get_item_metadata(_deposit.selected), "carrier_id": _carrier.get_item_metadata(_carrier.selected), "amount_milligrams": 1000000, "expected_revision": _production["state_revision"]}, true)


func switch_active_hand() -> void:
	_self_action("switch_hand")


func _repair_component() -> void:
	if _tool_parts.selected < 0 or _tools.is_empty():
		_result.text = "Select a tool and component first."
		return
	_submit("repair_tool_component", {"part_id": _tool_parts.get_item_metadata(_tool_parts.selected), "amount_ppm": 1000000, "expected_revision": _production["state_revision"], "expected_tool_revision": _tools["state_revision"]}, true)


func use_active_tool() -> void:
	_use_tool()


func _submit(operation: String, payload: Dictionary, production: bool = false) -> void:
	if not _pending.is_empty():
		return
	var command: SimulationCommand = ProductionDevelopmentCommand.new() if production else InventoryDevelopmentCommand.new()
	command.command_id = _remote.next_local_request_id()
	command.operation = operation
	command.payload = payload
	var queued: ServiceResult = _remote.enqueue_command(command)
	if queued.is_success:
		_pending = String(command.command_id)
		_result.text = "Waiting for server…"
	else:
		_result.text = queued.message
	_update_buttons()


func _completed(command: SimulationCommand, result: ServiceResult) -> void:
	if String(command.command_id) == _pending:
		_pending = ""
		_result.text = "Action completed." if result.is_success else result.message
		_update_buttons()


func _update_buttons() -> void:
	for button in _buttons:
		button.disabled = _record.is_empty() or not _pending.is_empty()


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)


func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons.append(button)


static func _selected_id(list: ItemList) -> String:
	var selected: PackedInt32Array = list.get_selected_items()
	return "" if selected.is_empty() else str(list.get_item_metadata(selected[0])["item_id"])


func _item_name(id: String) -> String:
	for item in _record.get("items", []):
		if item["item_id"] == id:
			return NAMES.get(item["definition_id"], "Equipment")
	return "Equipment"


func _container_name(id: String) -> String:
	if id == _record.get("body_container_id"):
		return "Carried loose"
	for container in _record.get("container_records", []):
		if container["container_id"] == id:
			return _item_name(container["owner_item_id"])
	return "Storage"


static func _slot_name(id: String) -> String:
	return id.replace("hand.", "").replace("_", " ").capitalize()
