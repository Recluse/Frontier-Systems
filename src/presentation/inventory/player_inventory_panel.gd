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
var _transfer_preview := Label.new()
var _world_transfer_preview := Label.new()
var _initialized_pickers: Dictionary = {}
var _source := OptionButton.new()
var _closure_target := OptionButton.new()
var _closure_selected_id: String = ""
var _closure_picker_key: String = ""
var _closure_status := Label.new()
var _closure_feedback := Label.new()
var _closure_buttons: Dictionary = {}
var _pending_closure: Dictionary = {}
var _destination := OptionButton.new()
var _slot := OptionButton.new()
var _deposit := OptionButton.new()
var _carrier := OptionButton.new()
var _summary := Label.new()
var _details := Label.new()
var _equipment := Label.new()
var _active_tool := Label.new()
var _equipment_record: Dictionary = {}
var _equipment_observed_at: int = -1
var _equipment_tick: int = -1
var _equipment_revision: int = -1
var _result := Label.new()
var _buttons: Array[Button] = []
var _pending: String = ""
var _shown_pending: String = ""
var _view_key: String = ""
var _tools: Dictionary = {}
var _tool_parts := OptionButton.new()
var _tool_mounts := OptionButton.new()
var _loose_parts := OptionButton.new()
var _part_blueprints := OptionButton.new()
var _component_details := Label.new()
var _maintenance_targets := Label.new()
var _component_selections: Dictionary = {}
var _component_buttons: Dictionary = {}
var _pending_component: Dictionary = {}
var _inspected_tool: String = ""
var _work_cycles := SpinBox.new()
var _work_status := Label.new()
var _work_targets := Label.new()
const EQUIPMENT_OBSERVATION_TIMEOUT_MSEC: int = 5000


