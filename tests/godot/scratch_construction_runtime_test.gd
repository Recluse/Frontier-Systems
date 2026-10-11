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
	for batch in range(5):
		move([-3000, 0, -1000])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		step(120)
	var tools: ToolSimulationSystem = world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID)
	# Old snapshots remain valid when the bindings catalog is extended additively.
	var legacy: Dictionary = JSON.parse_string(world.capture_world_snapshot_json().value)
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tools/inventory-bindings.v1.json"))["bindings"]
	legacy["systems"]["tools"]["bindings_fingerprint"] = JSON.stringify(original, "", true, true).sha256_text()
	var restored := WorldRuntime.new()
	restored.resource_carriers_enabled = true
	root.add_child(restored)
	check(restored.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "legacy tool binding fingerprint migrates")
	restored.free()
	var stored_part: String = craft("power")
	command("power", {"station": "printer", "enabled": false})
	for design in ["equipment.canister", "equipment.extractor", "equipment.crowbar", "equipment.shovel", "equipment.backpack", "equipment.pouch"]:
		var before: Dictionary = production.capture_snapshot().value
		command("machine_craft", {"kind": design})
		var id: String = ""
		for candidate in production.capture_snapshot().value["structures"]:
			if not before["structures"].has(candidate): id = candidate
		check(not id.is_empty(), "hand construction produces " + design)
		check(production.capture_snapshot().value["energy_joules"] == before["energy_joules"], "manual construction has no hidden printer energy dependency")
		var blueprint: Dictionary = production.machine_blueprint(design).value
		check(production.payload_mass(id) == blueprint["materials"]["iron"], "structural mass counted once")
		if design == "equipment.shovel": check(tools.capability(id, "tool.shovel").value, "built shovel exposes its component-backed excavation capability")
		if design == "equipment.crowbar": check(tools.capability(id, "tool.crowbar").value, "built crowbar has working replaceable components")
		var owner: Dictionary = inventory.capture_snapshot().value["owner"]
		var storage: String = MachineryWorkshop.container(owner, id)
		if design in ["equipment.backpack", "equipment.pouch"]:
			check(not storage.is_empty(), "built portable storage owns a real nested container")
			transfer(stored_part, storage)
			var occupied: Dictionary = production.capture_snapshot().value
			command("salvage_equipment", {"item_id": id}, false)
			check(production.capture_snapshot().value["store"] == occupied["store"], "occupied storage cannot be salvaged for duplicated material")
			transfer(stored_part, "body.human-2")
		var snapshot: ServiceResult = world.capture_world_snapshot_json()
		check(snapshot.is_success, "constructed storage and tool provenance validates")
		restored = WorldRuntime.new()
		restored.resource_carriers_enabled = true
		root.add_child(restored)
		check(restored.restore_world_snapshot_json(snapshot.value).is_success, "constructed " + design + " survives restart")
		restored.free()
		command("salvage_equipment", {"item_id": id})
		check(production.capture_snapshot().value["store"] == before["store"], "salvage returns exact hand-built materials")
		check(MachineryWorkshop.container(inventory.capture_snapshot().value["owner"], id).is_empty(), "salvage removes empty child storage")
	# Physical storage must also work through the deployed factory graph path.
	for batch in range(3):
		move([-3000, 0, -1000])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		step(120)
	var generator: String = assemble("solar", [-1100, 0, -1000])
	var printer: String = assemble("printhead", [900, 0, -1000])
	fit(printer, craft("expander"))
	var socket: String = craft("socket")
	fit(printer, socket)
	command("machine_wire", {"machine_id": generator, "other_id": printer, "item_id": craft("cable")})
	command("load_cargo", {"carrier_id": "resource-canister-1", "material": "iron", "amount_milligrams": 1500000})
	command("machine_insert", {"machine_id": printer, "item_id": "resource-canister-1", "socket_id": socket})
	step(120)
	for design in ["equipment.backpack", "equipment.pouch"]:
		var before: Dictionary = production.capture_snapshot().value["structures"]
		command("machine_print", {"machine_id": printer, "kind": design})
		for id in production.capture_snapshot().value["structures"]:
			if before.has(id): continue
			check(not MachineryWorkshop.container(inventory.capture_snapshot().value["owner"], id).is_empty(), "printed portable storage owns its real container")
			command("machine_unfit", {"machine_id": printer, "item_id": id, "socket_id": ""})
		step(60)
	check(world.capture_world_snapshot_json().is_success, "printed portable storage and grid persist together")
	var panel := MachineryPanel.new()
	root.add_child(panel)
	panel.configure(world)
	panel.observe({"production": production.observation(context).value, "inventory": inventory.own_inventory_observation(context).value, "position": [0, 0, 0]})
	var designs: Array = []
	for index in range(panel._kind.item_count): designs.append(panel._kind.get_item_metadata(index))
	for design in production.observation(context).value["blueprints"]: check(designs.has(design), "construction UI exposes trusted design " + design)
	panel.free()
	command("machine_craft", {"kind": "untrusted.item"}, false)
	print("Scratch construction integration: %d failures" % failures)
	finish()


func transfer(item: String, destination: String) -> void:
	sequence += 1
	var action := InventoryDevelopmentCommand.new()
	action.command_id = StringName("scratch-transfer-%d" % sequence)
	action.authenticated_context = context
	action.operation = "self"
	action.payload = {"operation": "move", "item_id": item, "source_container_id": MachineryWorkshop.item(inventory.capture_snapshot().value["owner"], item)["container_id"], "destination_container_id": destination, "slot_id": "", "expected_revision": inventory.own_inventory_observation(context, true).value["inventory_revision"]}
	world.enqueue_command(action)
	step()
	check(last.is_success, "native nested storage transfer: " + last.message)
