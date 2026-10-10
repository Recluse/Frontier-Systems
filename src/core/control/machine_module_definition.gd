extends RefCounted
class_name MachineModuleDefinition

## Declarative module capabilities. A handler ID never loads executable content.

const SCHEMA_VERSION: int = 1

var definition_id: String = ""
var revision: int = 1
var module_family: String = ""
var interface_id: String = ""
var size_units: int = 1
var idle_power_watts: float = 0.0
var required_host_capabilities := PackedStringArray()
var ports: Array[Dictionary] = []
var handler_id: String = ""


func to_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"definition_id": definition_id,
		"revision": revision,
		"module_family": module_family,
		"interface_id": interface_id,
		"size_units": size_units,
		"idle_power_watts": idle_power_watts,
		"required_host_capabilities": Array(required_host_capabilities),
		"ports": ports.duplicate(true),
		"handler_id": handler_id,
	}


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray([
		"schema_version", "definition_id", "revision", "module_family", "interface_id",
		"size_units", "idle_power_watts", "required_host_capabilities", "ports", "handler_id",
	])
	if not ControlContractValidation.has_exact_fields(record, fields):
		return ServiceResult.failure(&"invalid_module_definition", "The module definition has missing or unsupported fields.")
	if not ControlContractValidation.is_integer(record["schema_version"], SCHEMA_VERSION, SCHEMA_VERSION):
		return ServiceResult.failure(&"unsupported_module_version", "The module definition schema version is not supported.")
	for field in ["definition_id", "module_family", "interface_id", "handler_id"]:
		if not ControlContractValidation.is_id(record[field]):
			return ServiceResult.failure(&"invalid_module_identity", "Module identities must be non-empty strings up to 128 characters.")
	if not ControlContractValidation.is_integer(record["revision"], 1, 9007199254740991):
		return ServiceResult.failure(&"invalid_module_revision", "A module definition requires a positive integer revision.")
	if not ControlContractValidation.is_integer(record["size_units"], 1, 1024):
		return ServiceResult.failure(&"invalid_module_size", "Module size must be between one and 1,024 units.")
	var power_value: Variant = record["idle_power_watts"]
	if typeof(power_value) != TYPE_INT and typeof(power_value) != TYPE_FLOAT:
		return ServiceResult.failure(&"invalid_module_power", "Module power demand must be numeric.")
	var power: float = float(power_value)
	if not is_finite(power) or power < 0.0:
		return ServiceResult.failure(&"invalid_module_power", "Module power demand must be finite and non-negative.")
	var capabilities: ServiceResult = ControlContractValidation.decode_ids(record["required_host_capabilities"], 0, 64)
	if not capabilities.is_success:
		return capabilities
	if typeof(record["ports"]) != TYPE_ARRAY or record["ports"].size() > 32:
		return ServiceResult.failure(&"invalid_module_ports", "A module definition may contain at most 32 ports.")
	var module := MachineModuleDefinition.new()
	module.definition_id = record["definition_id"]
	module.revision = int(record["revision"])
	module.module_family = record["module_family"]
	module.interface_id = record["interface_id"]
	module.size_units = int(record["size_units"])
	module.idle_power_watts = power
	module.required_host_capabilities = capabilities.value
	module.handler_id = record["handler_id"]
	var seen_ports: Dictionary = {}
	for port_value in record["ports"]:
		var decoded: ServiceResult = ControlContractValidation.decode_port(port_value)
		if not decoded.is_success:
			return decoded
		var port: Dictionary = decoded.value
		if seen_ports.has(port["port_id"]):
			return ServiceResult.failure(&"duplicate_module_port", "Port IDs must be unique within a module definition.")
		seen_ports[port["port_id"]] = true
		module.ports.append(port)
	return ServiceResult.success(module)