func configure(remote: RemoteWorldRuntime) -> void:
	_remote = remote
	if get_parent() is ScrollContainer:
		var scroll := get_parent() as ScrollContainer
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.focus_mode = Control.FOCUS_ALL
		scroll.gui_input.connect(_scroll_input)
	for picker in [_source, _destination, _slot, _deposit, _carrier, _tool_parts, _tool_mounts, _loose_parts, _part_blueprints]:
		picker.fit_to_longest_item = false
		picker.clip_text = true
	add_theme_constant_override("separation", 10)
	_label("Inventory · portable storage · tools")
	for label in [_summary, _equipment, _details, _result]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	add_child(_equipment)
	_label("Browse owned knowledge (double-click a backpack or pouch to browse)")
	add_child(_source)
	_source.item_selected.connect(func(_index: int) -> void: _fill_items(); _inspect(); _update_buttons())
	_items.custom_minimum_size.y = 180
	_items.item_selected.connect(func(_index: int) -> void: _inspect(); _update_buttons())
	_items.item_activated.connect(_open_storage)
	add_child(_items)
	add_child(_details)
	_label("Physical owned-container closure · select the exact container")
	_closure_target.fit_to_longest_item = false
	_closure_target.clip_text = true
	add_child(_closure_target)
	_closure_target.item_selected.connect(func(index: int) -> void: _closure_selected_id = str(_closure_target.get_item_metadata(index)); _update_buttons())
	for label in [_closure_status, _closure_feedback]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(label)
	var closure_actions := HFlowContainer.new()
	add_child(closure_actions)
	for operation in ["open_container", "close_container"]:
		_button(closure_actions, "Open container" if operation == "open_container" else "Close container", _closure_action.bind(operation))
		_closure_buttons[operation] = _buttons[-1]
	_label("Selected equipment slot · selection alone does not make a hand active")
	add_child(_slot)
	var equipment_actions := HFlowContainer.new()
	add_child(equipment_actions)
	_button(equipment_actions, "Equip", _self_action.bind("equip"), "equip")
	_button(equipment_actions, "Unequip", _self_action.bind("unequip"), "unequip")
	_button(equipment_actions, "Switch hand", _self_action.bind("switch_hand"), "switch_hand")
	_button(self, "Make selected hand active", _self_action.bind("select_hand"), "select_hand")
	_label("Destination storage")
	add_child(_destination)
	_storage_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_storage_status)
	_transfer_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_transfer_preview)
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
	_world_transfer_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_world_transfer_preview)
	var world_actions := HFlowContainer.new()
	add_child(world_actions)
	_button(world_actions, "Collect selected", _world_action.bind("pickup"), "pickup")
	_button(world_actions, "Drop selected", _world_action.bind("drop"), "drop")
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_world_status)
	_label("Hand-tool extraction · uses host-observed active equipment")
	_active_tool.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_active_tool)
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
	_work_targets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_work_targets)
	_deposit.item_selected.connect(func(_index: int) -> void: _update_buttons())
	_carrier.item_selected.connect(func(_index: int) -> void: _update_buttons())
	_work_cycles.value_changed.connect(func(_value: float) -> void: _update_buttons())
	_work_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_work_status)
	_button(self, "Start sustained extraction", _sustained_action.bind("start_tool_extract"))
	_button(self, "Resume reserved extraction", _sustained_action.bind("resume_tool_extract"))
	_button(self, "Cancel and release remaining source reservation", _sustained_action.bind("cancel_tool_extract"))
	_label("Tool component maintenance · select a tool above, then a component")
	_component_picker(_tool_parts, "Repair component · mounted or inspected detached")
	_maintenance_targets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_maintenance_targets)
	_button(self, "Maintain selected component at workstation", _repair_component)
	_label("Tool parts · manufacture from workstation materials")
	_component_picker(_part_blueprints, "Fabrication blueprint")
	_button(self, "Manufacture selected part", _part_action.bind("fabricate_tool_part"), "fabricate_tool_part")
	_label("Owned loose part · use an equipment mount to replace or upgrade")
	_component_picker(_loose_parts, "Owned loose part")
	_component_picker(_tool_mounts, "Equipment mount")
	_button(self, "Fit loose part in selected tool mount", _part_action.bind("fit_tool_part"), "fit_tool_part")
	_button(self, "Detach selected tool mount into inventory", _part_action.bind("detach_tool_part"), "detach_tool_part")
	_button(self, "Recycle selected loose part", _part_action.bind("recycle_tool_part"), "recycle_tool_part")
	_component_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label("Observed component prerequisites · scroll to read all costs and host checks")
	add_child(_component_details)
	for picker in [_part_blueprints, _loose_parts, _tool_mounts, _tool_parts]:
		picker.item_selected.connect(func(_index: int) -> void: _update_buttons())
	_label("Equip the extractor in a hand, make that hand active, carry a canister and approach the source. Mounted extraction remains available through Workstation. Crowbar world interactions are a later integration.")
	for guidance: Label in [_equipment, _active_tool, _maintenance_targets, _component_details, _work_status, _work_targets, _storage_status, _transfer_preview, _world_transfer_preview, _world_status, _result, _closure_status, _closure_feedback]:
		guidance.focus_mode = Control.FOCUS_ALL
		guidance.gui_input.connect(_guidance_input.bind(guidance))
		guidance.tooltip_text = "Tab to review; Up/Down or Page Up/Page Down scroll the Inventory pane."
	_result.tooltip_text = "Action feedback; Tab to review the exact pending target or host receipt; Up/Down or Page Up/Page Down to scroll."
	add_child(_result)
	remote.command_completed.connect(_completed)
	remote.connection_closed.connect(_disconnected)
	_update_buttons()


