extends SceneTree

class RecordingRemote extends RemoteWorldRuntime:
	var sent: Array[SimulationCommand] = []
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		sent.append(command)
		return ServiceResult.success()

var world: WorldRuntime
var context: AuthenticatedCommandContext
var panel: PlayerInventoryPanel
var remote: RecordingRemote
var last: ServiceResult
var sequence: int = 0
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

func select_tool(id: String) -> void:
	for index in range(panel._items.item_count):
		if panel._items.get_item_metadata(index)["item_id"] == id: panel._items.select(index)
	panel._inspect()
	panel._update_buttons()

func frame() -> Dictionary:
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	return {"inventory": inventory.own_inventory_observation(context, true).value, "production": world.production_observation(context).value, "tools": world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID).observation(context).value, "world_items": inventory.world_inventory_observation(context).value}

func step() -> void:
	world.get_node("SimulationRunner")._physics_process(1.0 / 60.0)

func apply(command: SimulationCommand) -> void:
	command.authenticated_context = context
	check(world.enqueue_command(command).is_success, "real owner queues intent")
	step()

func command(operation: String, payload: Dictionary) -> void:
	sequence += 1
	var request := ProductionDevelopmentCommand.new()
	request.command_id = StringName("component-fixture-%d" % sequence)
	request.operation = operation
	payload["expected_revision"] = frame()["production"]["state_revision"]
	request.payload = payload
	apply(request)
	check(last.is_success, operation + ": " + last.message)

func move(position: Array) -> void:
	sequence += 1
	var request := InventoryDevelopmentCommand.new()
	request.command_id = StringName("component-move-%d" % sequence)
	request.operation = "move_to"
	request.payload = {"position_millimetres": position}
	apply(request)
	check(last.is_success, "fixture moves")

func panel_action(operation: String) -> void:
	var before: Dictionary = frame()
	panel._part_action(operation)
	check(not panel._pending.is_empty() and not panel._pending_component.is_empty(), operation + " queues exact IDs")
	check(frame() == before, "queued panel intent changes no canonical state before tick")
	check(panel._part_blueprints.disabled and panel._loose_parts.disabled and panel._tool_mounts.disabled and panel._tool_parts.disabled, "all component pickers freeze pending")
	var pinned: Dictionary = panel._pending_component.duplicate(true)
	var waiting: String = panel._result.text
	panel.observe(before)
	panel._part_action(operation)
	check(panel._pending_component == pinned and panel._result.text == waiting, "pending refresh/retry preserves exact target")
	apply(remote.sent[-1])
	check(last.is_success, operation + ": " + last.message)
	remote.command_completed.emit(remote.sent[-1], last)
	panel.observe(frame())
	check(panel._pending_component.is_empty(), "receipt clears component pending IDs")

