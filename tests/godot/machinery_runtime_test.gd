extends SceneTree

var world: WorldRuntime
var runner: SimulationRunner
var production: ProductionSimulationSystem
var inventory: InventorySimulationSystem
var context: AuthenticatedCommandContext
var last: ServiceResult
var sequence: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


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
	# Bootstrap from the existing finite resource loop, with no matter grants.
	for batch in range(9):
		move([-3000, 0, -1000])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		step(120)
	# Network JSON coordinates arrive as integral floats; normalize before adopting.
	var generator: String = assemble("solar", [0.0, 0.0, 1000.0])
	var printer: String = assemble("printhead", [0, 0, 0])
	var socket: String = craft("socket")
	fit(printer, socket)
	var expander: String = craft("expander")
	command("machine_print", {"machine_id": printer, "kind": "frame"}, false)
	fit(printer, expander)
	var cable: String = craft("cable")
	command("machine_wire", {"machine_id": generator, "other_id": printer, "item_id": cable})
	command("load_cargo", {"carrier_id": "resource-canister-1", "material": "iron", "amount_milligrams": 300000})
	command("machine_insert", {"machine_id": printer, "item_id": "resource-canister-1", "socket_id": socket})
	step(90)
	var before: Dictionary = production.capture_snapshot().value
	command("machine_print", {"machine_id": printer, "kind": "power"})
	var printed: String = newest(before["machinery"]["parts"])
	check(production.capture_snapshot().value["cargo"]["resource-canister-1"]["iron"] == 200000, "printing consumes physical canister inputs")
	check(not production.capture_snapshot().value["machinery"]["mounts"].has(printed), "printed output is not automatically fitted")
	command("machine_unfit", {"machine_id": printer, "item_id": printed, "socket_id": ""})
	command("machine_recycle", {"item_id": printed})
	check(production.capture_snapshot().value["store"]["iron"] == before["store"]["iron"] + 100000, "recycling restores the exact shell materials")
	command("machine_remove", {"machine_id": printer, "item_id": "resource-canister-1", "socket_id": socket})
	command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "iron", "amount_milligrams": 200000})
	command("load_cargo", {"carrier_id": "resource-canister-1", "material": "iron", "amount_milligrams": 1000000})
	command("machine_insert", {"machine_id": printer, "item_id": "resource-canister-1", "socket_id": socket})
	step(90)
	var old_structures: Dictionary = production.capture_snapshot().value["structures"]
	command("machine_print", {"machine_id": printer, "kind": "equipment.canister"})
	var manufactured_canister: String = ""
	for id in production.capture_snapshot().value["structures"]:
		if not old_structures.has(id): manufactured_canister = id
	check(not manufactured_canister.is_empty(), "expanded powered printer creates an independent physical canister")
	command("machine_unfit", {"machine_id": printer, "item_id": manufactured_canister, "socket_id": ""})
	command("salvage_equipment", {"item_id": manufactured_canister})
	command("machine_remove", {"machine_id": printer, "item_id": "resource-canister-1", "socket_id": socket})
	command("load_cargo", {"carrier_id": "resource-canister-1", "material": "iron", "amount_milligrams": 200000})
	command("machine_insert", {"machine_id": printer, "item_id": "resource-canister-1", "socket_id": socket})
	var refinery: String = assemble("refinery", [1000, 0, 0])
	var input_socket: String = craft("socket")
	var output_socket: String = craft("socket")
	fit(refinery, input_socket)
	fit(refinery, output_socket)
	var second_wire: String = craft("cable")
	command("machine_wire", {"machine_id": generator, "other_id": refinery, "item_id": second_wire})
	command("machine_remove", {"machine_id": printer, "item_id": "resource-canister-1", "socket_id": socket})
	command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "iron", "amount_milligrams": 200000})
	# Obtain second canister from shared tray via native inventory authority.
	var pickup := InventoryDevelopmentCommand.new()
	sequence += 1
	pickup.command_id = StringName("machine-pickup-%d" % sequence)
	pickup.authenticated_context = context
	pickup.operation = "world"
	pickup.payload = {"operation": "pickup", "item_id": "resource-canister-2", "world_container_id": "world.tray-1", "destination_container_id": "body.human-2", "slot_id": "", "expected_revision": inventory.capture_snapshot().value["owner"]["state_revision"]}
	world.enqueue_command(pickup)
	step()
	check(last.is_success, "shared spare canister is collected")
	move([-3000, 0, -1000])
	command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
	move([0, 0, 0])
	command("machine_insert", {"machine_id": refinery, "item_id": "resource-canister-1", "socket_id": input_socket})
	command("machine_insert", {"machine_id": refinery, "item_id": "resource-canister-2", "socket_id": output_socket})
	command("machine_insert", {"machine_id": refinery, "item_id": "resource-canister-2", "socket_id": input_socket}, false)
	step(60)
	command("machine_run", {"machine_id": refinery, "recipe": "refine.iron"})
	step(30)
	command("machine_remove", {"machine_id": refinery, "item_id": "resource-canister-1", "socket_id": input_socket})
	var progress: int = production.capture_snapshot().value["machinery"]["jobs"][refinery]["progress"]
	step(60)
	check(production.capture_snapshot().value["machinery"]["jobs"][refinery]["progress"] == progress, "missing canister pauses without consuming feedstock")
	command("machine_insert", {"machine_id": refinery, "item_id": "resource-canister-1", "socket_id": input_socket})
	var snapshot: String = world.capture_world_snapshot_json().value
	var restored := WorldRuntime.new()
	restored.resource_carriers_enabled = true
	root.add_child(restored)
	var restore: ServiceResult = restored.restore_world_snapshot_json(snapshot)
	check(restore.is_success, "deployed machines, nested sockets, grid and running batch restore: " + restore.message)
	if restore.is_success:
		var restored_production: ProductionSimulationSystem = restored.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
		check(restored_production.capture_snapshot().value["machinery"]["jobs"][refinery]["paused"], "restart batches require explicit resume")
	restored.free()
	step(120)
	check(not production.capture_snapshot().value["machinery"]["jobs"].has(refinery), "powered refinery completes")
	var cargo: Dictionary = production.capture_snapshot().value["cargo"]
	check(int(cargo["resource-canister-1"]["iron"]) + int(cargo["resource-canister-2"]["iron"]) == 600000, "refinery outputs conserved iron into fitted canisters")
	command("machine_remove", {"machine_id": refinery, "item_id": "resource-canister-1", "socket_id": input_socket})
	command("machine_remove", {"machine_id": refinery, "item_id": "resource-canister-2", "socket_id": output_socket})
	for id in ["resource-canister-1", "resource-canister-2"]:
		for material in cargo[id]:
			if int(cargo[id][material]) > 0: command("unload_cargo", {"carrier_id": id, "material": material, "amount_milligrams": int(cargo[id][material])})
	var router: String = craft("frame")
	for kind in ["controller", "power", "router"]: fit(router, craft(kind))
	var extractor: String = craft("frame")
	for kind in ["controller", "power", "extractor"]: fit(extractor, craft(kind))
	var extraction_socket: String = craft("socket")
	fit(extractor, extraction_socket)
	command("machine_insert", {"machine_id": extractor, "item_id": "resource-canister-1", "socket_id": extraction_socket})
	command("machine_unwire", {"machine_id": generator, "item_id": cable})
	command("machine_unwire", {"machine_id": generator, "item_id": second_wire})
	command("machine_pack", {"machine_id": generator})
	move([-3000, 0, -1000])
	command("machine_deploy", {"machine_id": generator, "position": [-3000, 0, -1000], "mode": "surface"})
	move([-4500, 0, -1000])
	command("machine_deploy", {"machine_id": router, "position": [-4500, 0, -1000], "mode": "freeform"})
	command("machine_wire", {"machine_id": generator, "other_id": router, "item_id": cable})
	move([-6000, 0, -1000])
	command("machine_deploy", {"machine_id": extractor, "position": [-6000, 0, -1000], "mode": "surface"})
	command("machine_wire", {"machine_id": router, "other_id": extractor, "item_id": second_wire})
	command("machine_enable", {"machine_id": router, "enabled": false})
	command("machine_run", {"machine_id": extractor, "recipe": "extract.ice"})
	step(120)
	check(production.capture_snapshot().value["machinery"]["jobs"][extractor]["progress"] < 3, "isolated router blocks power after the small buffered charge")
	command("machine_enable", {"machine_id": router, "enabled": true})
	step(180)
	check(production.capture_snapshot().value["cargo"]["resource-canister-1"]["ice"] == 1000000 and production.capture_snapshot().value["deposits"]["deposit.ice"] == 4000000, "grid powered extractor fills socket canister from finite source")
	check(production.validate_snapshot_record(production.capture_snapshot().value, runner.tick_number).is_success, "complete loop conserves finite fixture mass")
	var damaged_owner: Dictionary = inventory.capture_snapshot().value["owner"]
	MachineryWorkshop.item(damaged_owner, extractor)["condition_permille"] = 0
	var workshop: Dictionary = production.capture_snapshot().value["machinery"]
	check(MachineryWorkshop.deployed(workshop, damaged_owner, extractor) and not MachineryWorkshop.operational(workshop, damaged_owner, extractor, "extractor"), "broken frames remain deployed and salvageable while their powered functions stop")
	var projection := RemoteProductionProjection.new()
	check(projection.accept_record(production.observation(context).value).is_success, "client accepts bounded machinery view")
	projection.free()
	var forged: Dictionary = JSON.parse_string(snapshot)
	forged["systems"]["production"]["machinery"]["parts"][generator]["kind"] = "solar"
	restored = WorldRuntime.new()
	restored.resource_carriers_enabled = true
	root.add_child(restored)
	check(not restored.restore_world_snapshot_json(JSON.stringify(forged)).is_success, "forged structural mass rejects")
	restored.free()
	var wrong_pose: Dictionary = JSON.parse_string(snapshot)
	wrong_pose["systems"]["production"]["machinery"]["placements"][generator]["position"][0] += 1
	restored = WorldRuntime.new()
	restored.resource_carriers_enabled = true
	root.add_child(restored)
	check(not restored.restore_world_snapshot_json(JSON.stringify(wrong_pose)).is_success, "mismatched physical world location rejects")
	restored.free()
	print("Machinery integration: %d failures" % failures)
	world.free()
	quit(1 if failures else 0)


