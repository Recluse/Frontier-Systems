extends "res://tests/godot/machinery_runtime_test.gd"

var panel: FirstPlayableTaskGuidePanel


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
	panel = FirstPlayableTaskGuidePanel.new()
	panel.custom_minimum_size.x = 420
	root.add_child(panel)
	check(panel._rows[0].text.contains("unavailable"), "fresh panel confirms nothing")
	check(panel.find_children("*", "Button", true, false).is_empty(), "guide has no action controls")
	for row in panel._rows:
		check(row.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and row.mouse_filter == Control.MOUSE_FILTER_IGNORE, "rows wrap without consuming native input")
	var initial: Dictionary = production.observation(context).value
	var before: String = world.capture_world_snapshot_json().value
	panel.observe({"production": initial})
	check(world.capture_world_snapshot_json().value == before, "presentation preserves canonical snapshot")
	check(panel._rows[3].text.contains("0 carried"), "fresh world has no physical plate")
	check(panel._rows[4].text.contains("0 currently observed"), "fresh world has no physical wall")
	for partial in [{}, {"store": {"plate": 1000000}}, {"components": ["invented"]}]:
		panel.observe({"production": partial})
		check(panel._rows[0].text.contains("unavailable") and not panel._rows[4].visible, "partial data clears all prior facts")
	var malformed: Dictionary = initial.duplicate(true)
	malformed["components"] = [42]
	panel.observe({"production": malformed})
	check(panel._rows[0].text.contains("unavailable"), "rejected projection cannot claim physical plate")
	var limited: Dictionary = initial.duplicate(true)
	limited["cargo"] = {}
	limited["deposits"]["deposit.iron"] = 0
	limited["energy_joules"] = 0
	limited["can_operate"] = true
	panel.observe({"production": limited})
	check(panel._rows[0].text.contains("Depleted") and panel._rows[1].text.contains("Collect a canister"), "depleted/no-carrier prerequisites are explicit")
	check(panel._rows[2].text.contains("Needs 1000 J"), "missing energy blocks recipe guidance")
	limited["energy_joules"] = 1000
	limited["powered"]["refinery"] = false
	panel.observe({"production": limited})
	check(panel._rows[2].text.contains("needs power"), "unpowered station blocks recipe guidance")
	move([-3000, 0, -1000])
	command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
	observe()
	check(panel._rows[1].text.contains("1.00 kg iron ore"), "actual extraction updates carried ore")
	move([0, 0, 0])
	command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
	command("process", {"recipe_id": "refine.iron"})
	observe()
	check(panel._rows[5].text.contains("Acceptance is not completion"), "accepted active job is not completion")
	command("power", {"station": "refinery", "enabled": false})
	observe()
	check(panel._rows[5].text.contains("paused without power"), "paused job remains incomplete")
	command("power", {"station": "refinery", "enabled": true})
	step(120)
	observe()
	check(panel._rows[2].text.contains("0.60 kg stored iron"), "completed batch shows actual output")
	move([-3000, 0, -1000])
	command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
	move([0, 0, 0])
	command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
	command("process", {"recipe_id": "refine.iron"})
	step(120)
	command("process", {"recipe_id": "craft.plate"})
	observe()
	check(panel._rows[3].text.contains("0 carried"), "accepted printing does not invent a carried plate")
	step(120)
	observe()
	check(panel._rows[3].text.contains("collect printed stock"), "stock still requires materialization")
	command("materialize_plate", {})
	observe()
	check(panel._rows[3].text.contains("1 carried"), "real materialization shows owned physical plate")
	var plate: String = production.observation(context).value["components"][0]
	command("wall_build", {"item_id": plate, "position": [0, 0, 0], "quarter_turn": 0}, false)
	observe()
	check(panel._rows[4].text.contains("0 currently observed"), "rejected wall placement confirms no wall")
	command("wall_build", {"item_id": plate, "position": [0, 0, -1000], "quarter_turn": 0})
	observe()
	check(panel._rows[3].text.contains("0 carried") and panel._rows[4].text.contains("1 currently observed"), "plate consumption and actual wall shown")
	var wall: String = production.observation(context).value["walls"].keys()[0]
	command("wall_remove", {"wall_id": wall})
	observe()
	check(panel._rows[3].text.contains("1 carried") and panel._rows[4].text.contains("0 currently observed"), "removal reverses current status")
	panel.observe({})
	check(panel._rows[0].text.contains("unavailable") and not panel._rows[3].visible, "disconnect clears cached facts")
	panel.free()
	print("Observation-only task guide: %d failures" % failures)
	finish()


func observe() -> void:
	var before: String = world.capture_world_snapshot_json().value
	panel.observe({"production": production.observation(context).value})
	check(world.capture_world_snapshot_json().value == before, "every guide update is canonical read-only")
