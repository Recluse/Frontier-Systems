extends VBoxContainer
class_name LocalInventoryPanel

## Development UI over scoped observations and queued commands, never snapshots.
const ACTOR: String = "local-inventory-actor"
const TARGET: String = "local-inventory-target"
var _world: WorldRuntime
var _configured: bool = false
var _status: Label
var _own_items: ItemList
var _search_items: ItemList
var _take_button: Button
var _insert_button: Button
var _equip_button: Button
var _view_id: String = ""
var _search_container: String = ""
var _job_id: String = ""
var _last_outcome: String = ""
var _pending_search_id: String = ""
var _last_submitted_job: String = ""
var _handled_outcome_id: String = ""
var _awaiting_start: bool = false
var _elapsed: float = 0.0
var _nonce: String = str(Time.get_ticks_usec())
var _own_records: Array = []
var _search_records: Array = []
var _all_buttons: Array[Button] = []
var _slot_picker: OptionButton
var _storage_picker: OptionButton
var _equipment_label: Label
var _switch_button: Button
var _self_buttons: Array[Button] = []
var _pending_self: String = ""
var _own_equipment: Array = []
var _hands: Array = []
var _world_items: ItemList
var _world_picker: OptionButton
var _world_records: Array = []
var _world_buttons: Array[Button] = []
var _pending_world: String = ""
var _body_root: String = ""
var _grip_panel: LocalGripPanel


