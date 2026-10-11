extends VBoxContainer
class_name PlayerInventoryPanel

## Authenticated player UI. All equipment/storage/tool effects are server intents.
const NAMES: Dictionary = {"item.backpack.fabricated": "Fabricated storage backpack", "item.pouch.fabricated": "Fabricated tool pouch", "item.crowbar.fabricated": "Fabricated crowbar", "item.shovel.fabricated": "Fabricated shovel", "item.backpack.prototype": "Backpack", "item.pouch.prototype": "Tool pouch", "item.crowbar.prototype": "Crowbar", "item.resource-canister.prototype": "Resource canister", "item.plate.prototype": "Printed plate", "item.extractor.prototype": "Resource extractor", "item.resource-canister.fabricated": "Fabricated resource canister", "item.extractor.fabricated": "Fabricated resource extractor"}
var _remote: RemoteWorldRuntime
var _record: Dictionary = {}
var _production: Dictionary = {}
var _nearby: Dictionary = {}
var _items := ItemList.new()
var _world_items := ItemList.new()
var _world_root := OptionButton.new()
var _world_details := Label.new()
var _world_status := Label.new()
var _pending_world: Dictionary = {}
var _pending_inventory: Dictionary = {}
var _inventory_buttons: Dictionary = {}
var _storage_status := Label.new()
var _initialized_pickers: Dictionary = {}
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
var _tool_mounts := OptionButton.new()
var _loose_parts := OptionButton.new()
var _part_blueprints := OptionButton.new()
var _work_cycles := SpinBox.new()
var _work_status := Label.new()


func configure(remote: RemoteWorldRuntime) -> void:
	_remote = remote
	for picker in [_source, _destination, _slot, _deposit, _carrier, _tool_parts, _tool_mounts, _loose_parts, _part_blueprints]:
		picker.fit_to_longest_item = false
		picker.clip_text = true
	add_theme_constant_override("separation", 10)
	_label("Inventory · portable storage · tools")
	for label in [_summary, _equipment, _details, _result]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	add_child(_equipment)
	_label("Browse container (double-click a backpack or pouch to open)")
	add_child(_source)
	_source.item_selected.connect(func(_index: int) -> void: _fill_items(); _inspect(); _update_buttons())
	_items.custom_minimum_size.y = 180
	_items.item_selected.connect(func(_index: int) -> void: _inspect(); _update_buttons())
	_items.item_activated.connect(_open_storage)
	add_child(_items)
	add_child(_details)
	_label("Equipment slot")
	add_child(_slot)
	var equipment_actions := HBoxContainer.new()
	add_child(equipment_actions)
	_button(equipment_actions, "Equip", _self_action.bind("equip"), "equip")
	_button(equipment_actions, "Unequip", _self_action.bind("unequip"), "unequip")
	_button(equipment_actions, "Switch hand", _self_action.bind("switch_hand"), "switch_hand")
	_button(self, "Make selected hand active", _self_action.bind("select_hand"), "select_hand")
	_label("Destination storage")
	add_child(_destination)
	_storage_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_storage_status)
	_destination.item_selected.connect(func(_index: int) -> void: _update_buttons())
	_slot.item_selected.connect(func(_index: int) -> void: _update_buttons())
	_button(self, "Move selected item into destination", _self_action.bind("move"), "move")
	_label("Cooperative tray handoff · drop here for another crew member to collect")
	_world_root.fit_to_longest_item = false
	_world_root.clip_text = true
	add_child(_world_root)
	_world_root.item_selected.connect(func(_index: int) -> void: _fill_world_items(); _inspect_world(); _update_buttons())
	_world_items.custom_minimum_size.y = 100
	_world_items.item_selected.connect(func(_index: int) -> void: _inspect_world(); _update_buttons())
	add_child(_world_items)
	_world_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_world_details)
	var world_actions := HBoxContainer.new()
	add_child(world_actions)
	_button(world_actions, "Collect selected", _world_action.bind("pickup"), "pickup")
	_button(world_actions, "Drop selected", _world_action.bind("drop"), "drop")
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_world_status)
	_label("Active tool · resource extractor")
	for id in ["deposit.iron", "deposit.ice", "deposit.regolith"]:
		_deposit.add_item({"deposit.iron": "Iron ore", "deposit.ice": "Ice", "deposit.regolith": "Regolith"}[id])
		_deposit.set_item_metadata(_deposit.item_count - 1, id)
	add_child(_deposit)
	add_child(_carrier)
	_button(self, "Extract 1 kg using active tool", _use_tool)
	_work_cycles.min_value = 1
	_work_cycles.max_value = 10
	_work_cycles.value = 2
	_work_cycles.suffix = " cycles of 1 kg"
	add_child(_work_cycles)
	_work_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_work_status)
	_button(self, "Start sustained extraction", _sustained_action.bind("start_tool_extract"))
	_button(self, "Resume reserved extraction", _sustained_action.bind("resume_tool_extract"))
	_button(self, "Cancel and release remaining source reservation", _sustained_action.bind("cancel_tool_extract"))
	_label("Tool component maintenance · select a tool above, then a component")
	add_child(_tool_parts)
	_button(self, "Maintain selected component at workstation", _repair_component)
	_label("Tool parts · manufacture from workstation materials")
	add_child(_part_blueprints)
	_button(self, "Manufacture selected part", _part_action.bind("fabricate_tool_part"))
	_label("Owned loose part · use an equipment mount to replace or upgrade")
	add_child(_loose_parts)
	add_child(_tool_mounts)
	_button(self, "Fit loose part in selected tool mount", _part_action.bind("fit_tool_part"))
	_button(self, "Detach selected tool mount into inventory", _part_action.bind("detach_tool_part"))
	_button(self, "Recycle selected loose part", _part_action.bind("recycle_tool_part"))
	_label("Equip the extractor in a hand, make that hand active, carry a canister and approach the source. Mounted extraction remains available through Workstation. Crowbar world interactions are a later integration.")
	add_child(_result)
	remote.command_completed.connect(_completed)
	remote.connection_closed.connect(_disconnected)
	_update_buttons()


