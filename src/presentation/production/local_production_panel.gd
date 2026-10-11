extends VBoxContainer
class_name LocalProductionPanel

signal observation_changed(record: Dictionary)

const RECIPE_LABELS: Dictionary = {
	"refine.iron": "Refine iron ore",
	"craft.plate": "Print a plate",
	"salvage.plate": "Recycle shared plate stock",
	"refine.ice": "Melt ice",
	"refine.regolith": "Separate regolith",
	"chemical.electrolysis": "Electrolyze water",
	"chemical.nutrients": "Mix nutrient solution"
}

## Shared fixture workstation UI. Observations in, fixed-tick intents out.
var _world: WorldRuntime
var _configured: bool = false
var _resource_view := WorkstationResourceView.new()
var _status: Label
var _feedback: Label
var _deposit: OptionButton
var _blueprint: OptionButton
var _equipment: OptionButton
var _fabrication_details: Label
var _fabricate_button: Button
var _salvage_button: Button
var _recipe: OptionButton
var _recipe_details: Label
var _chemical: OptionButton
var _station: OptionButton
var _amount: SpinBox
var _carrier: OptionButton
var _cargo_material: OptionButton
var _extract_button: Button
var _guide := LocalProductionGuide.new()
var _guide_label: Label
var _components: OptionButton
var _guide_button: Button
var _buttons: Array[Button] = []
var _record: Dictionary = {}
var _elapsed: float = 0.0
var _pending: String = ""
var _tool_record: Dictionary = {}
var _maintenance_parts: OptionButton
var _maintenance_details: Label
var _maintenance_feedback: Label
var _maintenance_button: Button
var _selected_part_id: String = ""
var _maintenance_choice_key: String = ""
var _nonce: String = str(Time.get_ticks_usec())
var _navigation: OptionButton
var _section_scroll: ScrollContainer
var _sections: Array[VBoxContainer] = []
var _activity: Label
var _gather_details: Label


