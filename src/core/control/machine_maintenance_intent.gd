extends RefCounted
class_name MachineMaintenanceIntent

## Closed maintenance vocabulary. Identity, grants and definitions are server-owned.
const FIELDS: Dictionary = {
	"isolate": [], "restore_power": [],
	"remove": ["instance_id"], "install": ["instance_id", "slot_id"],
	"attach_wire": ["wire_id", "first_module", "first_port", "second_module", "second_port"],
	"detach_wire": ["wire_id"],
	"replace_board": ["target_board_id"], "resume_board_job": [], "cancel_board_job": [],
}

var operation: String = ""
var parameters: Dictionary = {}


func to_record() -> Dictionary:
	return {"schema_version": 2, "operation": operation, "parameters": parameters.duplicate(true)}


static func from_record(record: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "operation", "parameters"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 2):
		return ServiceResult.failure(&"invalid_maintenance_intent", "A versioned maintenance intent is required.")
	if typeof(record["operation"]) != TYPE_STRING or not FIELDS.has(record["operation"]) or typeof(record["parameters"]) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"unknown_maintenance_operation", "The operation or parameters are invalid.")
	if int(record["schema_version"]) == 1 and record["operation"] in ["replace_board", "resume_board_job", "cancel_board_job"]:
		return ServiceResult.failure(&"unsupported_maintenance_operation", "Board jobs require maintenance intent v2.")
	var fields := PackedStringArray(FIELDS[record["operation"]])
	if not ControlContractValidation.has_exact_fields(record["parameters"], fields):
		return ServiceResult.failure(&"invalid_maintenance_parameters", "Parameters must match the selected operation exactly.")
	for field in fields:
		if not ControlContractValidation.is_id(record["parameters"][field]):
			return ServiceResult.failure(&"invalid_maintenance_id", "Maintenance endpoints must be stable IDs.")
	var intent := MachineMaintenanceIntent.new()
	intent.operation = record["operation"]
	intent.parameters = record["parameters"].duplicate(true)
	return ServiceResult.success(intent)