func observe(frame: Dictionary) -> void:
	_record = frame["inventory"]
	_production = frame["production"]
	_nearby = frame["world_items"]
	_tools = frame.get("tools", {})
	var work: Dictionary = _production.get("tool_extraction", {})
	_work_status.text = "No sustained extraction reserved by you."
	if not work.is_empty():
		_work_status.text = "Extraction %s · %d completed, %d reserved · %s" % [work["status"], work["completed_cycles"], work["remaining_cycles"], work["pause_reason"]]
	var loose_ids: Array = []
	for part in _tools.get("loose_parts", []): loose_ids.append(part["part_id"])
	_fill_picker(_loose_parts, loose_ids)
	var previous_blueprint: String = str(_part_blueprints.get_item_metadata(_part_blueprints.selected)) if _part_blueprints.selected >= 0 else ""
	_part_blueprints.clear()
	for id in _tools.get("part_blueprints", {}):
		var blueprint: Dictionary = _tools["part_blueprints"][id]
		_part_blueprints.add_item("%s · %d J" % [blueprint["name"], blueprint["fabrication_energy_joules"]])
		_part_blueprints.set_item_metadata(_part_blueprints.item_count - 1, id)
		if id == previous_blueprint: _part_blueprints.select(_part_blueprints.item_count - 1)
	var world_containers: Array = []
	for container in _nearby.get("containers", []):
		world_containers.append(container["container_id"])
	var view_key: String = JSON.stringify([_record, _production["state_revision"], _tools.get("state_revision", -1), _nearby])
	if view_key == _view_key:
		return
	_view_key = view_key
	_summary.text = "Owned including nested storage: %.2f kg · %d items" % [float(_record["mass_milligrams"]) / 1000000.0, _record["items"].size()]
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
	_fill_picker(_world_root, world_containers)
	_fill_world_items()
	_inspect()
	_inspect_world()
	_update_buttons()


func _fill_world_items() -> void:
	var selected: String = _selected_id(_world_items)
	var selected_root: String = ""
	if not _world_items.get_selected_items().is_empty():
		selected_root = _world_items.get_item_metadata(_world_items.get_selected_items()[0])["container_id"]
	_world_items.clear()
	for container in _nearby.get("containers", []):
		if container["container_id"] != _picker_id(_world_root): continue
		for entry in container["items"]:
			_world_items.add_item("%s · %s · direct tray contents" % [NAMES.get(entry["definition_id"], "Equipment"), entry["item_id"]])
			_world_items.set_item_metadata(_world_items.item_count - 1, entry.duplicate(true))
			if entry["item_id"] == selected and container["container_id"] == selected_root:
				_world_items.select(_world_items.item_count - 1)