func observe(frame: Dictionary) -> void:
	_record = frame.get("inventory", {})
	_observe_equipment(frame)
	if _record.is_empty():
		_summary.text = "Inventory observation unavailable."
		_view_key = ""
		_tools = {}
		_production = {}
		_work_status.text = "Work-cycle observation unavailable."
		_update_buttons()
		return
	_production = frame.get("production", {})
	_nearby = frame.get("world_items", {})
	_tools = frame.get("tools", {})
	var work: Dictionary = _production.get("tool_extraction", {})
	_work_status.text = "Work-cycle observation unavailable." if _production.is_empty() else "No sustained extraction reserved by you; this does not confirm past completion."
	if not work.is_empty():
		_work_status.text = "Extraction %s · %d completed, %d reserved · %s" % [work["status"], work["completed_cycles"], work["remaining_cycles"], work["pause_reason"]]
	var loose: Dictionary = {}
	var blueprints: Dictionary = {}
	if ToolObservationValidation.valid(_tools):
		for part in _tools["loose_parts"]: loose[part["part_id"]] = part["name"] + " · " + part["material_name"]
		for id in _tools["part_blueprints"]: blueprints[id] = _tools["part_blueprints"][id]["name"]
	EquipmentPrerequisiteView.fill(_loose_parts, loose, "Select an owned loose part")
	EquipmentPrerequisiteView.fill(_part_blueprints, blueprints, "Select a part blueprint")
	var world_containers: Array = []
	for container in _nearby.get("containers", []):
		world_containers.append(container["container_id"])
	var view_key: String = JSON.stringify([_record, _production, _tools, _nearby])
	if view_key == _view_key:
		_update_buttons()
		return
	_view_key = view_key
	_summary.text = "Owned including nested storage: %.2f kg · %d items" % [float(_record["mass_milligrams"]) / 1000000.0, _record["items"].size()]
	var containers: Array = _record.get("container_ids", [])
	_fill_picker(_source, containers, true)
	_fill_picker(_destination, containers)
	_fill_picker(_slot, _record["slot_ids"])
	var carriers: Dictionary = {}
	for id in _production.get("cargo", {}): carriers[id] = "Canister"
	EquipmentPrerequisiteView.fill(_carrier, carriers, "Select a receiving canister")
	_fill_items()
	_fill_picker(_world_root, world_containers)
	_fill_world_items()
	_inspect()
	_inspect_world()
	_update_buttons()


## Freshness only fences presentation claims; it neither authorizes nor retries commands.
func _observe_equipment(frame: Dictionary) -> void:
	var revision: int = int(_record.get("inventory_revision", -1))
	var tick: int = int(frame.get("tick_number", -1))
	if _record.is_empty() or revision < _equipment_revision or (tick >= 0 and tick < _equipment_tick):
		_equipment_record = {}
		_update_active_equipment()
		return
	if tick < 0 or tick > _equipment_tick or _equipment_observed_at < 0:
		_equipment_observed_at = Time.get_ticks_msec()
	_equipment_tick = maxi(tick, _equipment_tick)
	_equipment_revision = revision
	_equipment_record = _record.duplicate(true) if Time.get_ticks_msec() - _equipment_observed_at <= EQUIPMENT_OBSERVATION_TIMEOUT_MSEC else {}
	_update_active_equipment()


func _process(_delta: float) -> void:
	if not _equipment_record.is_empty() and _equipment_observed_at >= 0 and Time.get_ticks_msec() - _equipment_observed_at > EQUIPMENT_OBSERVATION_TIMEOUT_MSEC:
		_equipment_record = {}
		_update_active_equipment()
		_update_buttons()


func _update_active_equipment() -> void:
	var text: String = PlayerInventoryPresentation.active_equipment(_equipment_record, _selected_id(_items), _picker_id(_slot))
	if not _pending_inventory.is_empty() and _pending_inventory.get("operation") in ["equip", "unequip", "select_hand", "switch_hand"]:
		text += "\nEquipment command pending; outcome unconfirmed until its matching host receipt. Display follows fresh observations."
	_active_tool.text = text
	var equipped := PackedStringArray()
	for binding in _equipment_record.get("equipped", []):
		equipped.append("%s: %s" % [binding["slot_id"], binding["item_id"]])
	_equipment.text = text + ("\nObserved equipment bindings: " + ", ".join(equipped) if not equipped.is_empty() else "")


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
	if id != _inspected_tool:
		_tool_parts.clear()
		_tool_mounts.clear()
		_inspected_tool = id
	var parts: Dictionary = {}
	var mounts: Dictionary = {}
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
			mounts[slot] = "Empty" if assembly["slots"][slot] == "" else "Installed " + str(assembly["slots"][slot])
		_details.text += "\nComponent condition (authoritative):"
		for part in assembly["parts"]:
			var text: String = "%s · %s · %.4f%%" % [part["name"], part["material_name"], float(part["integrity_ppm"]) / 10000.0]
			_details.text += "\n" + text
			parts[part["part_id"]] = text
		for action in assembly["actions"]:
			_details.text += "\n%s: %s" % [action, "available" if assembly["actions"][action]["available"] else "missing " + ", ".join(PackedStringArray(assembly["actions"][action]["missing_functions"]))]
	for part in _tools.get("loose_parts", []):
		if part["part_id"] != id: continue
		_details.text += "\n%s · %s · component %.4f%%" % [part["name"], part["material_name"], float(part["integrity_ppm"]) / 10000.0]
		parts[part["part_id"]] = part["name"]
	EquipmentPrerequisiteView.fill(_tool_parts, parts, "Select a component")
	EquipmentPrerequisiteView.fill(_tool_mounts, mounts, "Select a mount")


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
	return PlayerInventoryPresentation.prerequisite(operation, _record, _nearby, _selected_id(list), _picker_id(_destination), _picker_id(_slot), root_id, _equipment_record)


