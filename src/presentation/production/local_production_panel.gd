extends VBoxContainer
class_name LocalProductionPanel

signal observation_changed(record: Dictionary)

const RECIPE_LABELS: Dictionary = {
	"refine.iron": "Refine 1 kg iron ore → 600 g iron + 400 g tailings",
	"craft.plate": "Print a plate from 1 kg iron",
	"salvage.plate": "Recycle a plate → 1 kg iron",
	"refine.ice": "Melt 1 kg ice → 1 kg water",
	"refine.regolith": "Separate regolith → salts, silicate and tailings",
	"chemical.electrolysis": "Separate water → hydrogen and oxygen",
	"chemical.nutrients": "Mix water and salts → nutrient solution"
}

## Shared fixture workstation UI. Observations in, fixed-tick intents out.
var _world: WorldRuntime
var _configured: bool = false
var _status: Label
var _feedback: Label
var _deposit: OptionButton
var _blueprint: OptionButton
var _equipment: OptionButton
var _recipe: OptionButton
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
var _nonce: String = str(Time.get_ticks_usec())


func configure(world: WorldRuntime) -> ServiceResult:
	if _configured or not is_instance_valid(world):
		return ServiceResult.failure(&"production_panel_configuration", "Configure one world per production panel.")
	_configured = true
	_world = world
	_world.command_completed.connect(_on_completed)
	_world.tree_exiting.connect(_on_closed)
	var title := _label()
	title.text = "Extract, store, refine and recycle"
	var instructions := _label()
	instructions.text = "Choose First person or Third person and use your configured navigation controls. Hold the UI cursor key to interact with panels. Approach a resource source; select it or double-click to extract into your canister. Your position determines which equipment you can reach."
	_guide_label = _label()
	_guide_button = _button("Next collection step", _guide_action)
	_status = _label()
	_deposit = _picker()
	for id in ["deposit.iron", "deposit.ice", "deposit.regolith"]:
		_deposit.add_item(id)
	_deposit.item_selected.connect(func(_index: int) -> void: refresh())
	_extract_button = _button("Extract selected mass into canister (up to 1 kg)", _extract_action)
	_recipe = _picker()
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
	_button("Cancel batch (recover feedstock; energy spent)", _send.bind("cancel", {}))
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
	_button("Return selected mass to storage", _chemical_action.bind("return"))
	var cargo_title := _label()
	cargo_title.text = "Portable canisters (own inventory only; 2 kg payload limit)"
	_carrier = _picker()
	_cargo_material = _picker()
	if observed.is_success:
		for id in observed.value["store"]:
			_cargo_material.add_item(id)
	_button("Load selected mass into carried canister", _cargo_action.bind("load_cargo"))
	_button("Unload selected mass to workstation", _cargo_action.bind("unload_cargo"))
	_button("Collect printed plate into inventory", _send.bind("materialize_plate", {}))
	_components = _picker()
	_button("Recycle selected carried plate", _selected_action.bind("recycle_component", "item_id", _components))
	var fabrication_title := _label()
	fabrication_title.text = "Equipment fabrication · recoverable construction materials"
	_blueprint = _picker()
	if observed.is_success:
		for id in observed.value.get("blueprints", {}):
			var blueprint: Dictionary = observed.value["blueprints"][id]
			var requirements: PackedStringArray = []
			for material in blueprint["materials"]:
				requirements.append("%.2f kg %s" % [float(blueprint["materials"][material]) / 1000000.0, material])
			_blueprint.add_item("%s · %s · %d J" % [blueprint["name"], ", ".join(requirements), blueprint["fabrication_energy_joules"]])
			_blueprint.set_item_metadata(_blueprint.item_count - 1, id)
	_button("Fabricate selected equipment into inventory", _fabricate_equipment)
	_equipment = _picker()
	_button("Salvage selected fabricated equipment and contents", _salvage_equipment)
	_button("Build 1 kg wall segment", _send.bind("build", {}))
	_button("Deconstruct one wall segment", _send.bind("deconstruct", {}))
	_station = _picker()
	for id in ProductionSimulationSystem.STATIONS:
		_station.add_item(id)
	_button("Toggle selected station power", _toggle_power)
	_feedback = _label()
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
	if observed.is_success and _equipment != null:
		var selected: String = str(_equipment.get_item_metadata(_equipment.selected)) if _equipment.selected >= 0 else ""
		_equipment.clear()
		for id in observed.value.get("structures", {}):
			var structure: Dictionary = observed.value["structures"][id]
			_equipment.add_item(observed.value["blueprints"][structure["blueprint_id"]]["name"])
			_equipment.set_item_metadata(_equipment.item_count - 1, id)
			if selected == id:
				_equipment.select(_equipment.item_count - 1)
	_record = observed.value if observed.is_success else {}
	observation_changed.emit(_record.duplicate(true))
	_fill_carriers(_record.get("cargo", {}).keys())
	_fill_components(_record.get("components", []))
	for button in _buttons:
		button.disabled = not _pending.is_empty() or _record.is_empty() or not _record.get("can_operate", false)
	_extract_button.disabled = not _pending.is_empty() or _record.is_empty() or _carrier.selected < 0 or _deposit.selected < 0 or not _record.get("extractable_sources", []).has(_deposit.get_item_text(_deposit.selected))
	var suggested: Dictionary = _guide.suggested_action()
	_guide_button.text = suggested["label"]
	_guide_button.disabled = not _pending.is_empty() or suggested["operation"] == "" or _record.is_empty() or (not _record.get("can_operate", false) if suggested["operation"] != "extract" else not _record.get("extractable_sources", []).has("deposit.iron"))
	if _record.is_empty():
		_status.text = "Production unavailable: move within reach of the logical workstation."
		return
	var lines: PackedStringArray = []
	lines.append("Workstation: within reach" if _record["can_operate"] else "Workstation actions unavailable: approach it with a conscious body and an unreserved hand.")
	lines.append("Extractable sources in reach: " + (", ".join(PackedStringArray(_record["extractable_sources"])) if not _record["extractable_sources"].is_empty() else "none"))
	for id in _record["deposits"]:
		lines.append("%s: %.2f kg remaining" % [{"deposit.iron": "Iron ore", "deposit.ice": "Ice", "deposit.regolith": "Regolith"}.get(id, id), float(_record["deposits"][id]) / 1000000.0])
	lines.append("Storage: " + _stock_text(_record["store"]))
	lines.append("Vessel (2 kg capacity): " + _stock_text(_record["vessel"]))
	lines.append("Sealed vessel pressure: %.1f kPa / 1000 kPa limit" % _record["vessel_pressure_kpa"])
	for id in _record["cargo"]:
		lines.append("%s: %s" % [id, _stock_text(_record["cargo"][id])])
	lines.append("Built wall segments: %d · energy: %d J" % [int(_record["wall_mass_milligrams"]) / 1000000, _record["energy_joules"]])
	if _record["job"].is_empty():
		lines.append("Workstation idle")
	else:
		var job: Dictionary = _record["job"]
		lines.append("%s: %.1f seconds remaining%s" % [job["station"], float(job["remaining_ticks"]) / float(_record["timebase_hz"]), " (paused: no power)" if not _record["powered"][job["station"]] else ""])
	var disabled: PackedStringArray = []
	for id in _record["powered"]:
		if not _record["powered"][id]:
			disabled.append(id)
	lines.append("Unpowered: " + (", ".join(disabled) if not disabled.is_empty() else "none"))
	_status.text = "\n".join(lines)


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
	refresh()


func refining_focus_control() -> Control:
	return _recipe


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


func _fabricate_equipment() -> void:
	if _blueprint.selected >= 0:
		_send("fabricate_equipment", {"blueprint_id": _blueprint.get_item_metadata(_blueprint.selected)})


func _salvage_equipment() -> void:
	if _equipment.selected >= 0:
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
	if result.is_success:
		_guide.note_command(command.operation, command.payload)
	_feedback.text = "Applied " + command.operation if result.is_success else "Rejected: " + result.message
	refresh()


func _on_batch_completed(recipe_id: String, _tick: int) -> void:
	# Keep the tick callback bounded; regular HUD polling updates the text.
	_guide.note_batch_completed(recipe_id)


func _on_closed() -> void:
	_world = null
	_record = {}
	observation_changed.emit({})
	_pending = ""
	_status.text = "Production unavailable: world closed"
	_guide_label.text = "Collection guide closed; progress was session-only."
	_fill_carriers([])
	_feedback.text = ""
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
	add_child(picker)
	return picker


func _button(title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
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