func _fill_picker(picker: OptionButton, ids: Array, all_items: bool = false) -> void:
	var previous: Variant = picker.get_item_metadata(picker.selected) if picker.selected >= 0 else null
	picker.clear()
	var restored: int = -1
	if all_items:
		picker.add_item("All owned items (including nested)")
		picker.set_item_metadata(0, "*")
		if previous == "*": restored = 0
	for id in ids:
		picker.add_item(_item_name(id) if picker == _loose_parts else (_slot_name(id) if picker == _slot else _container_name(id)))
		picker.set_item_metadata(picker.item_count - 1, id)
		if picker == _world_root:
			for container in _nearby.get("containers", []):
				if container["container_id"] == id:
					picker.set_item_text(picker.item_count - 1, "%s · observed %.2f m" % [id, float(container["distance_millimetres"]) / 1000.0])
		if previous == id: restored = picker.item_count - 1
	var strict: bool = picker in [_source, _destination, _slot, _world_root]
	# Initialize once; a vanished ID must never silently retarget to the first row.
	var initialized: bool = _initialized_pickers.has(picker.get_instance_id())
	picker.select(restored if strict and initialized else (restored if restored >= 0 else (0 if picker.item_count > 0 else -1)))
	if picker.item_count > 0: _initialized_pickers[picker.get_instance_id()] = true


static func _picker_id(picker: OptionButton) -> String:
	return str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""


func _fill_items() -> void:
	var selected: String = _selected_id(_items)
	_items.clear()
	if _record.is_empty():
		return
	var source: String = _picker_id(_source)
	for item in _record["items"]:
		if source != "*" and item["container_id"] != source:
			continue
		var name: String = _item_name(item["item_id"])
		_items.add_item("%s · %s · %s" % [name, item["item_id"], _container_name(item["container_id"])])
		_items.set_item_metadata(_items.item_count - 1, item)
		if item["item_id"] == selected:
			_items.select(_items.item_count - 1)


func _inspect() -> void:
	var id: String = _selected_id(_items)
	_details.text = "Select an item to inspect its condition, mass and contents."
	var selected_part: String = str(_tool_parts.get_item_metadata(_tool_parts.selected)) if _tool_parts.selected >= 0 else ""
	_tool_parts.clear()
	var previous_mount: String = str(_tool_mounts.get_item_metadata(_tool_mounts.selected)) if _tool_mounts.selected >= 0 else ""
	_tool_mounts.clear()
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
		for slot in assembly["slots"]:
			_tool_mounts.add_item("%s · %s" % [slot, "empty" if assembly["slots"][slot] == "" else "installed"])
			_tool_mounts.set_item_metadata(_tool_mounts.item_count - 1, slot)
			if slot == previous_mount: _tool_mounts.select(_tool_mounts.item_count - 1)
		_details.text += "\nComponent condition (authoritative):"
		for part in assembly["parts"]:
			var text: String = "%s · %s · %.4f%%" % [part["name"], part["material_name"], float(part["integrity_ppm"]) / 10000.0]
			_details.text += "\n" + text
			_tool_parts.add_item(text)
			_tool_parts.set_item_metadata(_tool_parts.item_count - 1, part["part_id"])
			if part["part_id"] == selected_part: _tool_parts.select(_tool_parts.item_count - 1)
		for action in assembly["actions"]:
			_details.text += "\n%s: %s" % [action, "available" if assembly["actions"][action]["available"] else "missing " + ", ".join(PackedStringArray(assembly["actions"][action]["missing_functions"]))]
	for part in _tools.get("loose_parts", []):
		if part["part_id"] != id: continue
		_details.text += "\n%s · %s · component %.4f%%" % [part["name"], part["material_name"], float(part["integrity_ppm"]) / 10000.0]
		_tool_parts.add_item(part["name"])
		_tool_parts.set_item_metadata(0, part["part_id"])


func _open_storage(index: int) -> void:
	var id: String = _items.get_item_metadata(index)["item_id"]
	for container in _record.get("container_records", []):
		if container["owner_item_id"] == id:
			for entry in range(_source.item_count):
				if _source.get_item_metadata(entry) == container["container_id"]:
					_source.select(entry)
					_fill_items()
					_inspect()
					_update_buttons()
					return


func _inventory_prerequisite(operation: String) -> String:
	var list: ItemList = _world_items if operation == "pickup" else _items
	var root_id: String = _picker_id(_world_root)
	return PlayerInventoryPresentation.prerequisite(operation, _record, _nearby, _selected_id(list), _picker_id(_destination), _picker_id(_slot), root_id)