func configure(world: WorldRuntime) -> ServiceResult:
	if _configured or not is_instance_valid(world) or world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) == null:
		return ServiceResult.failure(&"inventory_panel_configuration", "Configure this client panel with one world.")
	_world = world
	_configured = true
	_world.command_completed.connect(_on_command_completed)
	_world.tree_exiting.connect(_on_world_closed)
	var explanation := Label.new()
	explanation.text = "Local inventory demo: two logical fixture bodies. These are independent of the walking character."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(explanation)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_grip_panel = LocalGripPanel.new()
	var grip_setup: ServiceResult = _grip_panel.configure(world)
	if not grip_setup.is_success:
		return grip_setup
	add_child(_grip_panel)
	var actions := GridContainer.new()
	actions.columns = 2
	add_child(actions)
	_button(actions, "Search target backpack", _start_search.bind("storage.backpack-1"))
	_button(actions, "Search target pouch", _start_search.bind("storage.pouch-1"))
	_button(actions, "Target resists", _submit.bind(TARGET, "resist", {}))
	_button(actions, "Target steps away", _submit.bind(TARGET, "move", {"x_millimetres": 3000}))
	_button(actions, "Target returns", _submit.bind(TARGET, "move", {"x_millimetres": 1000}))
	_button(actions, "Close live search", _close_search)
	_button(actions, "Cancel my job", _job_operation.bind("cancel"))
	_button(actions, "Resume my job", _job_operation.bind("resume"))
	var own_label := Label.new()
	own_label.text = "Actor's owned items (including nested storage)"
	add_child(own_label)
	_own_items = ItemList.new()
	_own_items.custom_minimum_size.y = 80
	add_child(_own_items)
	_equipment_label = Label.new()
	_equipment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_equipment_label)
	_slot_picker = OptionButton.new()
	_slot_picker.tooltip_text = "Select a body equipment slot. Item compatibility is checked by the simulation."
	add_child(_slot_picker)
	_storage_picker = OptionButton.new()
	_storage_picker.tooltip_text = "Select an owned destination container."
	add_child(_storage_picker)
	var self_actions := GridContainer.new()
	self_actions.columns = 2
	add_child(self_actions)
	_switch_button = _button(self_actions, "Switch active hand", _self_action.bind("switch_hand"))
	_self_buttons.append(_switch_button)
	_self_buttons.append(_button(self_actions, "Select chosen hand", _self_action.bind("select_hand")))
	_self_buttons.append(_button(self_actions, "Equip selected owned item", _self_action.bind("equip")))
	_self_buttons.append(_button(self_actions, "Unequip chosen slot to storage", _self_action.bind("unequip")))
	_self_buttons.append(_button(self_actions, "Move unequipped item to storage", _self_action.bind("move")))
	var world_label := Label.new()
	world_label.text = "Reachable world storage (logical tray)"
	add_child(world_label)
	_world_picker = OptionButton.new()
	add_child(_world_picker)
	_world_items = ItemList.new()
	_world_items.custom_minimum_size.y = 80
	add_child(_world_items)
	var world_actions := VBoxContainer.new()
	add_child(world_actions)
	_world_buttons.append(_button(world_actions, "Drop selected owned item into tray", _world_action.bind("drop", false)))
	_world_buttons.append(_button(world_actions, "Pick up selected world item", _world_action.bind("pickup", false)))
	_world_buttons.append(_button(world_actions, "Pick up into chosen equipment slot", _world_action.bind("pickup", true)))
	var search_label := Label.new()
	search_label.text = "Searched container (direct contents only)"
	add_child(search_label)
	_search_items = ItemList.new()
	_search_items.custom_minimum_size.y = 80
	add_child(_search_items)
	var transfers := VBoxContainer.new()
	add_child(transfers)
	_take_button = _button(transfers, "Take selected searched item", _take_selected)
	_insert_button = _button(transfers, "Put selected owned item in target pouch", _give_selected.bind(false))
	_equip_button = _button(transfers, "Put selected owned item in target's left hand", _give_selected.bind(true))
	refresh()
	return ServiceResult.success()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if not is_instance_valid(_world) or _status == null:
		return
	var inventory: InventorySimulationSystem = _inventory()
	var context: AuthenticatedCommandContext = _context(ACTOR)
	var observed: ServiceResult = inventory.local_observation(context)
	var own: ServiceResult = inventory.own_inventory_observation(context)
	if not observed.is_success or not own.is_success:
		_status.text = "Fixture inventory unavailable in this world."
		_clear_search()
		_clear_own()
		_update_buttons()
		return
	_own_records = own.value["items"]
	_own_equipment = own.value["equipped"]
	_hands = own.value["hand_slot_ids"]
	_body_root = own.value["body_container_id"]
	var nearby: ServiceResult = inventory.world_inventory_observation(context)
	_world_records = []
	var world_ids: Array = []
	if nearby.is_success:
		for container in nearby.value["containers"]:
			world_ids.append(container["container_id"])
			_world_records.append_array(container["items"])
	_fill_picker(_world_picker, world_ids)
	_fill_list(_world_items, _world_records)
	_fill_picker(_slot_picker, own.value["slot_ids"])
	_fill_picker(_storage_picker, own.value["container_ids"])
	var fitted: PackedStringArray = []
	for binding in _own_equipment:
		fitted.append("%s: %s" % [binding["slot_id"], binding["item_id"]])
	_equipment_label.text = "Equipped: %s" % (", ".join(fitted) if not fitted.is_empty() else "none")
	_fill_list(_own_items, _own_records)
	var jobs: Array = observed.value["jobs"]
	_job_id = "" if jobs.is_empty() else jobs[0]["job_id"]
	var progress: String = "Idle" if jobs.is_empty() else "%s: %s (%d/%d ticks)" % [jobs[0]["action"], jobs[0]["state"], jobs[0]["progress_ticks"], jobs[0]["duration_ticks"]]
	for outcome in observed.value["outcomes"]:
		# Only the most recently requested search may install a new view.
		if outcome["job_id"] == _pending_search_id and outcome["success"] and outcome["view_id"] != "":
			_view_id = outcome["view_id"]
			_pending_search_id = ""
		if outcome["job_id"] == _last_submitted_job and outcome["job_id"] != _handled_outcome_id:
			_last_outcome = "Completed" if outcome["success"] else "Interrupted: %s" % outcome["error_code"]
			_handled_outcome_id = outcome["job_id"]
	if not _view_id.is_empty():
		var searched: ServiceResult = inventory.read_search(context, _view_id)
		if searched.is_success:
			_search_container = searched.value["container_id"]
			_search_records = searched.value["items"]
			_fill_list(_search_items, _search_records)
		else:
			_clear_search()
	_status.text = "%s | Carried: %.2f kg | Active hand: %s\n%s\nSearch: %s" % [progress, float(own.value["mass_milligrams"]) / 1000000.0, own.value["active_hand_slot_id"], _last_outcome, _search_container if not _view_id.is_empty() else "none"]
	_update_buttons()


func _start_search(container_id: String) -> void:
	if not is_instance_valid(_world):
		return
	var observed: ServiceResult = _inventory().local_observation(_context(ACTOR))
	if _awaiting_start or not observed.is_success or not observed.value["jobs"].is_empty():
		return
	_close_search()
	_pending_search_id = _start("search", container_id, "", "", "")


