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
	for batch in range(4):
		move([-3000, 0, -1000])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		step(120)
	for index in range(2):
		command("process", {"recipe_id": "craft.plate"})
		step(120)
		command("materialize_plate", {})
	var plates: Array = production.observation(context).value["components"]
	var intent: Dictionary = {"item_id": plates[0], "position": [0, 0, -1000], "quarter_turn": 0}
	command("wall_build", {"item_id": plates[0], "position": [0, 0, 1000], "quarter_turn": 0}, false)
	command("wall_build", {"item_id": plates[0], "position": [0, 0, 0], "quarter_turn": 0}, false)
	command("wall_build", {"item_id": plates[0], "position": [0, 100, -1000], "quarter_turn": 0}, false)
	command("wall_build", {"item_id": plates[0], "position": [1, 0, -1000], "quarter_turn": 0}, false)
	command("wall_build", {"item_id": plates[0], "position": [5000, 0, 0], "quarter_turn": 0}, false)
	command("wall_build", {"item_id": plates[0], "position": [0, 0, -1000], "quarter_turn": 2}, false)
	command("wall_build", {"item_id": "resource-canister-1", "position": [0, 0, -1000], "quarter_turn": 0}, false)
	command("wall_build", {"item_id": plates[0], "position": [0, 0, -1000], "quarter_turn": 0, "mass": 1}, false)
	var before: Dictionary = production.capture_snapshot().value
	var other := AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	var own_context: AuthenticatedCommandContext = context
	context = other
	command("wall_build", intent, false)
	context = own_context
	check(production.capture_snapshot().value["cargo"] == before["cargo"], "failed unowned plate construction is atomic")
	command("wall_build", intent)
	var wall_id: String = production.capture_snapshot().value["walls"].keys()[0]
	check(not production.capture_snapshot().value["cargo"].has(plates[0]) and not production.observation(context).value["components"].has(plates[0]), "wall consumes physical plate and payload exactly once")
	check(production.capture_snapshot().value["wall_mass_milligrams"] == 0, "spatial wall is distinct from legacy aggregate mass")
	# A retained retry acknowledges the same result without another consumed plate.
	intent["expected_revision"] = before["state_revision"]
	var retry: ServiceResult = production.apply_local(context, "machine-test-%d" % sequence, "wall_build", intent, runner.tick_number + 1)
	check(retry.is_success and production.capture_snapshot().value["walls"].size() == 1, "wall construction retained retry is idempotent")
	command("wall_build", {"item_id": plates[1], "position": [0, 0, -1000], "quarter_turn": 1}, false)
	check(production.capture_snapshot().value["cargo"].has(plates[1]), "overlap rejection preserves second plate")
	var movement_before: Dictionary = inventory.capture_snapshot().value
	sequence += 1
	var movement := InventoryDevelopmentCommand.new()
	movement.command_id = StringName("wall-motion-%d" % sequence)
	movement.authenticated_context = context
	movement.operation = "move_to"
	movement.payload = {"position_millimetres": [0, 0, -2000]}
	world.enqueue_command(movement)
	step()
	check(not last.is_success and inventory.capture_snapshot().value["bodies"] == movement_before["bodies"], "server rejects tunnelling without changing body epochs")
	move([1000, 0, 0])
	command("wall_build", {"item_id": plates[1], "position": [1000, 0, -1000], "quarter_turn": 1})
	check(production.profiling_counters()["spatial_walls"] == 2, "bounded profiling counts canonical panels")
	check(SpatialWallConstruction.motion_clear(production.capture_snapshot().value["walls"], [0, 0, 0], [-2000, 0, 0]), "parallel motion clear of wall succeeds")
	check(not SpatialWallConstruction.motion_clear(production.capture_snapshot().value["walls"], [0, 0, -1000], [2000, 0, -1000]), "rotated wall blocks swept bodies")
	check(not SpatialWallConstruction.motion_clear(production.capture_snapshot().value["walls"], [0, 950, 0], [0, 950, -2000]), "network capsule-centre poses cannot tunnel through panels")
	check(SpatialWallConstruction.motion_clear(production.capture_snapshot().value["walls"], [0, 3000, 0], [0, 3000, -2000]), "body entirely above wall can pass without false foot-coordinate collision")
	var snapshot: ServiceResult = world.capture_world_snapshot_json()
	check(snapshot.is_success, "spatial wall material validates in world checkpoint")
	var restored := WorldRuntime.new()
	restored.resource_carriers_enabled = true
	root.add_child(restored)
	check(restored.restore_world_snapshot_json(snapshot.value).is_success, "wall pose and conserved mass survive JSON restart")
	var restored_production: ProductionSimulationSystem = restored.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	check(restored_production.capture_snapshot().value["walls"] == production.capture_snapshot().value["walls"], "restart retains stable wall identities and normalized positions")
	restored.free()
	var projection := RemoteProductionProjection.new()
	check(projection.accept_record(production.observation(context).value).is_success, "client validates v7 spatial wall observation")
	var malformed: Dictionary = production.observation(context).value
	malformed["walls"][wall_id]["quarter_turn"] = 2
	check(not projection.accept_record(malformed).is_success, "client rejects malformed wall pose")
	projection.free()
	var preview := ProceduralProductionPreview.new()
	root.add_child(preview)
	preview.observe(production.observation(context).value)
	check(preview._spatial_walls.size() == 2 and preview._spatial_walls[wall_id] is StaticBody3D, "two real static wall colliders project canonical state")
	var old_body: Node = preview._spatial_walls[wall_id]
	preview.observe(production.observation(context).value)
	check(preview._spatial_walls[wall_id] == old_body, "unchanged observations reuse static physics")
	var panel := MachineryPanel.new()
	root.add_child(panel)
	panel.configure(world)
	panel.observe({"production": production.observation(context).value, "inventory": inventory.own_inventory_observation(context).value, "position": [1000, 0, 0]})
	panel.select_wall(wall_id)
	check(panel._selected(panel._wall) == wall_id, "construction selector targets stable clicked wall identity")
	panel.free()
	# Shared floor structures can be dismantled by either reachable conscious crew.
	context = other
	command("wall_remove", {"wall_id": wall_id})
	check(production.observation(context).value["components"].size() == 1, "other crew receives recovered plate in their own inventory")
	preview.observe(production.observation(context).value)
	check(preview._spatial_walls.size() == 1, "removed wall collider retires")
	preview.free()
	command("recycle_component", {"item_id": production.observation(context).value["components"][0]})
	var frame: String = craft("frame")
	command("machine_deploy", {"machine_id": frame, "position": [1000, 0, -1000], "mode": "surface"}, false)
	check(not production.capture_snapshot().value["machinery"]["placements"].has(frame), "machine cannot deploy through existing wall")
	command("machine_deploy", {"machine_id": frame, "position": [2000, 0, -200], "mode": "surface"})
	context = own_context
	var second_wall: String = production.capture_snapshot().value["walls"].keys()[0]
	command("wall_remove", {"wall_id": second_wall})
	command("wall_remove", {"wall_id": second_wall}, false)
	command("wall_build", {"item_id": production.observation(context).value["components"][0], "position": [2000, 0, -600], "quarter_turn": 0}, false)
	check(production.observation(context).value["components"].size() == 1, "wall cannot build through machine and failed construction preserves plate")
	command("recycle_component", {"item_id": production.observation(context).value["components"][0]})
	context = other
	command("machine_pack", {"machine_id": frame})
	command("machine_recycle", {"item_id": frame})
	context = own_context
	check(production.capture_snapshot().value["store"]["iron"] == 2400000 and production.capture_snapshot().value["walls"].is_empty(), "all wall matter returns to exact refined stock")
	var legacy: Dictionary = JSON.parse_string(world.capture_world_snapshot_json().value)
	legacy["systems"]["production"]["schema_version"] = 6
	legacy["systems"]["production"].erase("walls")
	restored = WorldRuntime.new()
	restored.resource_carriers_enabled = true
	root.add_child(restored)
	check(restored.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "v6 checkpoint migrates without new panels or matter")
	check((restored.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem).capture_snapshot().value["walls"].is_empty(), "migration grants no spatial construction")
	restored.free()
	var forged: Dictionary = JSON.parse_string(snapshot.value)
	forged["systems"]["production"]["walls"][wall_id]["position"][0] = 1
	restored = WorldRuntime.new()
	restored.resource_carriers_enabled = true
	root.add_child(restored)
	check(not restored.restore_world_snapshot_json(JSON.stringify(forged)).is_success, "forged non-grid wall checkpoint rejects")
	restored.free()
	forged = JSON.parse_string(snapshot.value)
	forged["systems"]["production"]["walls"].erase(wall_id)
	check(not production.validate_snapshot_record(forged["systems"]["production"], forged["tick_number"]).is_success, "missing wall matter rejects")
	print("Spatial wall integration: %d failures" % failures)
	finish()