func _self_action(operation: String) -> void:
	if not _pending.is_empty(): return
	var reason: String = _inventory_prerequisite(operation)
	if not reason.is_empty():
		_result.text = reason
		return
	var payload: Dictionary = {"operation": operation, "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": _record["inventory_revision"]}
	if operation in ["equip", "move"]:
		var item: Dictionary = PlayerInventoryPresentation.item(_record, _selected_id(_items))
		payload["item_id"] = item["item_id"]
		payload["source_container_id"] = item["container_id"]
	if operation in ["equip", "unequip", "select_hand"]:
		payload["slot_id"] = _picker_id(_slot)
	if operation in ["move", "unequip"]:
		payload["destination_container_id"] = _picker_id(_destination)
	_submit("self", payload)
	if not _pending.is_empty():
		_pending_inventory = payload.duplicate(true)
		_result.text = PlayerInventoryPresentation.pending_text(_pending_inventory)

func _world_action(operation: String) -> void:
	if _record.is_empty() or not _pending.is_empty():
		return
	var reason: String = _inventory_prerequisite(operation)
	if not reason.is_empty():
		_result.text = reason
		_world_status.text = reason
		return
	var list: ItemList = _world_items if operation == "pickup" else _items
	var item: Dictionary = list.get_item_metadata(list.get_selected_items()[0])
	var payload: Dictionary = {"operation": operation, "item_id": item["item_id"], "world_container_id": item["container_id"] if operation == "pickup" else _world_root.get_item_metadata(_world_root.selected), "destination_container_id": _destination.get_item_metadata(_destination.selected) if operation == "pickup" else "", "slot_id": "", "expected_revision": _record["inventory_revision"]}
	_submit("world", payload)
	if not _pending.is_empty():
		_pending_world = payload.duplicate(true)
		_result.text = "Waiting for host · %s %s · world %s%s · revision %d. Ownership changes only after host acceptance." % [operation, payload["item_id"], payload["world_container_id"], " → " + str(payload["destination_container_id"]) if operation == "pickup" else "", payload["expected_revision"]]
	_world_status.text = _result.text
	_update_buttons()


func _inspect_world() -> void:
	_world_details.text = "Select a nearby item. Listed roots are host-observed as accessible and in reach; capacity and ownership are rechecked by the host."
	if _nearby.get("containers", []).is_empty():
		_world_details.text = "No accessible world storage in the current host reach view. Approach a tray and wait for a fresh observation."
		return
	var selected: PackedInt32Array = _world_items.get_selected_items()
	if selected.is_empty(): return
	var item: Dictionary = _world_items.get_item_metadata(selected[0])
	for container in _nearby.get("containers", []):
		if container["container_id"] != item["container_id"]: continue
		_world_details.text = "%s · world storage %s\nObserved distance %.2f m · accessible/in reach in latest host view. Not carried by you; collect into owned storage. Only direct contents are visible; nested contents and tray capacity are unavailable. Host rechecks reach, capacity and ownership." % [item["item_id"], container["container_id"], float(container["distance_millimetres"]) / 1000.0]


func _disconnected(message: String) -> void:
	_record = {}
	_production = {}
	_nearby = {}
	_tools = {}
	_pending = ""
	_pending_world.clear()
	_pending_inventory.clear()
	_view_key = ""
	_initialized_pickers.clear()
	for list in [_items, _world_items]: list.clear()
	for picker in [_source, _destination, _slot, _world_root, _carrier, _tool_parts, _tool_mounts, _loose_parts, _part_blueprints]: picker.clear()
	for label in [_summary, _equipment, _details, _world_details, _work_status, _storage_status]: label.text = ""
	_result.text = message + "; pending target cleared; its outcome is unknown. Reconnect and refresh before retrying."
	_world_status.text = _result.text
	_update_buttons()


func _use_tool() -> void:
	if not _pending.is_empty(): return
	if _record.is_empty():
		return
	if _carrier.selected < 0:
		_result.text = "Carry a resource canister first."
		return
	_submit("tool_extract", {"deposit_id": _deposit.get_item_metadata(_deposit.selected), "carrier_id": _carrier.get_item_metadata(_carrier.selected), "amount_milligrams": 1000000, "expected_revision": _production["state_revision"]}, true)