func _fill_closure_target() -> void:
	var ids: Array[String] = []
	for container in _record.get("container_records", []):
		if not str(container.get("owner_item_id", "")).is_empty(): ids.append(str(container["container_id"]))
	var key: String = JSON.stringify([ids, _closure_selected_id])
	if key == _closure_picker_key: return
	_closure_picker_key = key
	_closure_target.clear()
	_closure_target.add_item("Select owned storage")
	_closure_target.set_item_metadata(0, "")
	var selected: int = 0
	for id in ids:
		_closure_target.add_item(id)
		_closure_target.set_item_metadata(_closure_target.item_count - 1, id)
		if id == _closure_selected_id: selected = _closure_target.item_count - 1
	if selected == 0 and not _closure_selected_id.is_empty():
		_closure_target.add_item(_closure_selected_id + " · unavailable")
		selected = _closure_target.item_count - 1
		_closure_target.set_item_metadata(selected, _closure_selected_id)
	_closure_target.select(selected)


func _closure_action(operation: String) -> void:
	if not _pending.is_empty() or not operation in ["open_container", "close_container"]: return
	var reason: String = PlayerInventoryPresentation.closure_prerequisite(_equipment_record, _closure_selected_id)
	if not reason.is_empty():
		_closure_feedback.text = reason
		return
	var payload: Dictionary = {"container_id": _closure_selected_id, "expected_revision": int(_equipment_record["inventory_revision"])}
	_submit(operation, payload)
	if not _pending.is_empty():
		_pending_closure = payload.duplicate(true)
		_pending_closure["operation"] = operation
		_pending_closure["request_id"] = _pending
		_closure_feedback.text = "Waiting for host · " + PlayerInventoryPresentation.closure_targets(_pending_closure) + "\nOutcome unconfirmed; no automatic retry."
		_result.text = _closure_feedback.text
	else:
		_closure_feedback.text = _result.text


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
		_update_active_equipment()

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
	if not _pending_closure.is_empty():
		_closure_feedback.text = "Disconnected · outcome unknown · " + PlayerInventoryPresentation.closure_targets(_pending_closure) + "\nRefresh host observation; no automatic retry."
	_pending_closure.clear()
	_equipment_record = {}
	_equipment_observed_at = -1
	_equipment_tick = -1
	_equipment_revision = -1
	_record = {}
	_production = {}
	_nearby = {}
	_tools = {}
	_pending = ""
	_pending_world.clear()
	_pending_inventory.clear()
	_pending_component.clear()
	_inspected_tool = ""
	_view_key = ""
	_initialized_pickers.clear()
	for list in [_items, _world_items]: list.clear()
	for picker in [_source, _destination, _slot, _world_root, _carrier, _tool_parts, _tool_mounts, _loose_parts, _part_blueprints]: picker.clear()
	for label in [_summary, _equipment, _details, _world_details, _work_status, _storage_status, _transfer_preview, _world_transfer_preview]: label.text = ""
	_result.text = message + "; pending target cleared; its outcome is unknown. Reconnect and refresh before retrying."
	_world_status.text = _result.text
	_update_buttons()