func configure(world: WorldRuntime) -> ServiceResult:
	if _configured or not is_instance_valid(world):
		return ServiceResult.failure(&"production_panel_configuration", "Configure one world per production panel.")
	_configured = true
	_world = world
	_world.command_completed.connect(_on_completed)
	_world.tree_exiting.connect(_on_closed)
	if _world is RemoteWorldRuntime:
		_world.observation_received.connect(_observe_tools)
		_world.connection_closed.connect(func(_message: String) -> void: _on_closed())
	var maintenance_title := _label()
	maintenance_title.text = "Tool diagnosis and maintenance"
	_maintenance_parts = _picker()
	_maintenance_parts.clip_text = true
	_maintenance_parts.fit_to_longest_item = false
	_maintenance_parts.item_selected.connect(_select_maintenance_part)
	_maintenance_details = _label()
	_maintenance_button = _button("Maintain selected component", _maintain_component)
	_maintenance_feedback = _label()
	_maintenance_feedback.text = "Preview: select a component to inspect."
	var title := _label()
	title.text = "Extract, store, refine and recycle"
	var instructions := _label()
	instructions.text = "Approach a resource source or workstation. Hold your configured UI cursor key to use panels. Select a source; double-click to extract into your canister."
	_guide_label = _label()
	_guide_button = _button("Next collection step", _guide_action)
	_status = _label()
	_activity = _label()
	_gather_details = _label()
	_deposit = _picker()
	for id in ["deposit.iron", "deposit.ice", "deposit.regolith"]:
		_deposit.add_item(id)
	_deposit.item_selected.connect(func(_index: int) -> void: refresh())
	_extract_button = _button("Extract selected mass into canister (up to 1 kg)", _extract_action)
	_recipe = _picker()
	_recipe.item_selected.connect(func(_index: int) -> void: refresh())
	_recipe_details = _label()
	var production := _world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	production.batch_completed.connect(_on_batch_completed)
	var observed: ServiceResult = production.observation(_context())
	if observed.is_success:
		var recipes: Array = observed.value["recipes"].duplicate()
		var priority_recipes: Array[String] = ["refine.iron", "craft.plate", "salvage.plate", "refine.ice", "refine.regolith"]
		for id in priority_recipes:
			if recipes.has(id):
				_add_recipe(id)
				recipes.erase(id)
		for id in recipes:
			_add_recipe(id)
	_button("Run selected recipe", _selected_action.bind("process", "recipe_id", _recipe))
	var cancel_button := _button("Cancel batch (recover feedstock; energy spent)", _send.bind("cancel", {}))
	_chemical = _picker()
	if observed.is_success:
		for id in observed.value["dispensable"]:
			_chemical.add_item(id)
	_amount = SpinBox.new()
	_amount.min_value = 0.001
	_amount.max_value = 2000.0
	_amount.step = 0.001
	_amount.value = 1000.0
	_amount.suffix = "g"
	_amount.tooltip_text = "Transfer mass. Extraction accepts up to 1000 g; use smaller gas batches to avoid overpressure."
	add_child(_amount)
	_button("Dispense selected mass into vessel", _chemical_action.bind("dispense"))
	var return_button := _button("Return selected mass to storage", _chemical_action.bind("return"))
	var cargo_title := _label()
	cargo_title.text = "Portable canisters (own inventory only; 2 kg payload limit)"
	_carrier = _picker()
	_cargo_material = _picker()
	if observed.is_success:
		for id in observed.value["store"]:
			_cargo_material.add_item(id)
	_button("Load selected mass into carried canister", _cargo_action.bind("load_cargo"))
	var unload_button := _button("Unload selected mass to workstation", _cargo_action.bind("unload_cargo"))
	var collect_button := _button("Collect printed plate into inventory", _send.bind("materialize_plate", {}))
	_components = _picker()
	var recycle_button := _button("Recycle selected carried plate", _selected_action.bind("recycle_component", "item_id", _components))
	var fabrication_title := _label()
	fabrication_title.text = "Equipment fabrication · recoverable construction materials"
	_blueprint = _picker()
	_blueprint.item_selected.connect(func(_index: int) -> void: refresh())
	_fabrication_details = _label()
	_fabricate_button = _button("Fabricate selected equipment into inventory", _fabricate_equipment)
	_equipment = _picker()
	_equipment.item_selected.connect(func(_index: int) -> void: refresh())
	_salvage_button = _button("Salvage selected fabricated equipment and contents", _salvage_equipment)
	var build_button := _button("Build 1 kg wall segment", _send.bind("build", {}))
	_button("Deconstruct one wall segment", _send.bind("deconstruct", {}))
	_station = _picker()
	for id in ProductionSimulationSystem.STATIONS:
		_station.add_item(id)
	var power_button := _button("Toggle selected station power", _toggle_power)
	_feedback = _label()
	var original: Array[Node] = get_children()
	# Keep progress, mass and host receipts above the task chooser.
	for control in [title, instructions, _guide_label, _guide_button, _activity, _feedback, _amount]:
		move_child(control, get_child_count() - 1)
	var mass_label := _label()
	mass_label.text = "Transfer / extraction mass (g)"
	move_child(mass_label, _amount.get_index())
	_navigation = _picker()
	_navigation.item_selected.connect(_show_section)
	var hint := _label()
	hint.text = "Choose a workstation task. Scroll for full prerequisites; Tab follows controls into view. Results above apply to every task."
	_section_scroll = ScrollContainer.new()
	_section_scroll.custom_minimum_size.y = 400
	_section_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_section_scroll.follow_focus = true
	add_child(_section_scroll)
	var section_root := VBoxContainer.new()
	section_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_scroll.add_child(section_root)
	_add_section("Gather / carry", [[_gather_details, _extract_button], [cargo_title, unload_button]], original, section_root)
	_add_section("Refine / collect / recycle", [[_recipe, cancel_button], [collect_button, recycle_button]], original, section_root)
	_add_section("Equipment fabrication / salvage", [[fabrication_title, _salvage_button]], original, section_root)
	_add_section("Tool maintenance", [[maintenance_title, _maintenance_feedback]], original, section_root)
	_add_section("Fluids / chemicals", [[_chemical, return_button]], original, section_root)
	_add_section("Observed resources / jobs", [[_status, _status]], original, section_root)
	_add_section("Other workstation controls", [[build_button, power_button]], original, section_root)
	_show_section(0)
	refresh()
	return ServiceResult.success()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if _status == null or not is_instance_valid(_world):
		return
	var observed: ServiceResult = _world.production_observation(_context())
	_guide_label.text = _guide.text()
	var valid_observation: bool = observed.is_success and typeof(observed.value) == TYPE_DICTIONARY and WorkstationResourceView.valid(observed.value)
	_record = observed.value if valid_observation else {}
	_refresh_equipment()
	_fill_recipes(_record.get("recipes", []))
	if not _world is RemoteWorldRuntime:
		var tools := _world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem
		var tool_view: ServiceResult = tools.observation(_context()) if tools != null else ServiceResult.failure(&"tools_unavailable", "Tools unavailable")
		_tool_record = tool_view.value if tool_view.is_success else {}
	observation_changed.emit(_record.duplicate(true))
	_fill_carriers(_record.get("cargo", {}).keys())
	_fill_components(_record.get("components", []))
	for button in _buttons:
		button.disabled = not _pending.is_empty() or _record.is_empty() or not _record.get("can_operate", false)
	_fabricate_button.disabled = _fabricate_button.disabled or not _record.get("blueprints", {}).has(EquipmentPrerequisiteView.selected(_blueprint))
	_salvage_button.disabled = _salvage_button.disabled or not _record.get("structures", {}).has(EquipmentPrerequisiteView.selected(_equipment))
	_extract_button.disabled = not _pending.is_empty() or _record.is_empty() or _carrier.selected < 0 or _deposit.selected < 0 or not _record.get("extractable_sources", []).has(_deposit.get_item_text(_deposit.selected))
	var suggested: Dictionary = _guide.suggested_action()
	_guide_button.text = suggested["label"]
	_guide_button.disabled = not _pending.is_empty() or suggested["operation"] == "" or _record.is_empty() or (not _record.get("can_operate", false) if suggested["operation"] != "extract" else not _record.get("extractable_sources", []).has("deposit.iron"))
	_refresh_maintenance()
	var recipe_id: String = str(_recipe.get_item_metadata(_recipe.selected)) if _recipe.selected >= 0 else ""
	_status.text = _resource_view.describe(_record, recipe_id, not _pending.is_empty(), false)
	_recipe_details.text = WorkstationResourceView.recipe_text(_record, recipe_id) if valid_observation else "Recipe prerequisites unavailable: wait for a valid current observation."
	_activity.text = "Observed resources and job status unavailable; wait for a fresh observation."
	_gather_details.text = "Source and carried payload unavailable; wait for a fresh observation."
	if valid_observation:
		var job: Dictionary = _record["job"]
		_activity.text = "No active job observed; this does not confirm past completion."
		if not job.is_empty():
			_activity.text = "Observed job at %s: %.1f s remaining. Acceptance is not completion; see Observed resources / jobs for power and pause details." % [job["station"], float(job["remaining_ticks"]) / float(_record["timebase_hz"])]
		if not _pending.is_empty():
			_activity.text += "\nCommand pending: awaiting host receipt; no output confirmed."
		var source: String = _deposit.get_item_text(_deposit.selected) if _deposit.selected >= 0 else ""
		var carrier: String = _carrier.get_item_text(_carrier.selected) if _carrier.selected >= 0 else ""
		var mass: String = "%d mg remaining" % int(_record["deposits"][source]) if _record["deposits"].has(source) else "unavailable"
		var payload: String = WorkstationResourceView.stock_text(_record["cargo"][carrier]) if _record["cargo"].has(carrier) else "unavailable"
		_gather_details.text = "Source %s: %s; extraction reach: %s.\n%s payload: %s. Unload for shared-stock recipes. Host checks capacity and revision." % [source, mass, "yes" if _record["extractable_sources"].has(source) else "no", carrier, payload]