func switch_active_hand() -> void:
	_self_action("switch_hand")


func _repair_component() -> void:
	if not _pending.is_empty(): return
	if _tool_parts.selected < 0 or _tools.is_empty():
		_result.text = "Select a tool and component first."
		return
	_submit("repair_tool_component", {"part_id": _tool_parts.get_item_metadata(_tool_parts.selected), "amount_ppm": 1000000, "expected_revision": _production["state_revision"], "expected_tool_revision": _tools["state_revision"]}, true)


func _sustained_action(operation: String) -> void:
	if not _pending.is_empty(): return
	if _production.is_empty(): return
	var payload: Dictionary = {"expected_revision": _production["state_revision"]}
	if operation == "start_tool_extract":
		if _carrier.selected < 0: return
		payload.merge({"deposit_id": _deposit.get_item_metadata(_deposit.selected), "carrier_id": _carrier.get_item_metadata(_carrier.selected), "cycles": int(_work_cycles.value)})
	_submit(operation, payload, true)


func _part_action(operation: String) -> void:
	if not _pending.is_empty(): return
	if _tools.is_empty() or _production.is_empty(): return
	var payload: Dictionary = {"expected_revision": _production["state_revision"], "expected_tool_revision": _tools["state_revision"]}
	if operation == "fabricate_tool_part":
		if _part_blueprints.selected < 0: return
		payload["blueprint_id"] = _part_blueprints.get_item_metadata(_part_blueprints.selected)
	if operation in ["fit_tool_part", "recycle_tool_part"]:
		if _loose_parts.selected < 0:
			_result.text = "Select an owned loose part first."
			return
		payload["part_id"] = _loose_parts.get_item_metadata(_loose_parts.selected)
	if operation in ["fit_tool_part", "detach_tool_part"]:
		if _tool_mounts.selected < 0:
			_result.text = "Inspect a manufactured tool and select its mount."
			return
		payload["item_id"] = _selected_id(_items)
		payload["slot_id"] = _tool_mounts.get_item_metadata(_tool_mounts.selected)
	_submit(operation, payload, true)


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
		var was_world: bool = not _pending_world.is_empty()
		_pending = ""
		_pending_world.clear()
		_pending_inventory.clear()
		_result.text = "Host accepted action. Inventory follows the latest host view." if result.is_success else "Host rejected action: " + result.message
		if was_world: _world_status.text = _result.text
		_update_buttons()


func _update_buttons() -> void:
	for button in _buttons:
		button.disabled = _record.is_empty() or not _pending.is_empty()
	for operation in _inventory_buttons:
		var button: Button = _inventory_buttons[operation]
		var reason: String = _inventory_prerequisite(operation)
		button.disabled = button.disabled or not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else "Host rechecks current ownership, reach, capacity, compatibility and revision."
	for picker in [_source, _destination, _slot, _world_root]:
		picker.disabled = _record.is_empty() or not _pending.is_empty()
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE if not _pending.is_empty() else Control.MOUSE_FILTER_STOP
	_world_items.mouse_filter = _items.mouse_filter
	_items.set_process_input(_pending.is_empty())
	_world_items.set_process_input(_pending.is_empty())
	_storage_status.text = PlayerInventoryPresentation.storage_hint(_record, _picker_id(_destination)) if not _record.is_empty() else ""


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)


func _button(parent: Node, text: String, callback: Callable, inventory_operation: String = "") -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons.append(button)
	if not inventory_operation.is_empty(): _inventory_buttons[inventory_operation] = button


static func _selected_id(list: ItemList) -> String:
	var selected: PackedInt32Array = list.get_selected_items()
	return "" if selected.is_empty() else str(list.get_item_metadata(selected[0])["item_id"])


func _item_name(id: String) -> String:
	for part in _tools.get("loose_parts", []):
		if part["part_id"] == id: return part["name"] + " · " + part["material_name"]
	for item in _record.get("items", []):
		if item["item_id"] == id:
			return NAMES.get(item["definition_id"], "Equipment")
	return "Equipment"


func _container_name(id: String) -> String:
	if id == _record.get("body_container_id"):
		return "Carried loose · " + id
	for container in _record.get("container_records", []):
		if container["container_id"] == id:
			return "%s · %s" % [_item_name(container["owner_item_id"]), id]
	return "Storage · " + id


static func _slot_name(id: String) -> String:
	return id.replace("hand.", "").replace("_", " ").capitalize()
