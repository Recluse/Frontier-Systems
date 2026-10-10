extends RefCounted
class_name MachineFunctionRequirement

## Component requirements for one function; missing parts disable only that function.
## Tools, locks, load, and permissions remain live action-system preconditions.

const SCHEMA_VERSION: int = 1

var function_id: String = ""
var required_component_capabilities := PackedStringArray()


func to_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"function_id": function_id,
		"required_component_capabilities": Array(required_component_capabilities),
	}


func evaluate(available_component_capabilities: PackedStringArray) -> ServiceResult:
	var validation: ServiceResult = from_record(to_record())
	if not validation.is_success:
		return validation
	var missing := PackedStringArray()
	for capability in required_component_capabilities:
		if not available_component_capabilities.has(capability):
			missing.append(capability)
	return ServiceResult.success({
		"function_id": function_id,
		"available": missing.is_empty(),
		"missing_component_capabilities": Array(missing),
	})


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "function_id", "required_component_capabilities"])
	if not ControlContractValidation.has_exact_fields(record, fields):
		return ServiceResult.failure(&"invalid_machine_function", "The function requirement has missing or unsupported fields.")
	if not ControlContractValidation.is_integer(record["schema_version"], SCHEMA_VERSION, SCHEMA_VERSION):
		return ServiceResult.failure(&"unsupported_machine_function_version", "The function requirement schema version is not supported.")
	if not ControlContractValidation.is_id(record["function_id"]):
		return ServiceResult.failure(&"invalid_machine_function_id", "A function requires a stable non-empty ID.")
	var capabilities: ServiceResult = ControlContractValidation.decode_ids(record["required_component_capabilities"], 0, 64)
	if not capabilities.is_success:
		return capabilities
	var requirement := MachineFunctionRequirement.new()
	requirement.function_id = record["function_id"]
	requirement.required_component_capabilities = capabilities.value
	return ServiceResult.success(requirement)
