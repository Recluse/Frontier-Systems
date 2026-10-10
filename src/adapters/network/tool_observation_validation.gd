extends RefCounted
class_name ToolObservationValidation

## Bounded read-only network view, independent of the authoritative catalog.
static func valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(value, ["schema_version", "state_revision", "assemblies"]) or not ControlContractValidation.is_integer(value["schema_version"], 1, 1) or not ControlContractValidation.is_integer(value["state_revision"], 0, 9007199254740000) or typeof(value["assemblies"]) != TYPE_ARRAY or value["assemblies"].size() > 64: return false
	var ids: Dictionary = {}
	var parts: Dictionary = {}
	for assembly in value["assemblies"]:
		if typeof(assembly) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(assembly, ["assembly_id", "functions", "actions", "parts"]) or not ControlContractValidation.is_id(assembly["assembly_id"]) or ids.has(assembly["assembly_id"]) or not _ids(assembly["functions"]) or typeof(assembly["actions"]) != TYPE_DICTIONARY or assembly["actions"].size() > 32 or typeof(assembly["parts"]) != TYPE_ARRAY or assembly["parts"].size() > 16: return false
		ids[assembly["assembly_id"]] = true
		for action in assembly["actions"]:
			var details: Variant = assembly["actions"][action]
			if not ControlContractValidation.is_id(action) or typeof(details) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(details, ["available", "missing_functions"]) or typeof(details["available"]) != TYPE_BOOL or not _ids(details["missing_functions"]) or details["available"] != details["missing_functions"].is_empty(): return false
		for part in assembly["parts"]:
			if typeof(part) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(part, ["schema_version", "part_id", "definition_id", "material_id", "integrity_ppm", "wear_remainder", "name", "material_name"]): return false
			for key in ["part_id", "definition_id", "material_id"]:
				if not ControlContractValidation.is_id(part[key]): return false
			if parts.has(part["part_id"]) or parts.size() >= 512: return false
			parts[part["part_id"]] = true
			if not ControlContractValidation.is_integer(part["schema_version"], 1, 1) or not ControlContractValidation.is_integer(part["integrity_ppm"], 0, 1000000) or not ControlContractValidation.is_integer(part["wear_remainder"], 0, 999): return false
			for key in ["name", "material_name"]:
				if typeof(part[key]) != TYPE_STRING or part[key].is_empty() or part[key].length() > 128: return false
	return true


static func _ids(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() > 32: return false
	var seen: Dictionary = {}
	for id in value:
		if not ControlContractValidation.is_id(id) or seen.has(id): return false
		seen[id] = true
	return true
