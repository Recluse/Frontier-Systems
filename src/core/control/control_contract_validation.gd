extends RefCounted
class_name ControlContractValidation

## Shared validation for declarative machine-module and port records.


static func has_exact_fields(record: Dictionary, fields: PackedStringArray) -> bool:
	if record.size() != fields.size():
		return false
	for field in fields:
		if not record.has(field):
			return false
	return true


static func is_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty() and String(value).length() <= 128


## JSON decoders may represent integer-valued numbers as floats.
static func is_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number) and number >= minimum and number <= maximum


static func decode_ids(value: Variant, minimum: int, maximum: int) -> ServiceResult:
	if typeof(value) != TYPE_ARRAY:
		return ServiceResult.failure(&"invalid_module_ids", "Module identifiers must be an array.")
	var values: Array = value
	if values.size() < minimum or values.size() > maximum:
		return ServiceResult.failure(&"module_id_limit", "The identifier list is outside its declared count limits.")
	var ids := PackedStringArray()
	for item in values:
		if not is_id(item) or ids.has(item):
			return ServiceResult.failure(&"invalid_module_id", "Module identifiers must be unique non-empty strings up to 128 characters.")
		ids.append(item)
	return ServiceResult.success(ids)


static func decode_port(value: Variant) -> ServiceResult:
	if typeof(value) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_control_port", "A control port must be a record object.")
	var port: Dictionary = value
	if not has_exact_fields(port, PackedStringArray(["port_id", "direction", "signal_type", "transport"])):
		return ServiceResult.failure(&"invalid_control_port", "A control port has missing or unsupported fields.")
	if (
		not is_id(port["port_id"])
		or not ["input", "output"].has(port["direction"])
		or not ["pulse", "boolean", "number", "message"].has(port["signal_type"])
		or not ["wired", "radio"].has(port["transport"])
	):
		return ServiceResult.failure(&"invalid_control_port", "The port identity, direction, signal type, or transport is invalid.")
	return ServiceResult.success(port.duplicate(true))


## Signal transfer compatibility, separately from physically attaching a cable.
## Adapters must perform signal conversion before a functional route exists.
static func can_connect(source: Dictionary, destination: Dictionary) -> ServiceResult:
	var source_result: ServiceResult = decode_port(source)
	if not source_result.is_success:
		return source_result
	var destination_result: ServiceResult = decode_port(destination)
	if not destination_result.is_success:
		return destination_result
	if source["direction"] != "output" or destination["direction"] != "input":
		return ServiceResult.failure(&"control_port_direction_mismatch", "Connect an output port to an input port.")
	if source["transport"] != destination["transport"]:
		return ServiceResult.failure(&"control_transport_mismatch", "The connected ports use different transports.")
	if source["signal_type"] != destination["signal_type"]:
		return ServiceResult.failure(&"control_signal_type_mismatch", "A converter module is required for different signal types.")
	return ServiceResult.success()


## The prototype's wired ports share an abstract connector. Nonsensical wiring
## may be attached but has no signal route; real connector/rating checks follow.
static func assess_wired_attachment(first: Dictionary, second: Dictionary) -> ServiceResult:
	var first_check: ServiceResult = decode_port(first)
	if not first_check.is_success:
		return first_check
	var second_check: ServiceResult = decode_port(second)
	if not second_check.is_success:
		return second_check
	if first["transport"] != "wired" or second["transport"] != "wired":
		return ServiceResult.failure(&"wired_attachment_transport_mismatch", "A physical wire requires wired endpoints.")
	var forward: ServiceResult = can_connect(first, second)
	var reverse: ServiceResult = can_connect(second, first)
	var route_available: bool = forward.is_success or reverse.is_success
	return ServiceResult.success({
		"physically_connectable": true,
		"signal_route_available": route_available,
		"route_direction": "first_to_second" if forward.is_success else ("second_to_first" if reverse.is_success else "none"),
		"route_error_code": "" if route_available else String(forward.error_code),
	})
