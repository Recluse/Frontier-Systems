extends "res://tests/godot/machinery_runtime_test.gd"

# Test-only alternate trusted host catalog, validated before configure fingerprints it.
class AlternateProduction extends ProductionSimulationSystem:
	func _validate_catalog(value: Dictionary) -> ServiceResult:
		value["recipes"]["craft.plate"]["inputs"] = {"iron": 250000}
		value["recipes"]["craft.plate"]["outputs"] = {"plate": 250000}
		value["recipes"]["craft.plate"]["energy_joules"] = 750
		value["recipes"]["craft.plate"]["station"] = "recycler"
		return super._validate_catalog(value)


func run() -> void:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "world starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	context = AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-actor", &"recipe-test", world.world_id, world.region_id, PackedStringArray(["inventory.operate", "terrain.operate"]))
	var snapshot: String = world.capture_world_snapshot_json().value
	var observed: Dictionary = production.observation(context).value
	check(observed["schema_version"] == 8 and JSON.parse_string(snapshot)["systems"]["production"]["schema_version"] == 7, "v8 observation and unchanged v7 persistence")
	var catalog: Dictionary = production._catalog.duplicate(true)
	for id in observed["recipes"]:
		var requirement: Dictionary = observed["recipe_requirements"][id]
		check(requirement["inputs"] == catalog["recipes"][id]["inputs"] and requirement["station"] == catalog["recipes"][id]["station"] and requirement["energy_joules"] == catalog["recipes"][id]["energy_joules"], "requirements derive from host catalog: " + id)
	var projection := RemoteProductionProjection.new()
	var wire: Dictionary = JSON.parse_string(JSON.stringify(observed))
	check(projection.accept_record(wire).is_success, "serialized host requirements accepted")
	check(WorkstationResourceView.recipe_text(projection.observation(null).value, "craft.plate") == WorkstationResourceView.recipe_text(observed, "craft.plate"), "local and JSON remote text parity")
	# Exercise the real remote frame receive path without binding a port.
	var remote := RemoteWorldRuntime.new()
	root.add_child(remote)
	remote.set_process(false)
	remote._authenticated = true
	check(TerrainObservationValidation.valid(JSON.parse_string(JSON.stringify(world.terrain_observation(context).value))), "test terrain frame valid")
	check(ToolObservationValidation.valid(JSON.parse_string(JSON.stringify(world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID).observation(context).value))), "test tools frame valid")
	remote._receive(JSON.parse_string(JSON.stringify({"type": "observation", "production": observed, "terrain": world.terrain_observation(context).value, "tools": world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID).observation(context).value, "inventory": inventory.own_inventory_observation(context, true).value, "position": [0, 0, 0], "players": []})))
	check(remote.production_observation(context).is_success and remote.production_observation(context).value["recipe_requirements"] == wire["recipe_requirements"], "actual client receive adopts host requirements")
	remote._connecting = true
	remote._process(0.0)
	check(not remote.production_observation(context).is_success and remote._observation.is_empty(), "disconnect clears requirements and identity")
	var legacy: Dictionary = observed.duplicate(true)
	legacy["schema_version"] = 7
	legacy.erase("recipe_requirements")
	var legacy_projection := RemoteProductionProjection.new()
	check(legacy_projection.accept_record(legacy).is_success, "legacy v7 explicitly readable")
	check(WorkstationResourceView.recipe_text(legacy, "craft.plate").contains("unavailable from legacy v7") and not WorkstationResourceView.recipe_text(legacy, "craft.plate").contains("short by"), "legacy costs never guessed")
	var bad: Array[Dictionary] = []
	var missing: Dictionary = observed.duplicate(true)
	missing.erase("recipe_requirements")
	bad.append(missing)
	for costs in [null, {}, {"craft.plate": {}}]:
		var item: Dictionary = observed.duplicate(true)
		item["recipe_requirements"] = costs
		bad.append(item)
	for field in ["inputs", "station", "energy_joules"]:
		var item: Dictionary = observed.duplicate(true)
		item["recipe_requirements"]["craft.plate"].erase(field)
		bad.append(item)
	for inputs in [{}, {"iron": 0}, {"iron": -1}, {"iron": 1.5}, {"iron": 100000001}, {"unknown": 1}, {"iron": 100000000, "plate": 1}]:
		var item: Dictionary = observed.duplicate(true)
		item["recipe_requirements"]["craft.plate"]["inputs"] = inputs
		bad.append(item)
	for energy in [0, -1, 1.5, 100001, "1000", true]:
		var item: Dictionary = observed.duplicate(true)
		item["recipe_requirements"]["craft.plate"]["energy_joules"] = energy
		bad.append(item)
	for station in [null, 42, "unknown"]:
		var item: Dictionary = observed.duplicate(true)
		item["recipe_requirements"]["craft.plate"]["station"] = station
		bad.append(item)
	var extra: Dictionary = observed.duplicate(true)
	extra["recipe_requirements"]["craft.plate"]["duration_ticks"] = 120
	bad.append(extra)
	var unknown: Dictionary = observed.duplicate(true)
	unknown["recipe_requirements"]["unknown"] = unknown["recipe_requirements"]["craft.plate"].duplicate(true)
	bad.append(unknown)
	var fingerprint: Dictionary = observed.duplicate(true)
	fingerprint["catalog_fingerprint"] = "z".repeat(64)
	bad.append(fingerprint)
	var oversized: Dictionary = observed.duplicate(true)
	oversized["recipes"] = []
	oversized["recipe_requirements"] = {}
	for index in range(33):
		var id: String = "recipe.test-%d" % index
		oversized["recipes"].append(id)
		oversized["recipe_requirements"][id] = {"station": "printer", "inputs": {"iron": 1}, "energy_joules": 1}
	bad.append(oversized)
	var revision: Dictionary = observed.duplicate(true)
	revision["catalog_revision"] = 0
	bad.append(revision)
	for item in bad:
		check(not WorkstationResourceView.valid(item) and WorkstationResourceView.recipe_text(item, "craft.plate").contains("unavailable"), "malformed requirements fail closed")
	var detached: Dictionary = projection.observation(null).value
	detached["recipe_requirements"]["craft.plate"]["inputs"]["iron"] = 1
	check(projection.record == wire and production.observation(context).value == observed, "detached observation cannot mutate catalog requirements")
	var changed: Dictionary = observed.duplicate(true)
	changed["recipe_requirements"]["craft.plate"]["energy_joules"] = 999
	check(not projection.accept_record(changed).is_success and projection.record == wire, "same identity cannot change requirements")
	changed = observed.duplicate(true)
	changed["catalog_fingerprint"] = "a".repeat(64)
	check(not projection.accept_record(changed).is_success, "catalog identity cannot change within connection")
	check(not projection.accept_record(legacy).is_success, "requirements cannot disappear via v7 downgrade")
	var alternate_inventory := InventorySimulationSystem.new()
	check(alternate_inventory.configure_defaults(true).is_success, "alternate inventory configured")
	var alternate := AlternateProduction.new()
	check(alternate.configure(alternate_inventory).is_success, "alternate validated catalog configures")
	var alternate_record: Dictionary = alternate.observation(context).value
	check(alternate_record["catalog_fingerprint"] != observed["catalog_fingerprint"], "alternate catalog has distinct immutable identity")
	var text: String = WorkstationResourceView.recipe_text(alternate_record, "craft.plate")
	check(text.contains("iron 0.250 kg; 750 J at recycler") and text.contains("shared iron short by 0.250 kg"), "alternate host costs replace fixture assumptions")
	var new_projection := RemoteProductionProjection.new()
	check(new_projection.accept_record(JSON.parse_string(JSON.stringify(alternate_record))).is_success, "new connection can adopt alternate host")
	check(WorkstationResourceView.recipe_text(new_projection.record, "craft.plate") == text, "alternate local/remote parity")
	var exhausted: Dictionary = observed.duplicate(true)
	exhausted["deposits"]["deposit.iron"] = 0
	exhausted["cargo"]["resource-canister-1"]["iron"] = 1000000
	check(WorkstationResourceView.recipe_text(exhausted, "craft.plate").contains("shared iron short by 1.000 kg"), "deposits and owned cargo do not pay shared inputs")
	exhausted["store"]["iron"] = 1000000
	check(not WorkstationResourceView.recipe_text(exhausted, "craft.plate").contains("short by"), "depleted deposit does not block stocked recipe")
	check(world.capture_world_snapshot_json().value == snapshot and production._catalog == catalog, "read-only requirements preserve state and catalog")
	# Emitted runtime fixtures feed the independent JSON Schema check.
	DirAccess.make_dir_recursive_absolute("res://var")
	var fixture := FileAccess.open("res://var/recipe-requirements-fixture.json", FileAccess.WRITE)
	fixture.store_string(JSON.stringify({"current": observed, "legacy": legacy, "alternate": alternate_record, "persistent": JSON.parse_string(snapshot)["systems"]["production"], "malformed": bad}))
	fixture.close()
	remote.free()
	projection.free()
	legacy_projection.free()
	new_projection.free()
	alternate.free()
	alternate_inventory.free()
	world.free()
	print("Recipe requirements failures: %d" % failures)
	quit(0 if failures == 0 else 1)