func _use_tool() -> void:
	if not _pending.is_empty(): return
	if _record.is_empty():
		return
	if _picker_id(_carrier).is_empty() or _carrier.is_item_disabled(_carrier.selected):
		_result.text = "Carry a resource canister first."
		return
	var payload: Dictionary = {"deposit_id": _deposit.get_item_metadata(_deposit.selected), "carrier_id": _carrier.get_item_metadata(_carrier.selected), "amount_milligrams": 1000000, "expected_revision": _production["state_revision"]}
	_submit("tool_extract", payload, true)
	_pin_component_intent("tool_extract", payload)


func switch_active_hand() -> void:
	_self_action("switch_hand")


func _repair_component() -> void:
	if not _pending.is_empty(): return
	if _picker_id(_tool_parts).is_empty() or _tool_parts.is_item_disabled(_tool_parts.selected) or _tools.is_empty():
		_result.text = "Select a tool and component first."
		return
	var payload: Dictionary = {"part_id": _tool_parts.get_item_metadata(_tool_parts.selected), "amount_ppm": 1000000, "expected_revision": _production["state_revision"], "expected_tool_revision": _tools["state_revision"]}
	_submit("repair_tool_component", payload, true)
	_pin_component_intent("repair_tool_component", payload)


func _sustained_action(operation: String) -> void:
	if not _pending.is_empty(): return
	if _production.is_empty(): return
	var payload: Dictionary = {"expected_revision": _production["state_revision"]}
	if operation == "start_tool_extract":
		if _picker_id(_carrier).is_empty() or _carrier.is_item_disabled(_carrier.selected): return
		payload.merge({"deposit_id": _deposit.get_item_metadata(_deposit.selected), "carrier_id": _carrier.get_item_metadata(_carrier.selected), "cycles": int(_work_cycles.value)})
	_submit(operation, payload, true)
	_pin_component_intent(operation, payload)


func _component_prerequisite(operation: String) -> String:
	if not ToolObservationValidation.valid(_tools) or not WorkstationResourceView.valid(_production):
		return "Wait for current component and workstation observations."
	if not _production["can_operate"]: return "Workstation access unavailable in the host view."
	var station: String = "printer" if operation == "fabricate_tool_part" else ("recycler" if operation == "recycle_tool_part" else "construction")
	if not _production["powered"].get(station, false): return station + " power is off in the host view."
	if operation == "fabricate_tool_part":
		var id: String = _picker_id(_part_blueprints)
		if not _tools["part_blueprints"].has(id): return "Select an observed part blueprint."
		var blueprint: Dictionary = _tools["part_blueprints"][id]
		if _production["energy_joules"] < blueprint["fabrication_energy_joules"]: return "Observed station energy is below fabrication cost."
		for material in blueprint["materials"]:
			if _production["store"].get(material, 0) < blueprint["materials"][material]: return "Shared stock shortfall: " + material
	if operation in ["fit_tool_part", "recycle_tool_part"]:
		var found: bool = false
		for part in _tools["loose_parts"]:
			if part["part_id"] != _picker_id(_loose_parts): continue
			found = true
			if operation == "recycle_tool_part":
				var matched: bool = false
				for blueprint in _tools["part_blueprints"].values():
					if blueprint["definition_id"] != part["definition_id"] or blueprint["material_id"] != part["material_id"]: continue
					matched = true
					if _production["energy_joules"] < blueprint["salvage_energy_joules"]: return "Observed station energy is below recycling cost."
					break
				if not matched: return "No observed matching recycling specification."
		if not found: return "Select a currently owned loose part."
	if operation in ["fit_tool_part", "detach_tool_part"]:
		if not _production["structures"].has(_selected_id(_items)): return "Starter shells cannot use manufactured-part actions. Select owned fabricated equipment."
		var found: bool = false
		for assembly in _tools["assemblies"]:
			if assembly["assembly_id"] != _selected_id(_items): continue
			if not assembly["slots"].has(_picker_id(_tool_mounts)): continue
			if operation == "detach_tool_part" and assembly["slots"][_picker_id(_tool_mounts)] == "": return "Selected mount is already empty."
			found = true
		if not found: return "Select an owned manufactured tool and its observed mount."
	return ""


