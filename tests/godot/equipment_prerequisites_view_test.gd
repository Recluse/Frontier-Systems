extends SceneTree

class RecordingRemote extends RemoteWorldRuntime:
	var sent: Array[SimulationCommand] = []
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		sent.append(command)
		return ServiceResult.success()

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func choose(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == id: picker.select(index)

func run() -> void:
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	var context := AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-actor", &"equipment-test", world.world_id, world.region_id, PackedStringArray(["inventory.operate", "terrain.operate"]))
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var tools: Dictionary = world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID).observation(context).value
	var production: Dictionary = world.production_observation(context).value
	var before: String = world.capture_world_snapshot_json().value
	var blueprint_id: String = tools["part_blueprints"].keys()[0]
	var blueprint: Dictionary = tools["part_blueprints"][blueprint_id]
	var text: String = EquipmentPrerequisiteView.quote(production, tools["part_blueprints"], blueprint_id, "printer")
	for material in blueprint["materials"]:
		check(text.contains("required %d mg" % blueprint["materials"][material]) and text.contains("shared stock %d mg" % production["store"].get(material, 0)), "exact observed costs and stock")
	check(text.contains("reserve: %d J" % production["energy_joules"]) and text.contains("are not shared stock"), "energy and physical distinction")
	var exhausted: Dictionary = production.duplicate(true)
	exhausted["energy_joules"] = 0
	exhausted["powered"]["printer"] = false
	for material in blueprint["materials"]: exhausted["store"][material] = 0
	var exhausted_text: String = EquipmentPrerequisiteView.quote(exhausted, tools["part_blueprints"], blueprint_id, "printer")
	check(exhausted_text.contains("reserve: 0 J") and exhausted_text.contains("printer power: off"), "finite energy and power shown")
	for material in blueprint["materials"]:
		check(exhausted_text.contains("shortfall %d mg" % blueprint["materials"][material]), "exact shortage does not count other matter")
	var legacy_production: Dictionary = production.duplicate(true)
	legacy_production["schema_version"] = 7
	legacy_production.erase("recipe_requirements")
	check(EquipmentPrerequisiteView.quote(legacy_production, legacy_production["blueprints"], legacy_production["blueprints"].keys()[0], "printer").contains("Blueprint:"), "legacy equipment observations retain existing blueprint costs")
	var legacy: Dictionary = tools.duplicate(true)
	legacy["schema_version"] = 2
	legacy.erase("maintenance")
	check(EquipmentPrerequisiteView.part_text(legacy, production, blueprint_id, "extractor-1", "head", "", false).contains("future capability recovery are not observed"), "legacy parts remain readable without repair prediction")
	check(EquipmentPrerequisiteView.part_text({"assemblies": 9}, production, "", "", "", "", false).contains("unavailable"), "malformed tool unavailable")
	check(EquipmentPrerequisiteView.quote({}, {}, "", "printer").contains("unavailable"), "missing production unavailable")
	var partial: Dictionary = legacy.duplicate(true)
	partial["assemblies"][0]["actions"]["fixture.disabled"] = {"available": false, "missing_functions": ["fixture.function"]}
	partial["assemblies"][0]["actions"]["fixture.retained"] = {"available": true, "missing_functions": []}
	var partial_text: String = EquipmentPrerequisiteView.part_text(partial, production, blueprint_id, partial["assemblies"][0]["assembly_id"], "head", "", true)
	check(partial_text.contains("fixture.disabled: disabled") and partial_text.contains("fixture.retained: available") and partial_text.contains("Command pending"), "capability loss and retained functionality reported only as observed")
	var picker := OptionButton.new()
	EquipmentPrerequisiteView.fill(picker, {"b": "Same", "a": "Same"}, "Select")
	check(EquipmentPrerequisiteView.selected(picker) == "", "explicit initial selection")
	choose(picker, "b")
	EquipmentPrerequisiteView.fill(picker, {"a": "Same"}, "Select")
	check(EquipmentPrerequisiteView.selected(picker) == "b" and picker.is_item_disabled(picker.selected), "missing stable identity remains pinned")
	EquipmentPrerequisiteView.fill(picker, {"b": "Renamed", "a": "Same"}, "Select")
	check(EquipmentPrerequisiteView.selected(picker) == "b" and not picker.is_item_disabled(picker.selected), "reappearing stable identity")
	picker.free()
	var remote := RecordingRemote.new()
	root.add_child(remote)
	remote.set_process(false)
	remote._authenticated = true
	remote._receive(JSON.parse_string(JSON.stringify({"type": "observation", "tools": tools, "production": production, "terrain": world.terrain_observation(context).value, "inventory": inventory.own_inventory_observation(context, true).value, "position": [0, 0, 0], "players": []})))
	check(not remote._observation.is_empty(), "real receive accepts current frame")
	if not remote._observation.is_empty():
		check(EquipmentPrerequisiteView.part_text(remote._observation["tools"], remote._observation["production"], blueprint_id, "extractor-1", "head", "", false) == EquipmentPrerequisiteView.part_text(tools, production, blueprint_id, "extractor-1", "head", "", false), "local remote parity")
	remote._connecting = true
	remote._process(0)
	check(remote._observation.is_empty(), "remote disconnect retires prerequisites")
	remote.free()
	var local := LocalProductionPanel.new()
	root.add_child(local)
	check(local.configure(world).is_success, "local equipment panel configures")
	local.set_process(false)
	var equipment_id: String = production["blueprints"].keys()[0]
	choose(local._blueprint, equipment_id)
	local.refresh()
	check(local._fabrication_details.text.contains(equipment_id), "equipment observation detail")
	check(world.capture_world_snapshot_json().value == before, "presentation never changes canonical state")
	var owner_before: Dictionary = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID).capture_snapshot().value
	local._fabricate_equipment()
	check(not local._pending.is_empty() and local._fabrication_details.text.contains("Command pending") and local._blueprint.disabled, "equipment pending has no output claim")
	var pending := ProductionDevelopmentCommand.new()
	pending.command_id = StringName(local._pending)
	pending.operation = "fabricate_equipment"
	local._on_completed(pending, ServiceResult.failure(&"fixture_rejection", "stock changed"))
	check(local._feedback.text.contains("Rejected: stock changed") and local._pending.is_empty(), "equipment rejection preserves host reason")
	local._on_closed()
	check(local._fabrication_details.text.contains("outcome requires a fresh observation"), "equipment disconnect uncertainty")
	local.free()
	check(world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID).capture_snapshot().value == owner_before, "queued intent does not mutate production before tick")
	world.free()
	if failures == 0: print("Equipment prerequisites: observed costs, legacy/malformed, local/remote, stable selection, pending, rejection, disconnect and immutable state passed.")
	quit(0 if failures == 0 else 1)
