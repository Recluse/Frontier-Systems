extends RefCounted
class_name MachineModuleInstance

## Salvageable installed part. The circuit owns instances and returns detached records.
const SCHEMA_VERSION: int = 1

var instance_id: String = ""
var slot_id: String = ""
var definition: MachineModuleDefinition
var integrity: float = 1.0


func to_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"instance_id": instance_id,
		"slot_id": slot_id,
		"definition_id": definition.definition_id,
		"definition_revision": definition.revision,
		"integrity": integrity,
	}


## Used for salvage restore; definitions resolve from a trusted pinned catalog.
static func from_record(record: Dictionary, catalog: MachineModuleRegistry) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "instance_id", "slot_id", "definition_id", "definition_revision", "integrity"])
	if catalog == null or not ControlContractValidation.has_exact_fields(record, fields):
		return ServiceResult.failure(&"invalid_module_instance", "A complete module inspection record and catalog are required.")
	if not ControlContractValidation.is_integer(record["schema_version"], 1, 1) or not ControlContractValidation.is_integer(record["definition_revision"], 1, 9007199254740991):
		return ServiceResult.failure(&"invalid_instance_version", "Instance and definition versions must be supported integers.")
	for field in ["instance_id", "slot_id", "definition_id"]:
		if not ControlContractValidation.is_id(record[field]):
			return ServiceResult.failure(&"invalid_instance_id", "Module IDs must be stable strings.")
	var integrity_value: Variant = record["integrity"]
	if typeof(integrity_value) != TYPE_INT and typeof(integrity_value) != TYPE_FLOAT:
		return ServiceResult.failure(&"invalid_instance_integrity", "Integrity must be numeric.")
	var condition: float = float(integrity_value)
	if not is_finite(condition) or condition < 0.0 or condition > 1.0:
		return ServiceResult.failure(&"invalid_instance_integrity", "Integrity must be finite and between zero and one.")
	var definition_result: ServiceResult = catalog.get_definition(record["definition_id"], int(record["definition_revision"]))
	if not definition_result.is_success:
		return definition_result
	var instance := MachineModuleInstance.new()
	instance.instance_id = record["instance_id"]
	instance.slot_id = record["slot_id"]
	instance.definition = definition_result.value
	instance.integrity = condition
	return ServiceResult.success(instance)
