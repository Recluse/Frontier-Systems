extends RefCounted
class_name ToolComponentCatalog

## Declarative parts/materials/mounts and functions. Contains no world authorization.
const MAX_DEFINITIONS: int = 64
var _record: Dictionary = {}
var fingerprint: String = ""


func configure(value: Variant) -> ServiceResult:
	if not _record.is_empty() or typeof(value) != TYPE_DICTIONARY or not exact(value, ["schema_version", "materials", "components", "tools"]) or not ControlContractValidation.is_integer(value["schema_version"], 1, 1):
		return failure("An exact tool catalog is required.")
	for section in ["materials", "components", "tools"]:
		if typeof(value[section]) != TYPE_DICTIONARY or value[section].is_empty() or value[section].size() > MAX_DEFINITIONS:
			return failure("Catalog sections must be bounded nonempty registries.")
		for id in value[section]:
			if not ControlContractValidation.is_id(id) or typeof(value[section][id]) != TYPE_DICTIONARY:
				return failure("Definitions require stable IDs and objects.")
	for material in value["materials"].values():
		if not exact(material, ["name", "raw_material_id", "tier", "wear_ppm_per_cycle"]) or not named(material) or not ControlContractValidation.is_id(material["raw_material_id"]) or not ControlContractValidation.is_id(material["tier"]) or not ControlContractValidation.is_integer(material["wear_ppm_per_cycle"], 0, 1000000):
			return failure("Invalid material grade or wear policy.")
	for component in value["components"].values():
		if not exact(component, ["name", "mount_interfaces", "material_ids", "mass_milligrams", "wear_scale_permille", "operational_above_ppm", "repair_joules_per_permille", "functions"]) or not named(component) or not ids(component["mount_interfaces"], 1, 16) or not ids(component["material_ids"], 1, 16):
			return failure("Invalid component interfaces or material choices.")
		for material in component["material_ids"]:
			if not value["materials"].has(material): return failure("Unknown component material grade.")
		for field in ["mass_milligrams", "wear_scale_permille", "operational_above_ppm", "repair_joules_per_permille"]:
			var maximum: int = 100000000 if field == "mass_milligrams" else (1000000 if field == "operational_above_ppm" else 10000)
			if not ControlContractValidation.is_integer(component[field], 1 if field in ["mass_milligrams", "repair_joules_per_permille"] else 0, maximum): return failure("Invalid component units.")
		if not function_map(component["functions"]): return failure("Invalid component functions.")
	for tool in value["tools"].values():
		if not exact(tool, ["name", "slots", "actions"]) or not named(tool) or typeof(tool["slots"]) != TYPE_DICTIONARY or tool["slots"].is_empty() or tool["slots"].size() > 16 or not function_map(tool["actions"]):
			return failure("Invalid assembly layout or action requirements.")
		for slot in tool["slots"]:
			var rule: Variant = tool["slots"][slot]
			if not ControlContractValidation.is_id(slot) or typeof(rule) != TYPE_DICTIONARY or not exact(rule, ["mount_interfaces"]) or not ids(rule["mount_interfaces"], 1, 16): return failure("Invalid mounting slot.")
	_record = value.duplicate(true)
	_record["schema_version"] = 1
	for material in _record["materials"].values(): material["wear_ppm_per_cycle"] = int(material["wear_ppm_per_cycle"])
	for component in _record["components"].values():
		for field in ["mass_milligrams", "wear_scale_permille", "operational_above_ppm", "repair_joules_per_permille"]:
			component[field] = int(component[field])
	fingerprint = JSON.stringify(_record, "", true, true).sha256_text()
	return ServiceResult.success()


func definition(section: String, id: String) -> ServiceResult:
	if not _record.has(section) or not _record[section].has(id): return failure("Unknown tool definition.")
	return ServiceResult.success(_record[section][id].duplicate(true))


static func exact(value: Dictionary, fields: Array) -> bool:
	return ControlContractValidation.has_exact_fields(value, PackedStringArray(fields))


static func ids(value: Variant, minimum: int = 0, maximum: int = 32) -> bool:
	return ControlContractValidation.decode_ids(value, minimum, maximum).is_success


static func named(value: Dictionary) -> bool:
	return typeof(value.get("name")) == TYPE_STRING and not value["name"].is_empty() and value["name"].length() <= 80


static func function_map(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() > 32: return false
	for id in value:
		if not ControlContractValidation.is_id(id) or not ids(value[id]): return false
	return true


static func failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"tool_component_rejected", message)
