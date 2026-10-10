extends RefCounted
class_name TerrainMaterialState

## Homogeneous terrain cell planning foundation. Mass is canonical, geometry derived.
## Plans do not commit changes or create inventory. A future owner must transact both.
const MAX_EXACT_INTEGER: int = 9007199254740990
var cell_id: String = ""
var state_revision: int = 0
var mass_milligrams: int = 0
var _material: MaterialDefinition


func to_record() -> Dictionary:
	return {"schema_version": 1, "cell_id": cell_id, "state_revision": state_revision,
		"material_id": _material.definition_id, "material_revision": _material.revision,
		"mass_milligrams": mass_milligrams}


func volume_m3() -> float:
	return float(mass_milligrams) / 1000000.0 / _material.prototype_bulk_density_kg_m3


func plan_excavation(amount_milligrams: int) -> ServiceResult:
	return _plan(amount_milligrams, false)


func plan_fill(material_id: String, material_revision: int, amount_milligrams: int) -> ServiceResult:
	if _material == null or material_id != _material.definition_id or material_revision != _material.revision:
		return ServiceResult.failure(&"terrain_material_mismatch", "Mixing materials requires an explicit recipe or layered terrain operation.")
	return _plan(amount_milligrams, true)


func _plan(amount_milligrams: int, filling: bool) -> ServiceResult:
	if _material == null or not ControlContractValidation.is_id(cell_id) or mass_milligrams < 0 or mass_milligrams > MAX_EXACT_INTEGER or state_revision < 0 or amount_milligrams <= 0 or amount_milligrams > MAX_EXACT_INTEGER or state_revision >= MAX_EXACT_INTEGER:
		return ServiceResult.failure(&"invalid_terrain_transfer", "A bounded positive quantity and valid terrain state are required.")
	if (not filling and amount_milligrams > mass_milligrams) or (filling and amount_milligrams > MAX_EXACT_INTEGER - mass_milligrams):
		return ServiceResult.failure(&"terrain_mass_limit", "Excavation exceeds existing mass or fill exceeds capacity.")
	var after: Dictionary = to_record()
	after["state_revision"] = state_revision + 1
	after["mass_milligrams"] = mass_milligrams + amount_milligrams if filling else mass_milligrams - amount_milligrams
	return ServiceResult.success({"schema_version": 1, "operation": "fill" if filling else "excavate",
		"expected_cell_revision": state_revision, "before": to_record(), "after": after,
		"inventory_direction": "consume" if filling else "produce", "material_id": _material.definition_id,
		"material_revision": _material.revision, "amount_milligrams": amount_milligrams})


static func from_record(record: Dictionary, catalog: MaterialCatalog) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "cell_id", "state_revision", "material_id", "material_revision", "mass_milligrams"])
	if catalog == null or not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return ServiceResult.failure(&"invalid_terrain_material_state", "A complete terrain record and trusted material catalog are required.")
	if not ControlContractValidation.is_id(record["cell_id"]) or not ControlContractValidation.is_id(record["material_id"]):
		return ServiceResult.failure(&"invalid_terrain_identity", "Terrain and material IDs must be stable strings.")
	for field in ["state_revision", "mass_milligrams"]:
		if not ControlContractValidation.is_integer(record[field], 0, MAX_EXACT_INTEGER):
			return ServiceResult.failure(&"invalid_terrain_quantity", "Terrain quantities must be exact non-negative integers.")
	if not ControlContractValidation.is_integer(record["material_revision"], 1, MAX_EXACT_INTEGER):
		return ServiceResult.failure(&"invalid_terrain_material_revision", "A positive pinned material revision is required.")
	var resolved: ServiceResult = catalog.get_definition(record["material_id"], int(record["material_revision"]))
	if not resolved.is_success:
		return resolved
	var definition: MaterialDefinition = resolved.value
	if not definition.uses.has("terrain.fill"):
		return ServiceResult.failure(&"material_not_terrain_fill", "This material is not commissioned for terrain placement.")
	var cell := TerrainMaterialState.new()
	cell.cell_id = record["cell_id"]
	cell.state_revision = int(record["state_revision"])
	cell.mass_milligrams = int(record["mass_milligrams"])
	cell._material = definition
	return ServiceResult.success(cell)
