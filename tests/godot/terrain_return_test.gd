extends "res://tests/godot/terrain_portable_test.gd"


func _run() -> void:
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	_bind(world)
	_context = _session("local-inventory-actor", ["inventory.operate", "terrain.operate"])
	var original_context: AuthenticatedCommandContext = _context
	_check(_world.start_simulation().is_success, "return world starts")
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
	_send("excavate", _payload("terrain.dirt.source", 777777), _next())
	_check(_last.is_success, "finite odd integer excavation")
	var preclaim: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	var claim_payload: Dictionary = _claim_payload("terrain-transfer-1")
	_claim(claim_payload, 1)
	_check(_last.is_success, "whole parcel materializes")
	var claim_receipt: Dictionary = _last.value.duplicate(true)
	var active: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(active)
	var legacy: Dictionary = active.duplicate(true)
	legacy["systems"]["terrain"]["schema_version"] = 2
	for entry in legacy["systems"]["terrain"]["portable"].values():
		entry.erase("receipt")
		entry.erase("returned")
	_restart(legacy)
	_claim(claim_payload, 1)
	_check(_last.is_success and _last.value == claim_receipt, "v2 active parcel migrates with unchanged original claim retry")
	var valid: Dictionary = {"item_id": "terrain-item-1", "expected_inventory_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]}
	for field in ["mass_milligrams", "principal_id", "transfer_id", "material_id", "parcels", "destination_container_id"]:
		var forged: Dictionary = valid.duplicate(true)
		forged[field] = "forged"
		_return_deny(forged, 1, "forged return rejects " + field)
	var stale: Dictionary = valid.duplicate(true)
	stale["expected_inventory_revision"] += 1
	_return_deny(stale, 1, "stale return rejects without mutation")
	_return_deny({"item_id": "terrain-item-999", "expected_inventory_revision": valid["expected_inventory_revision"]}, 1, "absent parcel cannot be returned")
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_return_deny(valid, 1, "foreign physical holder rejects")
	_context = original_context
	_world_move("drop", "terrain-item-1", "", "")
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_world_move("pickup", "terrain-item-1", "body.human-1", "")
	_check(_terrain.observation(_context).value["returnable_parcels"].has("terrain-item-1"), "new authenticated holder sees its legitimate returnable parcel")
	var transferred: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(transferred)
	valid = {"item_id": "terrain-item-1", "expected_inventory_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]}
	var real_inventory: InventorySimulationSystem = _inventory
	var failing := FailedAdoption.new()
	failing.delegate = real_inventory
	_terrain._inventory = failing
	_return_deny(valid, 1, "injected adoption failure restores association and payload projection before returning")
	_check(failing.attempted, "fault reaches inventory adoption after successful preparation")
	_terrain._inventory = real_inventory
	failing.free()
	var loaded: int = _inventory.own_inventory_observation(_context, true).value["mass_milligrams"]
	_return(valid, 1)
	_check(_last.is_success, "new holder returns whole legitimate parcel: " + _last.message)
	if not _last.is_success: quit(1); return
	var returned_receipt: Dictionary = _last.value.duplicate(true)
	_check(_state()["claims"]["terrain-transfer-1"] == String(_context.principal_id) and _state()["portable"].size() == 1 and _terrain.portable_payload_masses().is_empty() and _mass() == 2000000, "holder escrow, permanent slot and zero portable mass settle with exact conservation")
	_check(_inventory.own_inventory_observation(_context, true).value["mass_milligrams"] == loaded - 777777, "whole payload leaves inventory exactly once")
	var returned: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(returned)
	var before: Dictionary = _canonical()
	_return(valid, 1)
	_check(_last.is_success and _last.value == returned_receipt and _canonical() == before, "return retry after restart is read-only")
	_return_deny(stale, 1, "changed retained return intent rejects")
	_return_deny(valid, 2, "new ordinal never resurrects a returned item")
	_claim_deny(_claim_payload("terrain-transfer-1"), 1, "returned holder cannot rematerialize fill-only escrow")
	_context = original_context
	before = _canonical()
	_claim(claim_payload, 1)
	_check(_last.is_success and _last.value == claim_receipt and _canonical() == before, "original claim retry survives cross-principal return unchanged")
	# Pass the actual shovel through normal inventory; the new holder can fill.
	_world_move("drop", _shovel, "", "")
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_world_move("pickup", _shovel, "body.human-1", "hand.left")
	_self("select_hand", "", "", "hand.left")
	_send("fill", _payload("terrain.dirt.fill", 123456, "terrain-transfer-1"), _next())
	_check(_last.is_success and _mass() == 2000000, "holder partially fills with same provenance")
	var partial: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(partial)
	_check(_state()["owner"]["transfers"]["terrain-transfer-1"]["mass_milligrams"] == 654321, "partial fill restart preserves exact remainder")
	_send("fill", _payload("terrain.dirt.fill", 654321, "terrain-transfer-1"), _next())
	_check(_last.is_success and _mass() == 2000000 and not _state()["owner"]["transfers"].has("terrain-transfer-1"), "full fill consumes escrow without losing history")
	var filled: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(filled)
	before = _canonical()
	_return(valid, 1)
	_check(_last.is_success and _last.value == returned_receipt and _canonical() == before, "old return retry after full fill creates nothing")
	_context = original_context
	_claim(claim_payload, 1)
	_check(_last.is_success and _last.value == claim_receipt and _canonical() == before, "old claim retry after full fill creates nothing")
	for mutation in range(8):
		var bad: Dictionary = filled.duplicate(true)
		var entry: Dictionary = bad["systems"]["terrain"]["portable"]["terrain-transfer-1"]
		match mutation:
			0: entry["returned"] = null
			1: entry["receipt"]["mass_milligrams"] += 1
			2: entry["receipt"]["parcels"] = {"forged-origin": 777777}
			3: entry["returned"]["principal_id"] = "local-inventory-actor"
			4: entry["returned"]["owner_sequence"] = 3
			5: entry["returned"]["expected_inventory_revision"] = entry["expected_inventory_revision"]
			6: entry["returned"]["request_number"] = 2
			7: bad["systems"]["inventory"]["owner"]["ledger"]["items"].append({"item_id": "terrain-item-1", "definition_id": "item.terrain-parcel.prototype", "definition_revision": 1, "condition_permille": 1000, "container_id": "body.human-1"})
		_reject_snapshot(bad, "corrupt lifecycle/chronology checkpoint rejects atomically %d" % mutation)
	# Retire the domain receipt tail without retiring lifetime claim/return retries.
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	for cycle in range(33):
		_send("excavate", _payload("terrain.dirt.source", 1), _next())
		_check(_last.is_success, "receipt-tail excavation succeeds")
		if not _last.is_success: quit(1); return
		var id: String = _last.value["transfer_id"]
		_send("fill", _payload("terrain.dirt.source", 1, id), _next())
	var expired: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(expired)
	_context = original_context
	before = _canonical()
	_claim(claim_payload, 1)
	_check(_last.is_success and _last.value == claim_receipt and _canonical() == before, "claim retry survives return/full fill and excavation receipt eviction")
	_context = _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_return(valid, 1)
	_check(_last.is_success and _last.value == returned_receipt and _canonical() == before, "return retry survives domain receipt eviction")
	# Claiming a remainder after an earlier ordinary escrow fill is legitimate.
	_restart(preclaim)
	_context = original_context
	_send("fill", _payload("terrain.dirt.fill", 123456, "terrain-transfer-1"), _next())
	_check(_last.is_success, "ordinary escrow fill precedes claim")
	_claim(_claim_payload("terrain-transfer-1"), 1)
	_check(_last.is_success and _last.value["mass_milligrams"] == 654321, "claim receipt pins actual whole remaining escrow rather than initial excavation")
	var remainder_claim: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(remainder_claim)
	_return({"item_id": "terrain-item-1", "expected_inventory_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]}, 1)
	_check(_last.is_success, "remainder parcel returns")
	var remainder_return: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(remainder_return)
	_check(_mass() == 2000000, "prior-fill claim/return restart conserves exact matter")
	var fixture := FileAccess.open("res://var/terrain-return-fixture.json", FileAccess.WRITE)
	fixture.store_string(JSON.stringify({"active": active, "legacy": legacy, "transferred": transferred, "returned": returned, "partial": partial, "filled": filled, "claim_receipt": claim_receipt, "return_receipt": returned_receipt, "expired": expired, "remainder_claim": remainder_claim, "remainder_return": remainder_return, "observation": _terrain.observation(_context).value}))
	fixture.close()
	_world.free()
	if _failures == 0: print("Terrain return: exact odd mass, physical holder transfer, v2 migration, immutable retries, partial/full fill, lifecycle restart and corrupt chronology checks passed.")
	quit(0 if _failures == 0 else 1)


func _return(payload: Dictionary, number: int) -> void:
	var command := TerrainReturnCommand.new()
	command.command_id = StringName("terrain-return-%d" % number)
	command.request_number = number
	command.payload = payload.duplicate(true)
	command.authenticated_context = _context
	_check(_world.enqueue_command(command).is_success, "return queues")
	_step()


func _return_deny(payload: Dictionary, number: int, message: String) -> void:
	var before: Dictionary = _canonical()
	_return(payload, number)
	_check(not _last.is_success and _canonical() == before, message)


## Inject only failed synchronous adoption; the real owner still prepares/validates.
class FailedAdoption extends InventorySimulationSystem:
	var delegate: InventorySimulationSystem
	var attempted: bool = false

	func authorize(context: AuthenticatedCommandContext, require_voluntary_action: bool = false) -> ServiceResult:
		return delegate.authorize(context, require_voluntary_action)

	func production_capability(context: AuthenticatedCommandContext, voluntary: bool = true, target_position: Array = [0, 0, 0]) -> ServiceResult:
		return delegate.production_capability(context, voluntary, target_position)

	func own_inventory_observation(context: AuthenticatedCommandContext, include_details: bool = false) -> ServiceResult:
		return delegate.own_inventory_observation(context, include_details)

	func primary_payload_masses() -> Dictionary:
		return delegate.primary_payload_masses()

	func prepare_equipment_change(context: AuthenticatedCommandContext, request_id: String, item_id: String, create: bool, masses: Dictionary, definition_id: String, owner_record: Dictionary = {}, external: Variant = null) -> ServiceResult:
		return delegate.prepare_equipment_change(context, request_id, item_id, create, masses, definition_id, owner_record, external)

	func commit_prepared_owner(_record: Dictionary) -> ServiceResult:
		attempted = true
		return ServiceResult.failure(&"injected_adoption_failure", "Test-only failed adoption.")
