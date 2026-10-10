extends RefCounted
class_name MedicalTreatmentDefinition

## Trusted data, loaded by the server catalog; never accepted from player intent.
var _record: Dictionary = {}


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "definition_id", "revision", "injury_kind", "healing_permille", "charge_cost"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(record.get("definition_id")) or not ControlContractValidation.is_integer(record.get("revision"), 1, ConsciousnessState.MAX_INTEGER) or not BodyInjuryState.KINDS.has(record.get("injury_kind")) or not ControlContractValidation.is_integer(record.get("healing_permille"), 1, 1000) or not ControlContractValidation.is_integer(record.get("charge_cost"), 1, MedicalSupplyState.MAX_CHARGES):
		return ServiceResult.failure(&"invalid_medical_treatment_definition", "An exact bounded localized treatment definition is required.")
	var definition := MedicalTreatmentDefinition.new()
	definition._record = record.duplicate(true)
	for field in ["schema_version", "revision", "healing_permille", "charge_cost"]:
		definition._record[field] = int(record[field])
	return ServiceResult.success(definition)


func to_record() -> Dictionary:
	return _record.duplicate(true)
