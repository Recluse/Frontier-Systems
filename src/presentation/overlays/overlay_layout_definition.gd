extends RefCounted
class_name OverlayLayoutDefinition

## Layouts arrange registered panels; they cannot instantiate resources or bind actions.
var _record: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "definition_id", "display_name", "orientation", "panel_ids", "leading_weight", "spacing"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return ServiceResult.failure(&"invalid_overlay_layout", "A complete versioned layout record is required.")
	if not ControlContractValidation.is_id(record["definition_id"]) or not ControlContractValidation.is_id(record["display_name"]) or record["orientation"] not in ["horizontal", "vertical"]:
		return ServiceResult.failure(&"invalid_overlay_layout_identity", "Layout identity and orientation must be valid.")
	var ids: ServiceResult = ControlContractValidation.decode_ids(record["panel_ids"], 2, 2)
	if not ids.is_success:
		return ids
	var weight: Variant = record["leading_weight"]
	if (typeof(weight) != TYPE_FLOAT and typeof(weight) != TYPE_INT) or not is_finite(float(weight)) or float(weight) < 0.25 or float(weight) > 0.75 or not ControlContractValidation.is_integer(record["spacing"], 4, 24):
		return ServiceResult.failure(&"invalid_overlay_layout_dimensions", "Layout weight and spacing must be bounded.")
	var definition := OverlayLayoutDefinition.new()
	definition._record = record.duplicate(true)
	return ServiceResult.success(definition)
