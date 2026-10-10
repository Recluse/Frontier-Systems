extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var catalog := MaterialCatalog.new()
	for path in ["res://data/materials/dirt.v1.json", "res://data/materials/mars-regolith.v1.json", "res://data/materials/moon-regolith.v1.json"]:
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		_check(catalog.register_definition(record).is_success, "trusted fixture must register")
	var dirt: MaterialDefinition = catalog.get_definition("material.dirt", 1).value
	_check(dirt.uses.has("terrain.fill") and dirt.uses.has("crafting.feedstock") and dirt.uses.has("hydroponics.substrate"), "dirt must support all three requested uses")
	dirt.prototype_bulk_density_kg_m3 = 1.0
	_check(catalog.get_definition("material.dirt", 1).value.prototype_bulk_density_kg_m3 == 1200.0, "catalog lookup must be detached")
	var record := {"schema_version": 1, "cell_id": "terrain-cell-1", "state_revision": 7,
		"material_id": "material.dirt", "material_revision": 1, "mass_milligrams": 1200000000}
	var parsed: ServiceResult = TerrainMaterialState.from_record(record, catalog)
	_check(parsed.is_success, "terrain record must parse")
	var cell: TerrainMaterialState = parsed.value
	_check(is_equal_approx(cell.volume_m3(), 1.0), "volume must derive from mass and pinned prototype density")
	var mined: ServiceResult = cell.plan_excavation(250000000)
	_check(mined.is_success, "available material must excavate")
	var plan: Dictionary = mined.value
	_check(plan["after"]["mass_milligrams"] + plan["amount_milligrams"] == record["mass_milligrams"], "excavation must conserve mass")
	_check(plan["inventory_direction"] == "produce" and plan["after"]["state_revision"] == 8, "excavation must yield stock and declare a new cell revision")
	_check(cell.to_record() == record, "planning must not mutate canonical terrain")
	var mined_cell: TerrainMaterialState = TerrainMaterialState.from_record(JSON.parse_string(JSON.stringify(plan["after"])), catalog).value
	var filled: ServiceResult = mined_cell.plan_fill("material.dirt", 1, 250000000)
	_check(filled.is_success and filled.value["after"]["mass_milligrams"] == record["mass_milligrams"], "returning dug dirt must reconstruct original mass")
	_check(filled.value["inventory_direction"] == "consume", "terrain placement must consume stock")
	_check(not cell.plan_excavation(1200000001).is_success, "over-mining must reject")
	_check(not cell.plan_excavation(0).is_success and not cell.plan_excavation(-1).is_success, "zero and negative extraction must reject")
	_check(not cell.plan_fill("material.regolith.moon", 1, 1).is_success, "different material must not silently mix into the cell")
	var invalid: Dictionary = record.duplicate(true)
	invalid["mass_milligrams"] = 1.5
	_check(not TerrainMaterialState.from_record(invalid, catalog).is_success, "fractional milligrams must reject")
	invalid["mass_milligrams"] = -1
	_check(not TerrainMaterialState.from_record(invalid, catalog).is_success, "negative source mass must reject")
	invalid = record.duplicate(true)
	invalid["mass_milligrams"] = TerrainMaterialState.MAX_EXACT_INTEGER
	var full: TerrainMaterialState = TerrainMaterialState.from_record(invalid, catalog).value
	_check(not full.plan_fill("material.dirt", 1, 1).is_success, "mass overflow must reject")
	invalid = record.duplicate(true)
	invalid["state_revision"] = TerrainMaterialState.MAX_EXACT_INTEGER
	var exhausted: TerrainMaterialState = TerrainMaterialState.from_record(invalid, catalog).value
	_check(not exhausted.plan_excavation(1).is_success, "exhausted revisions must reject further plans")
	_check(not catalog.get_definition("invented-material", 1).is_success, "unknown materials must reject")
	var regolith: MaterialDefinition = catalog.get_definition("material.regolith.mars", 1).value
	_check(not regolith.uses.has("hydroponics.substrate"), "untreated regolith must not acquire growing-medium capability automatically")
	if _failures == 0:
		print("Terrain material conservation and contract scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