func _part_action(operation: String) -> void:
	if not _pending.is_empty(): return
	var reason: String = _component_prerequisite(operation)
	if not reason.is_empty():
		_result.text = reason
		return
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
	_pin_component_intent(operation, payload)


func _pin_component_intent(operation: String, payload: Dictionary) -> void:
	if not _pending.is_empty():
		_pending_component = payload.duplicate(true)
		_pending_component["operation"] = operation
		if operation in ["resume_tool_extract", "cancel_tool_extract"]:
			var work: Dictionary = _production.get("tool_extraction", {})
			for field: String in ["request_id", "tool_id", "deposit_id", "carrier_id"]:
				if work.has(field): _pending_component["observed_reserved_" + field] = work[field]
		_result.text = "Waiting for host\n" + _pending_component_text() + "\nNo repair, output, mount change or work-cycle completion confirmed."
		_update_buttons()


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
		_result.text = EngineeringFailureGuidance.describe(queued, queued.message)
	_update_buttons()


func _completed(command: SimulationCommand, result: ServiceResult) -> void:
	if String(command.command_id) == _pending:
		if not _pending_closure.is_empty():
			var expected: Dictionary = {"container_id": _pending_closure["container_id"], "expected_revision": _pending_closure["expected_revision"]}
			if command.operation != _pending_closure["operation"] or command.payload != expected: return
			if not result.is_success and result.error_code == &"remote_disconnected":
				_disconnected("Host connection closed")
				return
			_closure_feedback.text = ("Host accepted · " if result.is_success else "Host rejected · ") + PlayerInventoryPresentation.closure_targets(_pending_closure)
			_closure_feedback.text += "\nClosure follows fresh host observations." if result.is_success else "\n" + result.message
			_pending_closure.clear()
		var was_world: bool = not _pending_world.is_empty()
		var exact_targets: String = _pending_component_text() if not _pending_component.is_empty() else ""
		_pending = ""
		_pending_world.clear()
		_pending_inventory.clear()
		_pending_component.clear()
		_result.text = "Host accepted action. Inventory follows the latest host view." if result.is_success else EngineeringFailureGuidance.describe(result, "Host rejected action: " + result.message)
		if not exact_targets.is_empty(): _result.text += "\nReceipt targets\n" + exact_targets + "\nObserved state below follows host observations; receipt does not predict capabilities."
		if was_world: _world_status.text = _result.text
		_update_buttons()
		if get_parent() is ScrollContainer: _reveal_feedback.call_deferred(_pending)


