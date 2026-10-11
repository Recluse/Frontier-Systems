extends SceneTree

var _world: WorldRuntime
var _runner: SimulationRunner
var _terrain: TerrainSimulationSystem
var _inventory: InventorySimulationSystem
var _tools: ToolSimulationSystem
var _production: ProductionSimulationSystem
var _context: AuthenticatedCommandContext
var _last: ServiceResult
var _helper_id: int = 0
var _failures: int = 0
var _shovel: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	_bind(world)
	_context = _session("local-inventory-actor", ["inventory.operate", "terrain.operate"])
	_check(_world.start_simulation().is_success, "portable world starts")
	var fresh: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	var legacy: Dictionary = fresh.duplicate(true)
	legacy["systems"]["terrain"]["schema_version"] = 1
	legacy["systems"]["terrain"].erase("portable")
	var migrated := _clone(legacy)
	_check(migrated.get_simulation_system(&"terrain").capture_snapshot().value["schema_version"] == 3, "v1 terrain migrates without portable matter")
	migrated.free()
	# Fabricate an actual shovel through the existing finite production owner.
	for batch in range(3):
		_move([-3000, 0, -1000])
		_produce("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		_move([0, 0, 0])
		_produce("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		_produce("process", {"recipe_id": "refine.iron"})
		for tick in range(120): _step()
	_produce("fabricate_equipment", {"blueprint_id": "equipment.shovel"})
	_shovel = _production.capture_snapshot().value["structures"].keys()[0]
	_self("equip", _shovel, "body.human-2", "hand.left")
	_self("select_hand", "", "", "hand.left")
	var ready: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_send("excavate", _payload("terrain.dirt.source", 1000000), _next())
	_check(_last.is_success, "first finite excavation")
	_send("excavate", _payload("terrain.dirt.source", 1000000), _next())
	_check(_last.is_success, "second finite excavation")
	_deny("excavate", _payload("terrain.dirt.source", 1), "finite exhaustion rejects unchanged")
	var escrow: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	var first: Dictionary = _claim_payload("terrain-transfer-1")
	var original_context: AuthenticatedCommandContext = _context
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_claim_deny(first, 1, "wrong claimant cannot materialize")
	_context = original_context
	var no_grant := TerrainMaterializeCommand.new()
	no_grant.command_id = &"terrain-materialize-1"
	no_grant.request_number = 1
	no_grant.payload = first
	no_grant.authenticated_context = _session("local-inventory-actor", ["inventory.operate"])
	_check(_world.enqueue_command(no_grant).is_success, "permission attempt queues for authoritative validation")
	_step()
	_check(not _last.is_success, "missing terrain grant rejects at command validation")
	_claim_deny(first, 2, "skipped claim ordinal rejects")
	var invalid: Dictionary = first.duplicate(true)
	invalid["mass_milligrams"] = 1
	_claim_deny(invalid, 1, "clients cannot supply payload matter")
	invalid = first.duplicate(true)
	invalid["expected_inventory_revision"] += 1
	_claim_deny(invalid, 1, "stale inventory rejects")
	# Trusted root ceilings are independent host configuration. Reject before adoption.
	var own: Dictionary = _inventory.own_inventory_observation(_context, true).value
	for limit in ["mass", "items", "volume"]:
		var full: Dictionary = escrow.duplicate(true)
		for container in full["systems"]["inventory"]["owner"]["ledger"]["containers"]:
			if container["container_id"] != "body.human-2": continue
			if limit == "mass":
				# Independent intrinsic inventory fixture mass fills the pinned 40 kg root.
				# Terrain/Production origin budgets and payload records are untouched.
				var added_mass: int = 0
				while int(own["mass_milligrams"]) + added_mass <= 39000000:
					full["systems"]["inventory"]["owner"]["ledger"]["items"].append({"item_id": "capacity-canister-%d" % added_mass, "definition_id": "item.resource-canister.prototype", "definition_revision": 1, "condition_permille": 1000, "container_id": "body.human-2"})
					added_mass += 1000000
				container["capacity"]["max_items"] = 512
				container["capacity"]["max_volume_millilitres"] = 1000000
			if limit == "items":
				var count: int = 0
				for item in full["systems"]["inventory"]["owner"]["ledger"]["items"]:
					if item["container_id"] == "body.human-2": count += 1
				container["capacity"]["max_items"] = count
			if limit == "volume":
				for observed in own["container_records"]:
					if observed["container_id"] == "body.human-2": container["capacity"]["max_volume_millilitres"] = observed["load"]["volume_millilitres"] + 999
		_restart(full)
		_claim_deny(first, 1, "full %s capacity preserves escrow and inventory" % limit)
	_restart(escrow)
	var competing: Array = []
	var collect_competing := func(command: SimulationCommand, result: ServiceResult) -> void:
		if command is TerrainMaterializeCommand: competing.append(result)
	_world.command_completed.connect(collect_competing)
	_queue_claim(first, 1)
	_queue_claim(_claim_payload("terrain-transfer-2"), 2)
	_step()
	_world.command_completed.disconnect(collect_competing)
	_check(competing.size() == 2 and competing[0].is_success and not competing[1].is_success and _state()["claims"].has("terrain-transfer-2"), "competing distinct intents cannot both use the earlier inventory revision")
	_restart(escrow)
	var mass_before: int = _inventory.own_inventory_observation(_context, true).value["mass_milligrams"]
	_claim(first, 1)
	_check(_last.is_success, "whole own escrow materializes")
	var receipt: Dictionary = _last.value.duplicate(true)
	_check(receipt["mass_milligrams"] == 1000000 and receipt["parcels"] == {"terrain.dirt.source.generation": 1000000}, "exact material and origin parcels retained")
	_check(_inventory.own_inventory_observation(_context, true).value["mass_milligrams"] == mass_before + 1000000, "payload counted exactly once with no shell mass")
	_check(not _terrain.observation(_context).value["transfers"].has("terrain-transfer-1"), "portable payload is no longer escrow")
	var before: Dictionary = _canonical()
	_claim(first, 1)
	_check(_last.is_success and _last.value == receipt and _canonical() == before, "exact retry is read-only")
	_claim_deny(_claim_payload("terrain-transfer-2"), 1, "changed retained ordinal rejects")
	_claim_deny(first, 2, "new ordinal cannot rematerialize the same transfer")
	_deny("fill", _payload("terrain.dirt.fill", 1, "terrain-transfer-1"), "materialized payload cannot be terrain fill escrow")
	# Two competing next claims in the same authoritative tick.
	var second: Dictionary = _claim_payload("terrain-transfer-2")
	var outcomes: Array = []
	var collect := func(command: SimulationCommand, result: ServiceResult) -> void:
		if command is TerrainMaterializeCommand: outcomes.append(result)
	_world.command_completed.connect(collect)
	_queue_claim(second, 2)
	_queue_claim(second, 2)
	_step()
	_world.command_completed.disconnect(collect)
	_check(outcomes.size() == 2 and outcomes[0].is_success and outcomes[1].is_success and outcomes[0].value == outcomes[1].value, "competing exact intents settle once then reconcile")
	_check(_state()["portable"].size() == 2 and _state()["claims"].is_empty() and _mass() == 2000000, "cell plus escrow plus portable mass equals commissioning")
	# Existing inventory APIs move the same physical item, including to another principal.
	_self("equip", "terrain-item-1", "body.human-2", "hand.right")
	_self("unequip", "", "", "hand.right")
	_check(_inventory.own_inventory_observation(_context).value["items"].any(func(item: Dictionary) -> bool: return item["item_id"] == "terrain-item-1" and item["container_id"] == "storage.backpack-2"), "parcel stows in existing portable storage")
	_world_move("drop", "terrain-item-1", "", "")
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_world_move("pickup", "terrain-item-1", "body.human-1", "hand.right")
	_check(_inventory.own_inventory_observation(_context, true).value["item_details"].any(func(item: Dictionary) -> bool: return item["item"]["item_id"] == "terrain-item-1" and item["mass_milligrams"] == 1000000), "physical transfer retains canonical payload mass")
	_context = original_context
	before = _canonical()
	_claim(first, 1)
	_check(_last.is_success and _last.value == receipt and _canonical() == before, "original claimant can reconcile after physical transfer")
	# Production prospective validation must include the other owner's live payload.
	_check(_inventory.validate_payload_masses(ProductionSimulationSystem.payload_masses(_production.capture_snapshot().value)).is_success, "prospective production view composes terrain payloads")
	var tight: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	var current_mass: int = _inventory.own_inventory_observation(_context, true).value["mass_milligrams"]
	var padding: int = 0
	while current_mass + padding <= 39000000:
		tight["systems"]["inventory"]["owner"]["ledger"]["items"].append({"item_id": "prospective-canister-%d" % padding, "definition_id": "item.resource-canister.prototype", "definition_revision": 1, "condition_permille": 1000, "container_id": "body.human-2"})
		padding += 1000000
	for container in tight["systems"]["inventory"]["owner"]["ledger"]["containers"]:
		if container["container_id"] == "body.human-2":
			container["capacity"]["max_items"] = 512
			container["capacity"]["max_volume_millilitres"] = 1000000
	var normal: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(tight)
	var prospective: Dictionary = ProductionSimulationSystem.payload_masses(_production.capture_snapshot().value)
	prospective["prospective-plate"] = 1000000
	before = _canonical()
	var factory: ServiceResult = _inventory.prepare_plate_change(_context, "prospective-factory", "prospective-plate", true, prospective)
	_check(not factory.is_success and _canonical() == before, "production factory cannot omit existing portable terrain mass to fit a full body")
	_restart(normal)
	var snapshot: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(snapshot)
	var recovered: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_check(JSON.parse_string(JSON.stringify(recovered)) == JSON.parse_string(JSON.stringify(snapshot)), "exact full JSON values and provenance restore")
	var recovered_json: String = _world.capture_world_snapshot_json().value
	_restart(recovered)
	_check(_world.capture_world_snapshot_json().value == recovered_json, "normalized JSON checkpoint is byte-exact across another restart")
	before = _canonical()
	_claim(first, 1)
	_check(_last.is_success and _last.value == receipt and _canonical() == before, "restart exact reconciliation preserves provenance and physical parentage")
	for corruption in ["missing-item", "orphan", "double-claim", "item-id", "ordinal", "revision", "mass", "parcel", "ordinal-order", "factory-receipt"]:
		var bad: Dictionary = snapshot.duplicate(true)
		var terrain: Dictionary = bad["systems"]["terrain"]
		var items: Array = bad["systems"]["inventory"]["owner"]["ledger"]["items"]
		match corruption:
			"missing-item":
				for item in items.duplicate(true):
					if item["item_id"] == "terrain-item-1": items.erase(item)
			"orphan": terrain["portable"].erase("terrain-transfer-1")
			"double-claim": terrain["claims"]["terrain-transfer-1"] = "local-inventory-actor"
			"item-id": terrain["portable"]["terrain-transfer-1"]["item_id"] = "foreign-item"
			"ordinal": terrain["portable"]["terrain-transfer-2"]["request_number"] = 1
			"revision": terrain["portable"]["terrain-transfer-1"]["expected_inventory_revision"] = bad["systems"]["inventory"]["owner"]["state_revision"]
			"mass": terrain["owner"]["transfers"]["terrain-transfer-1"]["mass_milligrams"] += 1
			"ordinal-order":
				var first_revision: Variant = terrain["portable"]["terrain-transfer-1"]["expected_inventory_revision"]
				terrain["portable"]["terrain-transfer-1"]["expected_inventory_revision"] = terrain["portable"]["terrain-transfer-2"]["expected_inventory_revision"]
				terrain["portable"]["terrain-transfer-2"]["expected_inventory_revision"] = first_revision
			"factory-receipt":
				for receipt_record in bad["systems"]["inventory"]["owner"]["receipts"]:
					if receipt_record["request_id"] == "terrain-factory-terrain-transfer-1": receipt_record["fingerprint"] = "0".repeat(64)
			"parcel": terrain["owner"]["transfers"]["terrain-transfer-1"]["parcels"]["terrain.dirt.source.generation"] += 1
		_reject_snapshot(bad, "atomic corruption denial: " + corruption)
	var exported := FileAccess.open("res://var/terrain-portable-fixture.json", FileAccess.WRITE)
	exported.store_string(JSON.stringify(snapshot))
	exported.close()
	# Lifetime receipts remain bounded even after domain excavation receipts expire.
	for container in ready["systems"]["inventory"]["owner"]["ledger"]["containers"]:
		if container["container_id"] == "body.human-2":
			container["capacity"]["max_items"] = 512
			container["capacity"]["max_volume_millilitres"] = 1000000
	_restart(ready)
	for index in range(TerrainSimulationSystem.MAX_PORTABLE):
		_send("excavate", _payload("terrain.dirt.source", 1), _next())
		_check(_last.is_success, "bounded small excavation")
		_claim(_claim_payload("terrain-transfer-%d" % (index + 1)), index + 1)
		_check(_last.is_success, "bounded portable claim")
	var saturated: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(saturated)
	before = _canonical()
	_claim({"transfer_id": "terrain-transfer-1", "expected_inventory_revision": saturated["systems"]["terrain"]["portable"]["terrain-transfer-1"]["expected_inventory_revision"]}, 1)
	_check(_last.is_success and _canonical() == before, "old claim retry survives excavation receipt eviction and JSON restart")
	_send("excavate", _payload("terrain.dirt.source", 1), _next())
	_claim_deny(_claim_payload("terrain-transfer-129"), 129, "lifetime collection limit rejects without mutation")
	_check(_mass() == 2000000, "bounded saturation conserves all matter")
	var return_command: SimulationCommand = TerrainTransportCodec.command(1, "return", {"item_id": "terrain-item-1", "expected_inventory_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]})
	return_command.authenticated_context = _context
	_check(_world.enqueue_command(return_command).is_success, "saturated lifetime parcel can queue return")
	_step()
	_check(_last.is_success and _state()["portable"].size() == 128 and _terrain.portable_payload_masses().size() == 127 and _mass() == 2000000, "return preserves full lifetime slots, escrow and exact mass")
	var retired: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(retired)
	_claim_deny(_claim_payload("terrain-transfer-129"), 129, "return never recycles a lifetime claim slot")
	_world.free()
	if _failures == 0: print("Terrain portable: finite source, claimant/capacity gates, competing/repeated intents, conserved origin parcels, physical transfers, exact atomic JSON recovery and lifetime limits passed.")
	quit(0 if _failures == 0 else 1)


func _claim_payload(transfer: String) -> Dictionary:
	return {"transfer_id": transfer, "expected_inventory_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]}


func _queue_claim(payload: Dictionary, number: int) -> void:
	var command := TerrainMaterializeCommand.new()
	command.command_id = StringName("terrain-materialize-%d" % number)
	command.request_number = number
	command.payload = payload.duplicate(true)
	command.authenticated_context = _context
	_check(_world.enqueue_command(command).is_success, "portable claim queues")


func _claim(payload: Dictionary, number: int) -> void:
	_queue_claim(payload, number)
	_step()


func _claim_deny(payload: Dictionary, number: int, message: String) -> void:
	var before: Dictionary = _canonical()
	_claim(payload, number)
	_check(not _last.is_success and _canonical() == before, message)


func _world_move(operation: String, item: String, destination: String, slot: String) -> void:
	_inventory_command("world", {"operation": operation, "item_id": item, "world_container_id": "world.tray-1", "destination_container_id": destination, "slot_id": slot, "expected_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]})


func _bind(world: WorldRuntime) -> void:
	_world = world
	_runner = world.get_node("SimulationRunner")
	_runner.set_physics_process(false)
	_terrain = world.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID)
	_inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	_tools = world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID)
	_production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _last = result)


func _session(principal: String, grants: Array) -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(StringName(principal), &"terrain-test-session", _world.world_id, _world.region_id, PackedStringArray(grants))


func _clone(record: Dictionary) -> WorldRuntime:
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	var restored: ServiceResult = clone.restore_world_snapshot_json(JSON.stringify(record))
	_check(restored.is_success, "JSON clone restores: " + restored.message)
	return clone


func _restart(record: Dictionary) -> void:
	var clone := _clone(record)
	_world.free()
	_bind(clone)
	_check(_world.start_simulation().is_success, "restored world starts")


func _reject_snapshot(record: Dictionary, message: String) -> void:
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	var before: Dictionary = clone.capture_world_snapshot().value.to_dictionary()
	_check(not clone.restore_world_snapshot_json(JSON.stringify(record)).is_success and clone.capture_world_snapshot().value.to_dictionary() == before, message)
	clone.free()


func _state() -> Dictionary:
	return _terrain.capture_snapshot().value


func _canonical() -> Dictionary:
	var terrain: Dictionary = _state()
	var inventory: Dictionary = _inventory.capture_snapshot().value
	terrain.erase("last_tick")
	inventory.erase("last_tick")
	return {"terrain": terrain, "inventory": inventory}


func _mass() -> int:
	var owner: Dictionary = _state()["owner"]
	var mass: int = 0
	for cell in owner["cells"].values(): mass += int(cell["state"]["mass_milligrams"])
	for transfer in owner["transfers"].values(): mass += int(transfer["mass_milligrams"])
	return mass


func _next() -> int:
	return int(_state()["principals"].get(String(_context.principal_id), 0)) + 1


func _payload(cell: String, amount: int, transfer: String = "") -> Dictionary:
	return {"cell_id": cell, "amount_milligrams": amount, "transfer_id": transfer, "expected_cell_revision": _state()["owner"]["cells"][cell]["state"]["state_revision"],
		"expected_inventory_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"], "expected_tool_revision": _tools.capture_snapshot().value["ledger"]["state_revision"]}


func _deny(operation: String, payload: Dictionary, message: String) -> void:
	var before: Dictionary = _canonical()
	_send(operation, payload, _next())
	_check(not _last.is_success and _canonical() == before, message)


func _send(operation: String, payload: Dictionary, number: int) -> void:
	var command := TerrainCommand.new()
	command.command_id = StringName("terrain-client-%d" % number)
	command.request_number = number
	command.operation = operation
	command.payload = payload.duplicate(true)
	command.authenticated_context = _context
	_check(_world.enqueue_command(command).is_success, "terrain ingress queues")
	_step()


func _produce(operation: String, payload: Dictionary) -> void:
	_helper_id += 1
	var command := ProductionDevelopmentCommand.new()
	command.command_id = StringName("terrain-setup-%d" % _helper_id)
	command.authenticated_context = _context
	command.operation = operation
	payload["expected_revision"] = _production.capture_snapshot().value["state_revision"]
	command.payload = payload
	_check(_world.enqueue_command(command).is_success, "production setup queues")
	_step()
	_check(_last.is_success, "finite shovel setup: " + _last.message)


func _move(position: Array) -> void:
	_inventory_command("move_to", {"position_millimetres": position})


func _self(operation: String, item: String, source: String, slot: String) -> void:
	_inventory_command("self", {"operation": operation, "item_id": item, "source_container_id": source, "destination_container_id": "storage.backpack-2" if operation == "unequip" else "", "slot_id": slot, "expected_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]})


func _inventory_command(operation: String, payload: Dictionary) -> void:
	_helper_id += 1
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName("terrain-inventory-%d" % _helper_id)
	command.authenticated_context = _context
	command.operation = operation
	command.payload = payload
	_check(_world.enqueue_command(command).is_success, "inventory setup queues")
	_step()
	_check(_last.is_success, "inventory setup: " + _last.message)


func _step() -> void:
	_runner._physics_process(1.0 / 60.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
