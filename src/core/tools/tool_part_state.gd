extends RefCounted
class_name ToolPartState

## Independently persistent part, including when detached from all assemblies.
const MAX_INTEGRITY: int = 1000000
var _record: Dictionary = {}
var _catalog: ToolComponentCatalog


static func create(part_id: String, definition_id: String, material_id: String, catalog: ToolComponentCatalog) -> ServiceResult:
	return from_record({"schema_version": 1, "part_id": part_id, "definition_id": definition_id, "material_id": material_id, "integrity_ppm": MAX_INTEGRITY, "wear_remainder": 0}, catalog)


static func from_record(value: Variant, catalog: ToolComponentCatalog) -> ServiceResult:
	if catalog == null or typeof(value) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(value, ["schema_version", "part_id", "definition_id", "material_id", "integrity_ppm", "wear_remainder"]): return ToolComponentCatalog.failure("An exact part record is required.")
	if not ControlContractValidation.is_integer(value["schema_version"], 1, 1) or not ControlContractValidation.is_id(value["part_id"]) or not ControlContractValidation.is_id(value["definition_id"]) or not ControlContractValidation.is_id(value["material_id"]) or not ControlContractValidation.is_integer(value["integrity_ppm"], 0, MAX_INTEGRITY) or not ControlContractValidation.is_integer(value["wear_remainder"], 0, 999): return ToolComponentCatalog.failure("Invalid part identity, integrity or fractional wear.")
	var definition: ServiceResult = catalog.definition("components", value["definition_id"])
	if not definition.is_success or not definition.value["material_ids"].has(value["material_id"]): return ToolComponentCatalog.failure("The component does not support that material grade.")
	var part := ToolPartState.new()
	part._record = value.duplicate(true)
	for field in ["schema_version", "integrity_ppm", "wear_remainder"]: part._record[field] = int(value[field])
	part._catalog = catalog
	return ServiceResult.success(part)


func to_record() -> Dictionary:
	return _record.duplicate(true)


func operational() -> bool:
	return _record["integrity_ppm"] > _catalog.definition("components", _record["definition_id"]).value["operational_above_ppm"]


func material_stock() -> Dictionary:
	var material: Dictionary = _catalog.definition("materials", _record["material_id"]).value
	return {material["raw_material_id"]: int(_catalog.definition("components", _record["definition_id"]).value["mass_milligrams"])}


## Wear changes condition, never deletes a component or consumes its material mass.
func plan_usage(cycles: int) -> ServiceResult:
	if cycles < 1 or cycles > 10000: return ToolComponentCatalog.failure("Usage must contain 1–10000 bounded work cycles.")
	var component: Dictionary = _catalog.definition("components", _record["definition_id"]).value
	var material: Dictionary = _catalog.definition("materials", _record["material_id"]).value
	var numerator: int = int(material["wear_ppm_per_cycle"]) * int(component["wear_scale_permille"]) * cycles + int(_record["wear_remainder"])
	var next: Dictionary = to_record()
	next["integrity_ppm"] = maxi(0, int(next["integrity_ppm"]) - numerator / 1000)
	next["wear_remainder"] = numerator % 1000
	return ServiceResult.success(next)


## Proposed maintenance, not a free remote repair action. Owner must debit energy.
func plan_repair(amount_ppm: int) -> ServiceResult:
	if amount_ppm < 1 or amount_ppm > MAX_INTEGRITY: return ToolComponentCatalog.failure("Repair must contain bounded positive integrity.")
	var restored: int = mini(amount_ppm, MAX_INTEGRITY - int(_record["integrity_ppm"]))
	if restored == 0: return ToolComponentCatalog.failure("The part needs no maintenance.")
	var next: Dictionary = to_record()
	next["integrity_ppm"] += restored
	# Sub-integrity wear is retained: small maintenance cannot erase accumulated wear.
	var energy: int = int(ceil(float(restored) / 1000.0)) * int(_catalog.definition("components", _record["definition_id"]).value["repair_joules_per_permille"])
	return ServiceResult.success({"part": next, "energy_joules": energy})


func plan_damage(amount_ppm: int) -> ServiceResult:
	if amount_ppm < 1 or amount_ppm > MAX_INTEGRITY: return ToolComponentCatalog.failure("Damage must contain bounded positive integrity.")
	var next: Dictionary = to_record()
	next["integrity_ppm"] = maxi(0, int(next["integrity_ppm"]) - amount_ppm)
	return ServiceResult.success(next)