func _take_selected() -> void:
	if _view_id.is_empty():
		return
	# Revalidate at the click, before creating a transfer intent from visible data.
	var live: ServiceResult = _inventory().read_search(_context(ACTOR), _view_id)
	var index: int = _selection(_search_items)
	if not live.is_success or index < 0 or index >= _search_records.size():
		_clear_search()
		return
	var selected_id: String = _search_records[index]["item_id"]
	for item in live.value["items"]:
		if item["item_id"] == selected_id:
			_start("take", live.value["container_id"], selected_id, "", "body.human-2")
			return
	_clear_search()


func _give_selected(equip: bool) -> void:
	if not is_instance_valid(_world):
		return
	var index: int = _selection(_own_items)
	if index < 0 or index >= _own_records.size():
		return
	_start("equip" if equip else "insert", "body.human-1" if equip else "storage.pouch-1", _own_records[index]["item_id"], "hand.left" if equip else "", "")


func _self_action(operation: String) -> void:
	if not is_instance_valid(_world) or not _pending_self.is_empty() or not _pending_world.is_empty():
		return
	var observed: ServiceResult = _inventory().local_observation(_context(ACTOR))
	if not observed.is_success:
		return
	var payload := {"operation": operation, "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": observed.value["inventory_revision"]}
	if operation in ["select_hand", "equip", "unequip"]:
		if _slot_picker.selected < 0:
			return
		payload["slot_id"] = _slot_picker.get_item_metadata(_slot_picker.selected)
	if operation in ["move", "unequip"]:
		if _storage_picker.selected < 0:
			return
		payload["destination_container_id"] = _storage_picker.get_item_metadata(_storage_picker.selected)
	if operation in ["equip", "move"]:
		var index: int = _selection(_own_items)
		if index < 0 or index >= _own_records.size():
			return
		payload["item_id"] = _own_records[index]["item_id"]
		payload["source_container_id"] = _own_records[index]["container_id"]
	_pending_self = _submit(ACTOR, "self", payload)


func _world_action(operation: String, fit_slot: bool) -> void:
	if not is_instance_valid(_world) or not _pending_world.is_empty() or not _pending_self.is_empty():
		return
	var observed: ServiceResult = _inventory().local_observation(_context(ACTOR))
	if not observed.is_success or _world_picker.selected < 0:
		return
	var payload := {"operation": operation, "item_id": "", "world_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": observed.value["inventory_revision"]}
	if operation == "drop":
		var index: int = _selection(_own_items)
		if index < 0 or index >= _own_records.size():
			return
		payload["item_id"] = _own_records[index]["item_id"]
		payload["world_container_id"] = _world_picker.get_item_metadata(_world_picker.selected)
	else:
		var index: int = _selection(_world_items)
		if index < 0 or index >= _world_records.size():
			return
		payload["item_id"] = _world_records[index]["item_id"]
		payload["world_container_id"] = _world_records[index]["container_id"]
		payload["destination_container_id"] = _body_root if fit_slot else _storage_picker.get_item_metadata(_storage_picker.selected)
		if fit_slot:
			payload["slot_id"] = _slot_picker.get_item_metadata(_slot_picker.selected)
	_pending_world = _submit(ACTOR, "world", payload)


func select_world_item(container_id: String, item_id: String) -> void:
	refresh()
	for index in range(_world_records.size()):
		if _world_records[index]["container_id"] == container_id and _world_records[index]["item_id"] == item_id:
			_world_items.select(index)
			return


func collect_world_item(container_id: String, item_id: String) -> void:
	select_world_item(container_id, item_id)
	var index: int = _selection(_world_items)
	if index >= 0 and _world_records[index]["container_id"] == container_id and _world_records[index]["item_id"] == item_id:
		_world_action("pickup", false)


func _start(action: String, container: String, item: String, slot: String, destination: String) -> String:
	var observed: ServiceResult = _inventory().local_observation(_context(ACTOR))
	if not observed.is_success or _awaiting_start or not observed.value["jobs"].is_empty():
		return ""
	var id: String = _submit(ACTOR, "start", {"action": action, "target_body_id": "body.human-1", "target_container_id": container,
		"item_id": item, "slot_id": slot, "destination_container_id": destination, "expected_revision": observed.value["inventory_revision"]})
	_last_submitted_job = id
	_awaiting_start = not id.is_empty()
	return id


func _job_operation(operation: String) -> void:
	if not _job_id.is_empty():
		_submit(ACTOR, operation, {"job_id": _job_id})


func _close_search() -> void:
	if not _view_id.is_empty():
		_submit(ACTOR, "close_search", {"view_id": _view_id})
	_pending_search_id = ""
	_clear_search()


func _clear_search() -> void:
	_view_id = ""
	_search_container = ""
	_search_records = []
	if _search_items != null:
		_search_items.clear()
	if _take_button != null:
		_take_button.disabled = true


