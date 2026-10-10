extends RefCounted
class_name OverlaySectionProfile

## Ordered presentation sections only; no arbitrary nodes or action bindings.
var _record: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


static func from_record(record: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "definition_id", "display_name", "sections"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return ServiceResult.failure(&"invalid_overlay_sections", "A complete versioned section profile is required.")
	if not ControlContractValidation.is_id(record["definition_id"]) or not ControlContractValidation.is_id(record["display_name"]) or typeof(record["sections"]) != TYPE_ARRAY or record["sections"].is_empty() or record["sections"].size() > 16:
		return ServiceResult.failure(&"invalid_overlay_sections", "Section identity and bounded entries are required.")
	var ids := PackedStringArray()
	for raw in record["sections"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_overlay_section", "Each section must be a record.")
		var section: Dictionary = raw
		if not ControlContractValidation.has_exact_fields(section, PackedStringArray(["section_id", "collapsed"])) or not ControlContractValidation.is_id(section.get("section_id")) or typeof(section.get("collapsed")) != TYPE_BOOL or ids.has(section["section_id"]):
			return ServiceResult.failure(&"invalid_overlay_section", "Section IDs must be unique and collapse flags boolean.")
		ids.append(section["section_id"])
	var profile := OverlaySectionProfile.new()
	profile._record = record.duplicate(true)
	return ServiceResult.success(profile)
