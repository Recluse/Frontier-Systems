extends "res://tests/godot/machinery_runtime_test.gd"


func run() -> void:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: last = result)
	check(world.start_simulation().is_success, "world starts")
	runner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	var view := WorkstationResourceView.new()
	var initial: Dictionary = production.observation(context).value
	var before: String = world.capture_world_snapshot_json().value
	var text: String = view.describe(initial, "refine.iron")
	check(text.contains("shared ore.iron short by 1.000 kg") and text.contains("Host catalog requirements"), "missing input uses host requirements")
	check(text.contains("Duration and capacity quote unavailable") and not text.contains("fixture"), "no fixture assumptions or capacity quote")
	for partial in [{}, {"store": {}}, {"components": [42]}]:
		check(view.describe(partial, "craft.plate").contains("unavailable"), "partial observations clear resource claims")
	var rejected: Dictionary = initial.duplicate(true)
	rejected["energy_joules"] = -1
	check(view.describe(rejected, "craft.plate").contains("unavailable"), "malformed observation rejected")
	check(world.capture_world_snapshot_json().value == before and production.observation(context).value == initial, "helper preserves canonical snapshot and input observation")
	var panel := LocalProductionPanel.new()
	panel.custom_minimum_size.x = 420
	root.add_child(panel)
	check(panel.configure(world).is_success, "panel configures")
	check(panel._status.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and panel._recipe.clip_text and not panel._recipe.fit_to_longest_item, "narrow panel wraps and picker does not impose long width")
	for index in range(panel._recipe.item_count):
		if panel._recipe.get_item_metadata(index) == "craft.plate": panel._recipe.select(index)
	panel.refresh()
	check(panel._recipe_details.text.contains("Selected: craft.plate") and panel.get_children().find(panel._recipe_details) == panel.get_children().find(panel._recipe) + 1, "current recipe details beside stable selector")
	panel.refresh()
	check(panel._recipe.get_item_metadata(panel._recipe.selected) == "craft.plate", "poll retains recipe ID")
	move([-3000, 0, -1000])
	command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
	text = view.describe(production.observation(context).value, "refine.iron")
	check(text.contains("resource-canister-1: ore.iron 1.000 kg") and text.contains("shared ore.iron short by 1.000 kg"), "carried ore does not pay shared recipe inputs")
	move([0, 0, 0])
	command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
	panel._send("process", {"recipe_id": "refine.iron"})
	check(panel._status.text.contains("Command queued") and panel._status.text.contains("Physical plates owned: 0"), "queued is not active or physical output")
	step(1)
	panel.refresh()
	check(panel._status.text.contains("Active job: refine.iron"), "accepted current job")
	view.describe(production.observation(context).value, "craft.plate")
	command("power", {"station": "refinery", "enabled": false})
	check(view.describe(production.observation(context).value, "craft.plate").contains("Paused job"), "power loss pauses observed work")
	command("cancel", {})
	check(view.describe(production.observation(context).value, "craft.plate").contains("completion or cancellation is unconfirmed"), "disappeared job does not invent success")
	panel._send("process", {"recipe_id": "refine.iron"})
	step(1)
	panel.refresh()
	check(panel._feedback.text.begins_with("Rejected:") and not panel._status.text.contains("Command queued"), "rejection releases queue without inventing output")
	var limited: Dictionary = initial.duplicate(true)
	limited["energy_joules"] = 0
	limited["can_operate"] = false
	limited["powered"]["printer"] = false
	text = view.describe(limited, "craft.plate")
	check(text.contains("energy short by 1000 J") and text.contains("printer needs power") and text.contains("conscious body"), "simultaneous current blockers")
	limited["store"]["plate"] = 1000000
	text = view.describe(limited, "craft.plate")
	check(text.contains("Physical plates owned: 0. Printed shared stock: 1.000 kg"), "printed stock is not physical inventory")
	panel._fill_recipes(["refine.iron", "craft.plate"])
	check(panel._recipe.get_item_metadata(panel._recipe.selected) == "craft.plate", "recipe reorder preserves stable ID")
	panel._on_closed()
	check(panel._record.is_empty() and panel._recipe.item_count == 0 and panel._components.item_count == 0 and panel._status.text.contains("closed"), "disconnect clears counts and choices")
	check(view.describe({}, "craft.plate").contains("unavailable"), "disconnect clears remembered job state")
	panel.free()
	world.free()
	print("Workstation resource view failures: %d" % failures)
	quit(0 if failures == 0 else 1)