func _submit(principal: String, operation: String, payload: Dictionary) -> String:
	if not is_instance_valid(_world):
		return ""
	var id: String = "inventory-ui-%s-%s" % [_nonce, _world.next_local_request_id()]
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName(id)
	command.operation = operation
	command.payload = payload.duplicate(true)
	command.authenticated_context = _context(principal)
	var result: ServiceResult = _world.enqueue_command(command)
	_last_outcome = "Queued %s" % operation if result.is_success else result.message
	return id if result.is_success else ""


func _on_command_completed(command: SimulationCommand, result: ServiceResult) -> void:
	if command is InventoryDevelopmentCommand and String(command.command_id).begins_with("inventory-ui-%s-" % _nonce):
		if String(command.command_id) == _pending_self:
			_pending_self = ""
		if String(command.command_id) == _pending_world:
			_pending_world = ""
		if String(command.command_id) == _last_submitted_job:
			_awaiting_start = false
		_last_outcome = "Started %s" % command.operation if result.is_success else "Rejected: %s" % result.error_code


func _on_world_closed() -> void:
	_world = null
	_clear_search()
	_clear_own()
	_status.text = "World closed"
	for button in _all_buttons:
		button.disabled = true


func _clear_own() -> void:
	_own_records = []
	_own_equipment = []
	_hands = []
	_own_items.clear()
	_slot_picker.clear()
	_storage_picker.clear()
	_equipment_label.text = "Equipped: none"
	_body_root = ""
	_world_records = []
	_world_items.clear()
	_world_picker.clear()


func _inventory() -> InventorySimulationSystem:
	return _world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem


func _context(principal: String) -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.for_local_development(StringName(principal), _world.world_id, _world.region_id)


func _button(parent: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	_all_buttons.append(button)
	return button


func _fill_list(list: ItemList, records: Array) -> void:
	var unchanged: bool = list.item_count == records.size()
	for record_index in range(records.size()):
		if not unchanged or list.get_item_metadata(record_index) != records[record_index]["item_id"] or list.get_item_text(record_index) != "%s (%s)" % [records[record_index]["item_id"], records[record_index]["definition_id"]]:
			unchanged = false
			break
	if unchanged:
		return
	var selected_id: String = ""
	var index: int = _selection(list)
	if index >= 0:
		selected_id = String(list.get_item_metadata(index))
	list.clear()
	for record in records:
		list.add_item("%s (%s)" % [record["item_id"], record["definition_id"]])
		list.set_item_metadata(list.item_count - 1, record["item_id"])
		if record["item_id"] == selected_id:
			list.select(list.item_count - 1)
	if list.item_count > 0 and list.get_selected_items().is_empty():
		list.select(0)


func _selection(list: ItemList) -> int:
	var selected: PackedInt32Array = list.get_selected_items()
	return -1 if selected.is_empty() else selected[0]


func _fill_picker(picker: OptionButton, ids: Array) -> void:
	var selected_id: String = String(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""
	var unchanged: bool = picker.item_count == ids.size()
	for index in range(ids.size()):
		if not unchanged or picker.get_item_metadata(index) != ids[index]:
			unchanged = false
			break
	if unchanged:
		return
	picker.clear()
	for id in ids:
		picker.add_item(id)
		picker.set_item_metadata(picker.item_count - 1, id)
		if id == selected_id:
			picker.select(picker.item_count - 1)


func _update_buttons() -> void:
	_take_button.disabled = _search_records.is_empty() or _view_id.is_empty() or not _job_id.is_empty() or _awaiting_start
	_insert_button.disabled = _own_records.is_empty() or not _job_id.is_empty() or _awaiting_start
	_equip_button.disabled = _insert_button.disabled
	for button in _self_buttons:
		button.disabled = _slot_picker.item_count == 0 or not _job_id.is_empty() or _awaiting_start or not _pending_self.is_empty()
	_switch_button.disabled = _hands.is_empty() or not _job_id.is_empty() or _awaiting_start or not _pending_self.is_empty()
	var busy: bool = not _job_id.is_empty() or _awaiting_start or not _pending_self.is_empty() or not _pending_world.is_empty()
	_world_buttons[0].disabled = busy or _own_records.is_empty() or _world_picker.item_count == 0
	_world_buttons[1].disabled = busy or _world_records.is_empty() or _storage_picker.item_count == 0
	_world_buttons[2].disabled = busy or _world_records.is_empty() or _slot_picker.item_count == 0