func _update_buttons() -> void:
	_update_active_equipment()
	_work_targets.text = _work_target_text()
	_transfer_preview.text = PlayerInventoryPresentation.transfer_preview(_record, _selected_id(_items), _picker_id(_destination), _picker_id(_slot), {}, "", _equipment_record) if not _record.is_empty() else ""
	_world_transfer_preview.text = ""
	if not _record.is_empty():
		_world_transfer_preview.text = PlayerInventoryPresentation.drop_preview(_record, _selected_id(_items), _nearby, _picker_id(_world_root), _equipment_record)
		if not _picker_id(_world_root).is_empty():
			_world_transfer_preview.text += "\n" + PlayerInventoryPresentation.transfer_preview(_record, _selected_id(_world_items), _picker_id(_destination), "", _nearby, _picker_id(_world_root), _equipment_record)
	if _shown_pending != _pending:
		_shown_pending = _pending
		if not _pending.is_empty() and get_parent() is ScrollContainer:
			_reveal_feedback.call_deferred(_pending)
	for button in _buttons:
		button.disabled = _record.is_empty() or not _pending.is_empty()
	_update_closure()
	for operation in _component_buttons:
		var component_button: Button = _component_buttons[operation]
		var reason: String = _component_prerequisite(operation)
		component_button.disabled = component_button.disabled or not reason.is_empty()
		component_button.tooltip_text = reason if not reason.is_empty() else "Host rechecks current prerequisites at the tick."
	_update_component_selections()
	_maintenance_targets.text = ToolMaintenanceView.targets(_tools, _production, _inspected_tool, _picker_id(_tool_parts), _picker_id(_tool_mounts), _picker_id(_loose_parts))
	_component_details.text = EquipmentPrerequisiteView.part_text(_tools, _production, _picker_id(_part_blueprints), _selected_id(_items), _picker_id(_tool_mounts), _picker_id(_loose_parts), not _pending.is_empty())
	if not _pending_component.is_empty(): _component_details.text += "\nPending exact targets\n" + _pending_component_text()
	for operation in _inventory_buttons:
		var button: Button = _inventory_buttons[operation]
		var reason: String = _inventory_prerequisite(operation)
		button.disabled = button.disabled or not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else "Host rechecks current ownership, reach, capacity, compatibility and revision."
	for picker in [_source, _destination, _slot, _world_root, _part_blueprints, _loose_parts, _tool_mounts, _tool_parts]:
		picker.disabled = _record.is_empty() or not _pending.is_empty()
	_items.mouse_filter = Control.MOUSE_FILTER_IGNORE if not _pending.is_empty() else Control.MOUSE_FILTER_STOP
	_world_items.mouse_filter = _items.mouse_filter
	_items.focus_mode = Control.FOCUS_ALL if _pending.is_empty() else Control.FOCUS_NONE
	_world_items.focus_mode = _items.focus_mode
	_items.set_process_input(_pending.is_empty())
	_world_items.set_process_input(_pending.is_empty())
	_storage_status.text = PlayerInventoryPresentation.storage_hint(_record, _picker_id(_destination)) if not _record.is_empty() else ""

func _pending_component_text() -> String:
	var lines := PackedStringArray(["Action: " + str(_pending_component.get("operation", ""))])
	for field: String in ["blueprint_id", "item_id", "slot_id", "part_id", "amount_ppm", "amount_milligrams", "deposit_id", "carrier_id", "cycles", "observed_reserved_request_id", "observed_reserved_tool_id", "observed_reserved_deposit_id", "observed_reserved_carrier_id", "expected_revision", "expected_tool_revision"]:
		if not _pending_component.has(field): continue
		var title: String = {"blueprint_id": "Blueprint ID", "item_id": "Tool ID", "slot_id": "Mount ID", "part_id": "Part ID", "amount_ppm": "Requested repair ppm", "amount_milligrams": "Requested mass mg", "deposit_id": "Source ID", "carrier_id": "Receiving canister ID", "cycles": "Requested cycles", "observed_reserved_request_id": "Observed reservation request ID at submit", "observed_reserved_tool_id": "Observed reserved tool ID at submit", "observed_reserved_deposit_id": "Observed reserved source ID at submit", "observed_reserved_carrier_id": "Observed reserved canister ID at submit", "expected_revision": "Production revision", "expected_tool_revision": "Tool revision"}[field]
		lines.append(title + ": " + str(_pending_component[field]))
	return "\n".join(lines)


func _scroll_input(event: InputEvent) -> void:
	var scroll := get_parent() as ScrollContainer
	if scroll == null or not scroll.has_focus(): return
	var direction: int = 1 if event.is_action_pressed("ui_down") else (-1 if event.is_action_pressed("ui_up") else 0)
	if direction != 0:
		scroll.scroll_vertical += direction * 80
		scroll.accept_event()


## Large wrapped guidance remains readable without leaving its keyboard focus.
func _guidance_input(event: InputEvent, guidance: Label) -> void:
	var scroll := get_parent() as ScrollContainer
	if scroll == null or not guidance.has_focus(): return
	var amount: int = 0
	if event.is_action_pressed("ui_down"): amount = 80
	elif event.is_action_pressed("ui_up"): amount = -80
	elif event.is_action_pressed("ui_page_down"): amount = int(scroll.size.y)
	elif event.is_action_pressed("ui_page_up"): amount = -int(scroll.size.y)
	if amount != 0:
		scroll.scroll_vertical += amount
		guidance.accept_event()


