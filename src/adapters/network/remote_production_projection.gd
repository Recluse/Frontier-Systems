extends ProductionSimulationSystem
class_name RemoteProductionProjection

## Read-only client projection, never configured as a canonical simulation owner.
var record: Dictionary = {}
const MATERIALS: Array[String] = ["ore.iron", "ice", "regolith", "iron", "tailings", "water", "hydrogen", "oxygen", "salts", "silicate", "nutrient-solution", "plate"]


func accept_record(value: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "catalog_revision", "catalog_fingerprint", "timebase_hz", "last_tick", "state_revision", "deposits", "store", "vessel", "wall_mass_milligrams", "energy_joules", "powered", "job", "cargo", "components", "recipes", "dispensable", "can_operate", "vessel_pressure_kpa", "extractable_sources"])
	fields.append("machinery")
	fields.append("walls")
	fields.append_array(PackedStringArray(["structures", "blueprints", "loose_parts", "tool_extraction"]))
	if not ControlContractValidation.has_exact_fields(value, fields) or not ControlContractValidation.is_integer(value.get("schema_version"), 7, 7) or not ControlContractValidation.is_integer(value.get("timebase_hz"), 60, 90) or not [60, 72, 90].has(int(value.get("timebase_hz"))) or typeof(value.get("can_operate")) != TYPE_BOOL:
		return _invalid()
	if not SpatialWallConstruction.valid(value["walls"]): return _invalid()
	for field in ["last_tick", "state_revision", "catalog_revision", "wall_mass_milligrams", "energy_joules"]:
		if not ControlContractValidation.is_integer(value[field], 0, 9007199254740000):
			return _invalid()
	if typeof(value["catalog_fingerprint"]) != TYPE_STRING or value["catalog_fingerprint"].length() != 64:
		return _invalid()
	if not _valid_stock(value["store"], true) or not _valid_stock(value["vessel"], true) or typeof(value["cargo"]) != TYPE_DICTIONARY or value["cargo"].size() > 32:
		return _invalid()
	for id in value["cargo"]:
		if not ControlContractValidation.is_id(id) or not _valid_stock(value["cargo"][id], true):
			return _invalid()
	if typeof(value["blueprints"]) != TYPE_DICTIONARY or value["blueprints"].size() > 32 or typeof(value["structures"]) != TYPE_DICTIONARY or value["structures"].size() > 32:
		return _invalid()
	for id in value["blueprints"]:
		var blueprint: Variant = value["blueprints"][id]
		if not ControlContractValidation.is_id(id) or typeof(blueprint) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(blueprint, PackedStringArray(["name", "definition_id", "definition_revision", "materials", "fabrication_energy_joules", "salvage_energy_joules", "fingerprint", "modular"])) or typeof(blueprint["modular"]) != TYPE_BOOL or typeof(blueprint["name"]) != TYPE_STRING or blueprint["name"].length() > 80 or not ControlContractValidation.is_id(blueprint["definition_id"]) or not ControlContractValidation.is_integer(blueprint["definition_revision"], 1, 1) or not _valid_stock(blueprint["materials"]) or typeof(blueprint["fingerprint"]) != TYPE_STRING or blueprint["fingerprint"].length() != 64:
			return _invalid()
		for field in ["fabrication_energy_joules", "salvage_energy_joules"]:
			if not ControlContractValidation.is_integer(blueprint[field], 1, 100000):
				return _invalid()
	if typeof(value["loose_parts"]) != TYPE_DICTIONARY or value["loose_parts"].size() > 128: return _invalid()
	for id in value["loose_parts"]:
		if not ControlContractValidation.is_id(id) or not _valid_stock(value["loose_parts"][id]): return _invalid()
	for id in value["structures"]:
		var structure: Variant = value["structures"][id]
		if not ControlContractValidation.is_id(id) or typeof(structure) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(structure, PackedStringArray(["blueprint_id", "fingerprint", "materials"])) or typeof(structure["blueprint_id"]) != TYPE_STRING or not value["blueprints"].has(structure["blueprint_id"]) or structure["fingerprint"] != value["blueprints"][structure["blueprint_id"]]["fingerprint"] or not _valid_stock(structure["materials"]):
			return _invalid()
		if not value["blueprints"][structure["blueprint_id"]]["modular"] and not _same_stock(structure["materials"], value["blueprints"][structure["blueprint_id"]]["materials"]):
			return _invalid()
	for field in ["components", "recipes", "dispensable", "extractable_sources"]:
		if not ControlContractValidation.decode_ids(value[field], 0, 32).is_success:
			return _invalid()
	if typeof(value["deposits"]) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value["deposits"], PackedStringArray(SOURCE_POSITIONS.keys())):
		return _invalid()
	for mass in value["deposits"].values():
		if not ControlContractValidation.is_integer(mass, 0, MAX_MASS):
			return _invalid()
	if typeof(value["powered"]) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value["powered"], PackedStringArray(STATIONS)):
		return _invalid()
	for enabled in value["powered"].values():
		if typeof(enabled) != TYPE_BOOL:
			return _invalid()
	if typeof(value["job"]) != TYPE_DICTIONARY:
		return _invalid()
	if not value["job"].is_empty():
		var job: Dictionary = value["job"]
		if not ControlContractValidation.has_exact_fields(job, PackedStringArray(["recipe_id", "deposit_id", "station", "inputs", "outputs", "remaining_ticks"])) or not STATIONS.has(job["station"]) or not _valid_stock(job["inputs"]) or not _valid_stock(job["outputs"]) or not ControlContractValidation.is_integer(job["remaining_ticks"], 1, 36000) or typeof(job["recipe_id"]) != TYPE_STRING or typeof(job["deposit_id"]) != TYPE_STRING:
			return _invalid()
	if typeof(value["tool_extraction"]) != TYPE_DICTIONARY or (not value["tool_extraction"].is_empty() and not ToolExtractionWork.valid(value["tool_extraction"])): return _invalid()
	var pressure: Variant = value["vessel_pressure_kpa"]
	if (typeof(pressure) != TYPE_INT and typeof(pressure) != TYPE_FLOAT) or not is_finite(float(pressure)) or float(pressure) < 0.0 or float(pressure) > MAX_VESSEL_PRESSURE_KPA:
		return _invalid()
	if typeof(value["machinery"]) != TYPE_DICTIONARY: return _invalid()
	var machinery: Dictionary = value["machinery"].duplicate(true)
	if typeof(machinery.get("inventory_items")) != TYPE_ARRAY or machinery["inventory_items"].size() > 512 or typeof(machinery.get("cargo")) != TYPE_DICTIONARY or machinery["cargo"].size() > 32: return _invalid()
	for physical in machinery["inventory_items"]:
		if typeof(physical) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(physical, PackedStringArray(["item_id", "definition_id", "definition_revision", "condition_permille", "container_id"])) or not ControlContractValidation.is_id(physical["item_id"]) or not ControlContractValidation.is_id(physical["definition_id"]) or not ControlContractValidation.is_id(physical["container_id"]) or not ControlContractValidation.is_integer(physical["definition_revision"], 1, 1) or not ControlContractValidation.is_integer(physical["condition_permille"], 0, 1000): return _invalid()
	for stock in machinery["cargo"].values():
		if not _valid_stock(stock, true): return _invalid()
	machinery.erase("inventory_items")
	machinery.erase("cargo")
	if not MachineryWorkshop.validate(machinery): return _invalid()
	if not SpatialWallConstruction.scene_clear(value["walls"], machinery, {"bodies": []}): return _invalid()
	record = value.duplicate(true)
	return ServiceResult.success()


static func _valid_stock(stock: Variant, complete: bool = false) -> bool:
	if typeof(stock) != TYPE_DICTIONARY or stock.size() > 32 or (complete and not ControlContractValidation.has_exact_fields(stock, PackedStringArray(MATERIALS))):
		return false
	for material in stock:
		if not MATERIALS.has(material) or not ControlContractValidation.is_integer(stock[material], 0, MAX_MASS):
			return false
	return true


static func _invalid() -> ServiceResult:
	return ServiceResult.failure(&"invalid_remote_projection", "The host production observation is malformed.")


func observation(_context: AuthenticatedCommandContext) -> ServiceResult:
	return ServiceResult.success(record.duplicate(true)) if not record.is_empty() else ServiceResult.failure(&"remote_observation_pending", "Awaiting host state.")
