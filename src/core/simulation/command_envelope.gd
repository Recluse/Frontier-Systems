extends RefCounted
class_name CommandEnvelope

## Untrusted client intent. Actor identity and permissions are deliberately absent.

const PROTOCOL_VERSION: int = 1
const MAX_ENCODED_BYTES: int = 65536
const MAX_NESTING_DEPTH: int = 16

var request_id: StringName
var world_id: StringName
var region_id: StringName
var command_type: StringName
var expected_tick_number: int = -1
var payload: Dictionary = {}


static func from_dictionary(record: Dictionary) -> ServiceResult:
	var allowed_keys: Array[String] = [
		"protocol_version",
		"request_id",
		"world_id",
		"region_id",
		"command_type",
		"expected_tick_number",
		"payload",
	]
	for key in record:
		if typeof(key) != TYPE_STRING or not allowed_keys.has(key):
			return ServiceResult.failure(&"unsupported_command_property", "Command intent contains an unsupported property.")

	if typeof(record.get("protocol_version")) != TYPE_INT or record["protocol_version"] != PROTOCOL_VERSION:
		return ServiceResult.failure(&"unsupported_command_protocol", "Command protocol version is not supported.")
	for key in ["request_id", "world_id", "region_id", "command_type"]:
		if typeof(record.get(key)) != TYPE_STRING or String(record[key]).strip_edges().is_empty():
			return ServiceResult.failure(&"invalid_command_identity", "Command identity properties must be non-empty strings.")
		if String(record[key]).to_utf8_buffer().size() > 128:
			return ServiceResult.failure(&"invalid_command_identity", "Command identity property exceeds the size limit.")

	var command_type: String = record["command_type"]
	if command_type.length() > 64:
		return ServiceResult.failure(&"invalid_command_type", "Command type exceeds the size limit.")
	var command_pattern := RegEx.new()
	if command_pattern.compile("^[a-z][a-z0-9_.-]{0,63}$") != OK or command_pattern.search(command_type) == null:
		return ServiceResult.failure(&"invalid_command_type", "Command type must use the registered lowercase identifier format.")

	var expected_tick: int = -1
	if record.has("expected_tick_number"):
		if typeof(record["expected_tick_number"]) != TYPE_INT or int(record["expected_tick_number"]) < 0:
			return ServiceResult.failure(&"invalid_expected_tick", "Expected tick number must be a non-negative integer.")
		expected_tick = int(record["expected_tick_number"])

	var payload_value: Variant = record.get("payload")
	if typeof(payload_value) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_command_payload", "Command payload must be an object.")
	var payload: Dictionary = payload_value
	if payload.size() > 128 or not _is_json_value(payload, 0):
		return ServiceResult.failure(&"invalid_command_payload", "Command payload must be a bounded JSON-compatible object.")

	var envelope := CommandEnvelope.new()
	envelope.request_id = StringName(record["request_id"])
	envelope.world_id = StringName(record["world_id"])
	envelope.region_id = StringName(record["region_id"])
	envelope.command_type = StringName(command_type)
	envelope.expected_tick_number = expected_tick
	envelope.payload = payload.duplicate(true)
	if JSON.stringify(envelope.to_dictionary()).to_utf8_buffer().size() > MAX_ENCODED_BYTES:
		return ServiceResult.failure(&"command_too_large", "Command request exceeds the encoded size limit.")
	return ServiceResult.success(envelope)


static func from_json(json_text: String) -> ServiceResult:
	if json_text.to_utf8_buffer().size() > MAX_ENCODED_BYTES:
		return ServiceResult.failure(&"command_too_large", "Command request exceeds the encoded size limit.")
	var parser := JSON.new()
	var parse_error: Error = parser.parse(json_text)
	if parse_error != OK:
		return ServiceResult.failure(
			&"invalid_command_json",
			"Command request JSON could not be parsed at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		)
	if typeof(parser.data) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_command_json", "Command request JSON must contain an object at the root.")
	return from_dictionary(parser.data)


func to_dictionary() -> Dictionary:
	var record: Dictionary = {
		"protocol_version": PROTOCOL_VERSION,
		"request_id": String(request_id),
		"world_id": String(world_id),
		"region_id": String(region_id),
		"command_type": String(command_type),
		"payload": payload.duplicate(true),
	}
	if expected_tick_number >= 0:
		record["expected_tick_number"] = expected_tick_number
	return record


static func _is_json_value(value: Variant, depth: int) -> bool:
	if depth > MAX_NESTING_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not _is_json_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING or not _is_json_value(value[key], depth + 1):
					return false
			return true
	return false
