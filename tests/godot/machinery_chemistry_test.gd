extends "res://tests/godot/machinery_runtime_test.gd"


func run() -> void:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: last = result)
	check(world.start_simulation().is_success, "chemistry world starts")
	runner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	for batch in range(6):
		move([-3000, 0, -1000])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		step(120)
	command("fabricate_equipment", {"blueprint_id": "equipment.canister"})
	var third: String = production.capture_snapshot().value["structures"].keys()[0]
	var pickup := InventoryDevelopmentCommand.new()
	pickup.command_id = &"chemistry-spare-canister"
	pickup.authenticated_context = context
	pickup.operation = "world"
	pickup.payload = {"operation": "pickup", "item_id": "resource-canister-2", "world_container_id": "world.tray-1", "destination_container_id": "body.human-2", "slot_id": "", "expected_revision": inventory.capture_snapshot().value["owner"]["state_revision"]}
	world.enqueue_command(pickup)
	step()
	check(last.is_success, "collect spare canister")
	move([-6000, 0, -1000])
	command("extract", {"deposit_id": "deposit.ice", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
	move([0, 0, 0])
	command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ice", "amount_milligrams": 1000000})
	command("process", {"recipe_id": "refine.ice"})
	step(60)
	command("load_cargo", {"carrier_id": "resource-canister-1", "material": "water", "amount_milligrams": 1000000})
	var generator: String = assemble("solar", [-1100, 0, -1000])
	var chemical: String = assemble("refinery", [900, 0, -1000])
	for id in ["resource-canister-1", "resource-canister-2", third]:
		var socket: String = craft("socket")
		fit(chemical, socket)
		command("machine_insert", {"machine_id": chemical, "item_id": id, "socket_id": socket})
	command("machine_wire", {"machine_id": generator, "other_id": chemical, "item_id": craft("cable")})
	command("machine_run", {"machine_id": chemical, "recipe": "chemical.electrolysis"})
	step(180)
	check(production.capture_snapshot().value["machinery"]["jobs"][chemical]["progress"] == 0, "oversized bulk gas outputs pause without unsafe pressure or resource loss")
	command("machine_cancel", {"machine_id": chemical})
	command("machine_run", {"machine_id": chemical, "recipe": "chemical.electrolysis.micro"})
	step(90)
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	check(clone.restore_world_snapshot_json(world.capture_world_snapshot_json().value).is_success, "portable chemistry progress restores with unchanged recipe semantics")
	clone.free()
	step(100)
	var cargo: Dictionary = production.capture_snapshot().value["cargo"]
	var water: int = 0
	var hydrogen: int = 0
	var oxygen: int = 0
	for stock in cargo.values():
		water += int(stock["water"])
		hydrogen += int(stock["hydrogen"])
		oxygen += int(stock["oxygen"])
	check(water == 990000 and hydrogen == 1110 and oxygen == 8890, "10 g feedstock becomes exact conserved hydrogen/oxygen in separate carriers")
	check(world.capture_world_snapshot_json().is_success, "complete chemistry has valid pressure, material and inventory associations")
	print("Portable machinery chemistry: %d failures" % failures)
	finish()
