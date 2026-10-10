extends RefCounted
class_name ToolObservationValidation

## Bounded read-only network view, independent of authoritative world state.
static func valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(value, ["schema_version", "state_revision", "assemblies", "loose_parts", "part_blueprints"]) or not ControlContractValidation.is_integer(value["schema_version"], 2, 2) or not ControlContractValidation.is_integer(value["state_revision"], 0, 9007199254740000) or typeof(value["assemblies"]) != TYPE_ARRAY or value["assemblies"].size() > 64 or typeof(value["loose_parts"]) != TYPE_ARRAY or value["loose_parts"].size() > 128 or typeof(value["part_blueprints"]) != TYPE_DICTIONARY or value["part_blueprints"].size() > 32: return false
	var ids: Dictionary = {}
	var parts: Dictionary = {}
	for assembly in value["assemblies"]:
		if typeof(assembly) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(assembly, ["assembly_id", "functions", "actions", "parts", "slots"]) or not ControlContractValidation.is_id(assembly["assembly_id"]) or ids.has(assembly["assembly_id"]) or not _ids(assembly["functions"]) or typeof(assembly["actions"]) != TYPE_DICTIONARY or assembly["actions"].size() > 32 or typeof(assembly["parts"]) != TYPE_ARRAY or assembly["parts"].size() > 16 or typeof(assembly["slots"]) != TYPE_DICTIONARY or assembly["slots"].size() > 16: return false
		ids[assembly["assembly_id"]] = true
		for action in assembly["actions"]:
			var details: Variant = assembly["actions"][action]
			if not ControlContractValidation.is_id(action) or typeof(details) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(details, ["available", "missing_functions"]) or typeof(details["available"]) != TYPE_BOOL or not _ids(details["missing_functions"]) or details["available"] != details["missing_functions"].is_empty(): return false
		var fitted: Dictionary = {}
		for part in assembly["parts"]:
			if not _part(part, parts): return false
			fitted[part["part_id"]] = true
		var mounted: Dictionary = {}
		for slot in assembly["slots"]:
			var id: Variant = assembly["slots"][slot]
			if not ControlContractValidation.is_id(slot) or typeof(id) != TYPE_STRING: return false
			if id == "": continue
			if not fitted.has(id) or mounted.has(id): return false
			mounted[id] = true
		if mounted.size() != fitted.size(): return false
	for part in value["loose_parts"]:
		if not _part(part, parts): return false
	for id in value["part_blueprints"]:
		var blueprint: Variant = value["part_blueprints"][id]
		if not ControlContractValidation.is_id(id) or typeof(blueprint) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(blueprint, ["definition_id", "material_id", "fabrication_energy_joules", "salvage_energy_joules", "name", "materials"]) or not ControlContractValidation.is_id(blueprint["definition_id"]) or not ControlContractValidation.is_id(blueprint["material_id"]) or not _name(blueprint["name"]) or typeof(blueprint["materials"]) != TYPE_DICTIONARY or blueprint["materials"].is_empty() or blueprint["materials"].size() > 32: return false
		for material in blueprint["materials"]:
			if not RemoteProductionProjection.MATERIALS.has(material) or not ControlContractValidation.is_integer(blueprint["materials"][material], 1, 100000000): return false
		for field in ["fabrication_energy_joules", "salvage_energy_joules"]:
			if not ControlContractValidation.is_integer(blueprint[field], 1, 100000): return false
	return true


static func _part(part: Variant, seen: Dictionary) -> bool:
	if typeof(part) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(part, ["schema_version", "part_id", "definition_id", "material_id", "integrity_ppm", "wear_remainder", "name", "material_name"]): return false
	for key in ["part_id", "definition_id", "material_id"]:
		if not ControlContractValidation.is_id(part[key]): return false
	if seen.has(part["part_id"]) or seen.size() >= 512: return false
	seen[part["part_id"]] = true
	return ControlContractValidation.is_integer(part["schema_version"], 1, 1) and ControlContractValidation.is_integer(part["integrity_ppm"], 0, 1000000) and ControlContractValidation.is_integer(part["wear_remainder"], 0, 999) and _name(part["name"]) and _name(part["material_name"])


static func _name(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128


static func _ids(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() > 32: return false
	var seen: Dictionary = {}
	for id in value:
		if not ControlContractValidation.is_id(id) or seen.has(id): return false
		seen[id] = true
	return true
