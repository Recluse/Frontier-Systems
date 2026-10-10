extends RefCounted
class_name EquipmentBlueprintCatalog

## Immutable trusted assembly specifications, separate from commodity recipes.
const MAX_BLUEPRINTS: int = 32
var _definitions: Dictionary = {}


func configure(record: Variant, inventory: InventorySimulationSystem, materials: Array) -> ServiceResult:
	if not _definitions.is_empty() or typeof(record) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "blueprints"])) or not ControlContractValidation.is_integer(record["schema_version"], 1, 1) or typeof(record["blueprints"]) != TYPE_DICTIONARY or record["blueprints"].is_empty() or record["blueprints"].size() > MAX_BLUEPRINTS:
		return _failure()
	var definitions: Dictionary = {}
	var item_ids: Dictionary = {}
	for id in record["blueprints"]:
		var value: Variant = record["blueprints"][id]
		if not ControlContractValidation.is_id(id) or typeof(value) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value, PackedStringArray(["name", "definition_id", "definition_revision", "materials", "fabrication_energy_joules", "salvage_energy_joules"])):
			return _failure()
		if typeof(value["name"]) != TYPE_STRING or value["name"].is_empty() or value["name"].length() > 80 or not ControlContractValidation.is_id(value["definition_id"]) or not ControlContractValidation.is_integer(value["definition_revision"], 1, 1) or item_ids.has(value["definition_id"]):
			return _failure()
		var definition: ServiceResult = inventory.factory_definition(value["definition_id"])
		if not definition.is_success or int(definition.value["mass_milligrams"]) != 0 or definition.value["storage"] != null or not definition.value["tags"].has("equipment.fabricated"):
			return _failure() # Structural mass belongs to production; storage graphs follow later.
		if typeof(value["materials"]) != TYPE_DICTIONARY or value["materials"].is_empty() or value["materials"].size() > 32:
			return _failure()
		var normalized: Dictionary = value.duplicate(true)
		var total: int = 0
		for material in value["materials"]:
			if not materials.has(material) or not ControlContractValidation.is_integer(value["materials"][material], 1, 100000000):
				return _failure()
			normalized["materials"][material] = int(value["materials"][material])
			total += normalized["materials"][material]
		if total > 100000000:
			return _failure()
		for energy in ["fabrication_energy_joules", "salvage_energy_joules"]:
			if not ControlContractValidation.is_integer(value[energy], 1, 100000):
				return _failure()
			normalized[energy] = int(value[energy])
		normalized["definition_revision"] = 1
		normalized["fingerprint"] = JSON.stringify(normalized, "", true, true).sha256_text()
		definitions[id] = normalized
		item_ids[value["definition_id"]] = true
	_definitions = definitions
	return ServiceResult.success()


func get_definition(id: String) -> ServiceResult:
	return ServiceResult.success(_definitions[id].duplicate(true)) if _definitions.has(id) else _failure()


func observation() -> Dictionary:
	return _definitions.duplicate(true)


func validate_structure(value: Variant) -> ServiceResult:
	if typeof(value) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value, PackedStringArray(["blueprint_id", "fingerprint", "materials"])) or typeof(value["blueprint_id"]) != TYPE_STRING:
		return _failure()
	var result: ServiceResult = get_definition(value["blueprint_id"])
	if not result.is_success or value["fingerprint"] != result.value["fingerprint"] or typeof(value["materials"]) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(value["materials"], PackedStringArray(result.value["materials"].keys())):
		return _failure()
	for material in result.value["materials"]:
		if not ControlContractValidation.is_integer(value["materials"][material], result.value["materials"][material], result.value["materials"][material]):
			return _failure()
	return ServiceResult.success({"blueprint_id": value["blueprint_id"], "fingerprint": result.value["fingerprint"], "materials": result.value["materials"].duplicate(true)})


static func _failure() -> ServiceResult:
	return ServiceResult.failure(&"invalid_equipment_blueprint", "Equipment blueprint or structural material record is invalid or differs from its pinned definition.")