func assemble(kind: String, position: Array) -> String:
	var frame: String = craft("frame")
	for module in ["controller", "power", kind]: fit(frame, craft(module))
	command("machine_deploy", {"machine_id": frame, "position": position, "mode": "surface"})
	return frame


func fit(frame: String, part: String) -> void:
	command("machine_fit", {"machine_id": frame, "item_id": part, "socket_id": ""})


func craft(kind: String) -> String:
	var before: Dictionary = production.capture_snapshot().value["machinery"]["parts"]
	command("machine_craft", {"kind": kind})
	return newest(before)


func newest(before: Dictionary) -> String:
	for id in production.capture_snapshot().value["machinery"]["parts"]:
		if not before.has(id): return id
	return ""


func command(operation: String, payload: Dictionary, success: bool = true) -> void:
	sequence += 1
	var action := ProductionDevelopmentCommand.new()
	action.command_id = StringName("machine-test-%d" % sequence)
	action.authenticated_context = context
	action.operation = operation
	action.payload = payload.duplicate(true)
	action.payload["expected_revision"] = production.capture_snapshot().value["state_revision"]
	world.enqueue_command(action)
	step()
	check(last.is_success == success, "%s: %s" % [operation, last.message])


func move(position: Array) -> void:
	sequence += 1
	var action := InventoryDevelopmentCommand.new()
	action.command_id = StringName("machine-move-%d" % sequence)
	action.authenticated_context = context
	action.operation = "move_to"
	action.payload = {"position_millimetres": position}
	world.enqueue_command(action)
	step()
	check(last.is_success, "move")


func step(count: int = 1) -> void:
	for _index in range(count): runner._physics_process(1.0 / 60.0)


func check(passed: bool, message: String) -> void:
	if passed: return
	failures += 1
	push_error(message)
