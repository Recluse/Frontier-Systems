extends ProductionSimulationSystem
class_name RemoteProductionProjection

## Read-only client projection, never configured as a canonical simulation owner.
var record: Dictionary = {}
const MATERIALS: Array[String] = ["ore.iron", "ice", "regolith", "iron", "tailings", "water", "hydrogen", "oxygen", "salts", "silicate", "nutrient-solution", "plate"]


func accept_record(value: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "catalog_revision", "catalog_fingerprint", "timebase_hz", "last_tick", "state_revision", "deposits", "store", "vessel", "wall_mass_milligrams", "energy_joules", "powered", "job", "cargo", "components", "recipes", "dispensable", "can_operate", "vessel_pressure_kpa", "extractable_sources"])
	if not ControlContractValidation.has_exact_fields(value, fields) or not ControlContractValidation.is_integer(value.get("schema_version"), 2, 2) or not ControlContractValidation.is_integer(value.get("timebase_hz"), 60, 90) or not [60, 72, 90].has(int(value.get("timebase_hz"))) or typeof(value.get("can_operate")) != TYPE_BOOL:
		return _invalid()
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
	var pressure: Variant = value["vessel_pressure_kpa"]
	if (typeof(pressure) != TYPE_INT and typeof(pressure) != TYPE_FLOAT) or not is_finite(float(pressure)) or float(pressure) < 0.0 or float(pressure) > MAX_VESSEL_PRESSURE_KPA:
		return _invalid()
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