func _reveal_feedback(request_id: String) -> void:
	# Wrapped text changes height after container sorting; reveal its final bounds.
	await get_tree().process_frame
	await get_tree().process_frame
	if _pending == request_id and get_parent() is ScrollContainer:
		(get_parent() as ScrollContainer).ensure_control_visible(_result)


func _component_picker(picker: OptionButton, title: String) -> void:
	_label(title)
	add_child(picker)
	var selection := Label.new()
	selection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(selection)
	_component_selections[picker] = selection


func _update_component_selections() -> void:
	for picker: OptionButton in _component_selections:
		var selection: Label = _component_selections[picker]
		var id: String = _picker_id(picker)
		selection.text = "No selection; choose explicitly above."
		if not id.is_empty():
			selection.text = "%s\nID: %s%s" % [picker.get_item_text(picker.selected), id, " · unavailable in latest host view" if picker.is_item_disabled(picker.selected) else ""]
		picker.tooltip_text = selection.text


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)


func _update_closure() -> void:
	_fill_closure_target()
	_closure_status.text = PlayerInventoryPresentation.closure_status(_equipment_record, _closure_selected_id)
	_closure_target.disabled = _equipment_record.is_empty() or not _pending.is_empty()
	for operation in _closure_buttons:
		var button: Button = _closure_buttons[operation]
		var reason: String = PlayerInventoryPresentation.closure_prerequisite(_equipment_record, _closure_selected_id)
		button.disabled = not _pending.is_empty() or not reason.is_empty()
		button.tooltip_text = reason if not reason.is_empty() else "Host checks physical ownership, open ancestors, hands and revision; no lock or other-body access is implied."


func _button(parent: Node, text: String, callback: Callable, inventory_operation: String = "") -> void:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons.append(button)
	if inventory_operation in ["fabricate_tool_part", "fit_tool_part", "detach_tool_part", "recycle_tool_part"]:
		_component_buttons[inventory_operation] = button
	elif not inventory_operation.is_empty(): _inventory_buttons[inventory_operation] = button


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


func _work_target_text() -> String:
	if _record.is_empty() or _production.is_empty(): return "Work-cycle targets unavailable: current observations missing."
	var source: String = _picker_id(_deposit)
	var carrier: String = _picker_id(_carrier)
	var lines := PackedStringArray([
		"Intended source ID: " + source + ("; observed." if _production.get("deposits", {}).has(source) else "; unavailable."),
		"Intended receiving canister ID: " + carrier + ("; observed." if _production.get("cargo", {}).has(carrier) else "; unavailable."),
		"Intended sustained cycles: %d of 1000000 mg; selection completes no work." % int(_work_cycles.value),
		"Start uses active equipment above, independently of inspected maintenance item. Host rechecks tool, source, canister and reach."
	])
	lines.append(_canister_observation_text(carrier))
	var work: Dictionary = _production.get("tool_extraction", {})
	if not work.is_empty():
		for field: String in ["tool_id", "deposit_id", "carrier_id"]:
			lines.append("Observed reserved " + field + ": " + str(work.get(field, "unavailable")))
		lines.append("Resume/cancel target this host-observed reservation, not the current selections.")
	return "\n".join(lines)


func _canister_observation_text(carrier: String) -> String:
	var lines := PackedStringArray()
	if carrier.is_empty() or not _production.get("cargo", {}).has(carrier):
		return "Receiving contents and loaded mass unavailable; choose a currently observed canister. Payload capacity unavailable in this observation."
	lines.append("Observed receiving contents: " + WorkstationResourceView.stock_text(_production["cargo"][carrier]))
	var mass: String = "unavailable"
	for detail in _record.get("item_details", []):
		if detail.get("item", {}).get("item_id", "") == carrier and detail.has("mass_milligrams"):
			mass = "%d mg (shell and payload included)" % int(detail["mass_milligrams"])
	lines.append("Observed receiving loaded mass: " + mass + ".")
	lines.append("Payload capacity unavailable in this observation. No fit or acceptance quote; host rechecks capacity, compatibility and reach.")
	return "\n".join(lines)