func _send(operation: String, payload: Dictionary) -> void:
	if not _pending.is_empty() or not is_instance_valid(_world):
		return
	refresh()
	if _record.is_empty() or (operation != "extract" and not _record["can_operate"]):
		return
	if operation == "extract" and not _record["extractable_sources"].has(payload.get("deposit_id")):
		_feedback.text = "Move within reach of the selected resource source."
		return
	var command := ProductionDevelopmentCommand.new()
	command.command_id = StringName("production-%s-%s" % [_nonce, _world.next_local_request_id()])
	command.authenticated_context = _context()
	command.operation = operation
	command.payload = payload.duplicate(true)
	command.payload["expected_revision"] = _record["state_revision"]
	var queued: ServiceResult = _world.enqueue_command(command)
	_pending = String(command.command_id) if queued.is_success else ""
	_feedback.text = "Queued " + operation if queued.is_success else queued.message
	_reveal_receipt.call_deferred()
	refresh()


func refining_focus_control() -> Control:
	_navigation.select(1)
	_show_section(1)
	return _recipe


func _add_section(title: String, ranges: Array, original: Array[Node], section_root: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_root.add_child(section)
	_sections.append(section)
	_navigation.add_item(title)
	for bounds in ranges:
		for index in range(original.find(bounds[0]), original.find(bounds[1]) + 1):
			var control: Node = original[index]
			# Mass is shared across gathering, cargo and fluid tasks.
			if control != _amount:
				control.reparent(section)


func _show_section(index: int) -> void:
	for current in range(_sections.size()):
		_sections[current].visible = current == index
	_section_scroll.scroll_vertical = 0


func _guide_action() -> void:
	refresh()
	var suggested: Dictionary = _guide.suggested_action()
	if suggested["operation"] == "" or _record.is_empty():
		return
	var payload: Dictionary = suggested["payload"].duplicate(true)
	if suggested["operation"] in ["extract", "unload_cargo"]:
		if _carrier.selected < 0:
			_feedback.text = "Collect a canister from the storage tray first."
			return
		payload["carrier_id"] = _carrier.get_item_text(_carrier.selected)
	elif suggested["operation"] == "recycle_component":
		if _record.get("components", []).is_empty():
			_feedback.text = "Collect a printed plate first."
			return
		payload["item_id"] = _record["components"][0]
	_send(suggested["operation"], payload)


func _selected_action(operation: String, field: String, picker: OptionButton) -> void:
	if picker.selected >= 0:
		var metadata: Variant = picker.get_item_metadata(picker.selected)
		_send(operation, {field: String(metadata) if metadata != null else picker.get_item_text(picker.selected)})


func _add_recipe(id: String) -> void:
	_recipe.add_item(RECIPE_LABELS.get(id, id))
	_recipe.set_item_metadata(_recipe.item_count - 1, id)


func _chemical_action(operation: String) -> void:
	if _chemical.selected >= 0:
		_send(operation, {"material": _chemical.get_item_text(_chemical.selected), "amount_milligrams": int(round(_amount.value * 1000.0))})


func _cargo_action(operation: String) -> void:
	if _carrier.selected >= 0 and _cargo_material.selected >= 0:
		_send(operation, {"carrier_id": _carrier.get_item_text(_carrier.selected), "material": _cargo_material.get_item_text(_cargo_material.selected), "amount_milligrams": int(round(_amount.value * 1000.0))})


func select_source(deposit_id: String) -> void:
	for index in range(_deposit.item_count):
		if _deposit.get_item_text(index) == deposit_id:
			_deposit.select(index)
			refresh()
			return


func extract_source(deposit_id: String) -> void:
	select_source(deposit_id)
	_extract_action()


func _extract_action() -> void:
	if _carrier.selected >= 0 and _deposit.selected >= 0:
		_send("extract", {"carrier_id": _carrier.get_item_text(_carrier.selected), "deposit_id": _deposit.get_item_text(_deposit.selected), "amount_milligrams": int(round(_amount.value * 1000.0))})


func _refresh_equipment() -> void:
	if _blueprint == null: return
	var blueprints: Dictionary = _record.get("blueprints", {})
	var entries: Dictionary = {}
	for id in blueprints: entries[id] = blueprints[id]["name"]
	EquipmentPrerequisiteView.fill(_blueprint, entries, "Select equipment blueprint")
	entries = {}
	for id in _record.get("structures", {}):
		var blueprint_id: String = _record["structures"][id]["blueprint_id"]
		entries[id] = blueprints.get(blueprint_id, {}).get("name", blueprint_id)
	EquipmentPrerequisiteView.fill(_equipment, entries, "Select owned fabricated equipment")
	_fabrication_details.text = EquipmentPrerequisiteView.quote(_record, blueprints, EquipmentPrerequisiteView.selected(_blueprint), "printer")
	var item_id: String = EquipmentPrerequisiteView.selected(_equipment)
	if _record.get("structures", {}).has(item_id):
		var structure: Dictionary = _record["structures"][item_id]
		_fabrication_details.text += "\nOwned equipment ID: %s; recoverable installed materials: %s." % [item_id, WorkstationResourceView.stock_text(structure["materials"])]
		_fabrication_details.text += "\nSalvage energy: %d J; recycler power: %s. Contents return to shared stock; host checks receiving capacity. Spent energy is not recovered." % [blueprints[structure["blueprint_id"]]["salvage_energy_joules"], "on" if _record["powered"]["recycler"] else "off"]
	else:
		_fabrication_details.text += "\nSelect owned fabricated equipment to inspect salvage. Previous ID: " + item_id
	if not _pending.is_empty(): _fabrication_details.text += "\nCommand pending: no output confirmed; wait for host receipt."
	_blueprint.disabled = _record.is_empty() or not _pending.is_empty()
	_equipment.disabled = _blueprint.disabled


func _fabricate_equipment() -> void:
	refresh()
	if _record.get("blueprints", {}).has(EquipmentPrerequisiteView.selected(_blueprint)):
		_send("fabricate_equipment", {"blueprint_id": _blueprint.get_item_metadata(_blueprint.selected)})


func _salvage_equipment() -> void:
	refresh()
	if _record.get("structures", {}).has(EquipmentPrerequisiteView.selected(_equipment)):
		_send("salvage_equipment", {"item_id": _equipment.get_item_metadata(_equipment.selected)})


func _fill_carriers(ids: Array) -> void:
	if _carrier == null:
		return
	var previous: String = _carrier.get_item_text(_carrier.selected) if _carrier.selected >= 0 else ""
	var unchanged: bool = _carrier.item_count == ids.size()
	for index in range(ids.size()):
		if not unchanged or _carrier.get_item_text(index) != ids[index]:
			unchanged = false
			break
	if unchanged:
		return
	_carrier.clear()
	for id in ids:
		_carrier.add_item(id)
		if id == previous:
			_carrier.select(_carrier.item_count - 1)


func _fill_components(ids: Array) -> void:
	if _components == null:
		return
	var previous: String = _components.get_item_text(_components.selected) if _components.selected >= 0 else ""
	_components.clear()
	for id in ids:
		_components.add_item(id)
		if id == previous:
			_components.select(_components.item_count - 1)


func _toggle_power() -> void:
	refresh()
	if not _record.is_empty() and _station.selected >= 0:
		var id: String = _station.get_item_text(_station.selected)
		_send("power", {"station": id, "enabled": not _record["powered"][id]})


func _on_completed(command: SimulationCommand, result: ServiceResult) -> void:
	if command is ProductionDevelopmentCommand and result.is_success and command.operation == "cancel":
		_guide.cancel_recipe()
	if not command is ProductionDevelopmentCommand or String(command.command_id) != _pending:
		return
	_pending = ""
	if command.operation == "repair_tool_component":
		_maintenance_feedback.text = ("Accepted: maintenance command completed. Await current condition observation." if result.is_success else "Rejected: " + result.message)
		refresh()
		return
	if result.is_success:
		_guide.note_command(command.operation, command.payload)
	_feedback.text = "Applied " + command.operation if result.is_success else "Rejected: " + result.message
	_reveal_receipt.call_deferred()
	refresh()


## The actual client adds headers and an outer scroll above this panel.
func _reveal_receipt() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not _feedback.is_visible_in_tree(): return
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(_feedback)
			return
		ancestor = ancestor.get_parent()


func _on_batch_completed(recipe_id: String, _tick: int) -> void:
	# Keep the tick callback bounded; regular HUD polling updates the text.
	_guide.note_batch_completed(recipe_id)


func _on_closed() -> void:
	_world = null
	_record = {}
	_tool_record = {}
	observation_changed.emit({})
	_pending = ""
	_status.text = "Production unavailable: world closed"
	_recipe_details.text = "Recipe prerequisites unavailable: world closed; command outcome requires a fresh observation."
	_guide_label.text = "Collection guide closed; progress was session-only."
	_fill_carriers([])
	_fill_components([])
	_fill_recipes([])
	_resource_view.describe({}, "")
	_feedback.text = ""
	_activity.text = "Unavailable: world closed; command outcome requires a fresh observation."
	_gather_details.text = "Unavailable: source and payload require a fresh observation."
	_refresh_maintenance()
	_maintenance_feedback.text = "Unavailable: world or host connection closed; command outcome requires a fresh observation."
	_refresh_equipment()
	_fabrication_details.text = "Unavailable: world closed; command outcome requires a fresh observation."
	for button in _buttons:
		button.disabled = true
	set_process(false)


func _context() -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", _world.world_id, _world.region_id)


func _label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label


func _picker() -> OptionButton:
	var picker := OptionButton.new()
	picker.clip_text = true
	picker.fit_to_longest_item = false
	add_child(picker)
	return picker


func _button(title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(callback)
	add_child(button)
	_buttons.append(button)
	return button


static func _stock_text(stock: Dictionary) -> String:
	var entries: PackedStringArray = []
	for id in stock:
		if int(stock[id]) > 0:
			entries.append("%s %.3f kg" % [id, float(stock[id]) / 1000000.0])
	return ", ".join(entries) if not entries.is_empty() else "empty"


func _observe_tools(frame: Dictionary) -> void:
	_tool_record = frame.get("tools", {}).duplicate(true)
	refresh()


func _select_maintenance_part(index: int) -> void:
	_selected_part_id = str(_maintenance_parts.get_item_metadata(index))
	_maintenance_feedback.text = "Preview: selection changed; no command submitted."
	_refresh_maintenance()


func _refresh_maintenance() -> void:
	if _maintenance_parts == null:
		return
	var entries: Dictionary = ToolMaintenanceView.components(_tool_record)
	var choices: Array = []
	for id in entries:
		choices.append([id, entries[id]["part"]["name"]])
	var choice_key: String = JSON.stringify(choices)
	if choice_key != _maintenance_choice_key:
		_maintenance_choice_key = choice_key
		_maintenance_parts.clear()
		_maintenance_parts.add_item("Select a component")
		_maintenance_parts.set_item_metadata(0, "")
		for choice in choices:
			_maintenance_parts.add_item("%s · %s" % [choice[1], choice[0]])
			_maintenance_parts.set_item_metadata(_maintenance_parts.item_count - 1, choice[0])
			if choice[0] == _selected_part_id:
				_maintenance_parts.select(_maintenance_parts.item_count - 1)
	# Missing IDs remain remembered but never retarget to the first remaining part.
	_maintenance_details.text = ToolMaintenanceView.describe(_tool_record, _record, _selected_part_id)
	var reason: String = ToolMaintenanceView.blocker(_tool_record, _record, _selected_part_id)
	_maintenance_button.disabled = not _pending.is_empty() or not reason.is_empty()
	_maintenance_button.tooltip_text = reason
	_maintenance_parts.disabled = _tool_record.is_empty() or not _pending.is_empty()


func _maintain_component() -> void:
	if not _pending.is_empty() or not is_instance_valid(_world):
		return
	refresh()
	var reason: String = ToolMaintenanceView.blocker(_tool_record, _record, _selected_part_id)
	if not reason.is_empty():
		_maintenance_feedback.text = "Unavailable: " + reason
		return
	_send("repair_tool_component", {"part_id": _selected_part_id, "amount_ppm": 1000000, "expected_tool_revision": _tool_record["state_revision"]})
	_maintenance_feedback.text = "Queued: maintenance awaits the authoritative tick result." if not _pending.is_empty() else "Rejected: " + _feedback.text


func _fill_recipes(ids: Array) -> void:
	var previous: String = str(_recipe.get_item_metadata(_recipe.selected)) if _recipe.selected >= 0 else ""
	var current: Array = []
	for index in range(_recipe.item_count): current.append(_recipe.get_item_metadata(index))
	if current == ids: return
	_recipe.clear()
	for id in ids:
		_add_recipe(id)
		if id == previous: _recipe.select(_recipe.item_count - 1)