func run() -> void:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	remote = RecordingRemote.new()
	root.add_child(remote)
	panel = PlayerInventoryPanel.new()
	root.add_child(panel)
	panel.configure(remote)
	panel.observe(frame())
	check(panel._picker_id(panel._part_blueprints).is_empty() and panel._component_buttons["fabricate_tool_part"].disabled, "blueprints require explicit selection")
	choose(panel._part_blueprints, "part.head.basic")
	panel._update_buttons()
	check(panel._component_details.text.contains("shortfall") and panel._component_buttons["fabricate_tool_part"].disabled, "zero shared stock does not count carried or mounted material")
	for _batch in range(6):
		move(ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		for _tick in range(120): step()
	command("fabricate_equipment", {"blueprint_id": "equipment.extractor"})
	panel.observe(frame())
	var tool: String = frame()["production"]["structures"].keys()[0]
	select_tool(tool)
	choose(panel._tool_mounts, "head")
	var old_head: String = ""
	for assembly in frame()["tools"]["assemblies"]:
		if assembly["assembly_id"] == tool: old_head = assembly["slots"]["head"]
	choose(panel._tool_parts, old_head)
	var reordered: Dictionary = frame()
	reordered["tools"]["assemblies"].reverse()
	for assembly in reordered["tools"]["assemblies"]: assembly["parts"].reverse()
	panel.observe(reordered)
	check(panel._picker_id(panel._tool_parts) == old_head and panel._picker_id(panel._tool_mounts) == "head", "component and mount IDs survive reordered records")
	var missing_mount: Dictionary = reordered.duplicate(true)
	missing_mount["tools"]["schema_version"] = 2
	missing_mount["tools"].erase("maintenance")
	for assembly in missing_mount["tools"]["assemblies"]:
		if assembly["assembly_id"] != tool: continue
		assembly["slots"].erase("head")
		for index in range(assembly["parts"].size() - 1, -1, -1):
			if assembly["parts"][index]["part_id"] == old_head: assembly["parts"].remove_at(index)
	panel.observe(missing_mount)
	check(panel._picker_id(panel._tool_mounts) == "head" and panel._tool_mounts.is_item_disabled(panel._tool_mounts.selected) and panel._tool_parts.is_item_disabled(panel._tool_parts.selected), "missing mount and component keep unavailable IDs")
	panel.observe(frame())
	check(panel._picker_id(panel._tool_parts) == old_head and not panel._tool_parts.is_item_disabled(panel._tool_parts.selected), "same component reappears without retarget")
	var unavailable: Dictionary = frame()
	unavailable["production"]["can_operate"] = false
	panel.observe(unavailable)
	check(panel._component_buttons["fabricate_tool_part"].disabled and panel._component_details.text.contains("access: unavailable"), "observed access loss blocks action")
	unavailable = frame()
	unavailable["production"]["powered"]["construction"] = false
	panel.observe(unavailable)
	check(panel._component_buttons["detach_tool_part"].disabled and panel._component_details.text.contains("construction power: off"), "observed construction power loss blocks detach")
	panel.observe(frame())
	var energy: int = frame()["production"]["energy_joules"]
	var cost: int = frame()["tools"]["part_blueprints"]["part.head.basic"]["fabrication_energy_joules"]
	panel_action("fabricate_tool_part")
	check(frame()["production"]["energy_joules"] == energy - cost, "fabrication pays observed exact cost")
	var loose: String = frame()["tools"]["loose_parts"][0]["part_id"]
	choose(panel._loose_parts, loose)
	choose(panel._tool_mounts, "head")
	panel._update_buttons()
	check(panel._component_details.text.contains("Matching recycling specification") and panel._component_details.text.contains("construction power: on"), "recycle cost and station prerequisites displayed")
	panel_action("fit_tool_part")
	check(panel._picker_id(panel._loose_parts) == loose and panel._loose_parts.is_item_disabled(panel._loose_parts.selected), "mounted loose ID remains unavailable without retarget to displaced part")
	var returned: bool = false
	for part in frame()["tools"]["loose_parts"]:
		if part["part_id"] == old_head: returned = true
	check(returned, "displaced head retained as same owned physical ID")
	panel_action("detach_tool_part")
	check(panel._picker_id(panel._loose_parts) == loose and not panel._loose_parts.is_item_disabled(panel._loose_parts.selected), "detached same ID reappears")
	check(panel._component_details.text.contains("disabled; missing"), "missing head reports observed capability loss")
	energy = frame()["production"]["energy_joules"]
	cost = frame()["tools"]["part_blueprints"]["part.head.basic"]["salvage_energy_joules"]
	panel_action("recycle_tool_part")
	check(frame()["production"]["energy_joules"] == energy - cost and panel._component_buttons["recycle_tool_part"].disabled, "recycle pays cost and removed ID cannot retarget")
	choose(panel._loose_parts, old_head)
	panel._update_buttons()
	panel._part_action("fit_tool_part")
	var request: SimulationCommand = remote.sent[-1]
	# Intervening real paid work makes the queued revision stale.
	command("fabricate_tool_part", {"blueprint_id": "part.head.basic", "expected_tool_revision": frame()["tools"]["state_revision"]})
	var before_rejection: Dictionary = frame()
	apply(request)
	check(not last.is_success and frame()["tools"] == before_rejection["tools"] and frame()["production"]["energy_joules"] == before_rejection["production"]["energy_joules"], "stale paid action rejected atomically")
	remote.command_completed.emit(request, last)
	check(panel._result.text.contains(last.message), "host rejection reason preserved")
	var legacy: Dictionary = frame()
	legacy["tools"]["schema_version"] = 2
	legacy["tools"].erase("maintenance")
	legacy["production"]["schema_version"] = 7
	legacy["production"].erase("recipe_requirements")
	panel.observe(legacy)
	check(panel._component_details.text.contains("Blueprint:") and panel._component_details.text.contains("Tool ID:"), "legacy v2/v7 remains readable")
	var vanished: Dictionary = legacy.duplicate(true)
	vanished["tools"]["part_blueprints"].erase("part.head.basic")
	panel.observe(vanished)
	check(panel._picker_id(panel._part_blueprints) == "part.head.basic" and panel._component_buttons["fabricate_tool_part"].disabled, "missing blueprint stable ID retained and blocked")
	panel.observe(legacy)
	check(panel._picker_id(panel._part_blueprints) == "part.head.basic", "returning blueprint restores same ID")
	panel._part_action("fit_tool_part")
	remote.connection_closed.emit("Disconnected")
	check(panel._pending_component.is_empty() and panel._tools.is_empty() and panel._tool_mounts.item_count == 0 and panel._result.text.contains("outcome is unknown"), "disconnect clears observations and pending IDs without success claim")
	panel.free()
	remote.free()
	world.free()
	if failures == 0: print("Inventory component UI: paid transactions, stable IDs, rejection, legacy and disconnect passed.")
	quit(0 if failures == 0 else 1)
