extends RefCounted
class_name MaterialDefinition

## Trusted material reference. Density is prototype tuning, not a chemistry model.
var definition_id: String = ""
var revision: int = 1
var display_name: String = ""
var prototype_bulk_density_kg_m3: float = 1.0
var uses := PackedStringArray()


func to_record() -> Dictionary:
	return {"schema_version": 1, "definition_id": definition_id, "revision": revision,
		"display_name": display_name, "prototype_bulk_density_kg_m3": prototype_bulk_density_kg_m3, "uses": Array(uses)}


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "definition_id", "revision", "display_name", "prototype_bulk_density_kg_m3", "uses"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return ServiceResult.failure(&"invalid_material_definition", "A complete versioned material definition is required.")
	if not ControlContractValidation.is_id(record["definition_id"]) or not ControlContractValidation.is_id(record["display_name"]) or not ControlContractValidation.is_integer(record["revision"], 1, 9007199254740990):
		return ServiceResult.failure(&"invalid_material_identity", "Material identity and revision must be valid.")
	var density: Variant = record["prototype_bulk_density_kg_m3"]
	if (typeof(density) != TYPE_INT and typeof(density) != TYPE_FLOAT) or not is_finite(float(density)) or float(density) <= 0.0 or float(density) > 100000.0:
		return ServiceResult.failure(&"invalid_material_density", "Prototype density must be finite, positive and bounded.")
	var usage: ServiceResult = ControlContractValidation.decode_ids(record["uses"], 1, 16)
	if not usage.is_success:
		return usage
	for use_id in usage.value:
		if use_id not in ["terrain.fill", "crafting.feedstock", "hydroponics.substrate"]:
			return ServiceResult.failure(&"unknown_material_use", "The prototype material use is not registered.")
	var definition := MaterialDefinition.new()
	definition.definition_id = record["definition_id"]
	definition.revision = int(record["revision"])
	definition.display_name = record["display_name"]
	definition.prototype_bulk_density_kg_m3 = float(density)
	definition.uses = usage.value
	return ServiceResult.success(definition)
