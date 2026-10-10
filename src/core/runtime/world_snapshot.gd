extends RefCounted
class_name WorldSnapshot

## JSON-compatible, versioned value envelope for one persistent world region.
## System payloads contain domain records only; scene nodes and service objects are excluded.

const SCHEMA_VERSION: int = 1

var world_id: StringName
var region_id: StringName
var tick_number: int
var systems: Dictionary


func _init(
	id: StringName = &"",
	region: StringName = &"",
	tick: int = 0,
	system_records: Dictionary = {}
) -> void:
	world_id = id
	region_id = region
	tick_number = tick
	systems = system_records.duplicate(true)


## Returns detached JSON-compatible values; nested system records are deep-copied.
func to_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"world_id": String(world_id),
		"region_id": String(region_id),
		"tick_number": tick_number,
		"systems": systems.duplicate(true),
	}


## Sorts object keys and preserves full floating-point precision for physical quantities.
func to_json() -> String:
	return JSON.stringify(to_dictionary(), "", true, true)


## Validates the shared envelope before any system-specific record is considered.
static func from_dictionary(record: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "world_id", "region_id", "tick_number", "systems"])):
		return ServiceResult.failure(&"invalid_world_snapshot_fields", "World snapshot fields must match the versioned envelope.")
	var version: Variant = record.get("schema_version")
	if typeof(version) != TYPE_INT or version != SCHEMA_VERSION:
		return ServiceResult.failure(&"unsupported_world_snapshot_version", "The world snapshot schema version is not supported.")

	var world_id_value: Variant = record.get("world_id")
	var region_id_value: Variant = record.get("region_id")
	var tick_value: Variant = record.get("tick_number")
	var systems_value: Variant = record.get("systems")
	if typeof(world_id_value) != TYPE_STRING or String(world_id_value).strip_edges().is_empty():
		return ServiceResult.failure(&"invalid_world_snapshot_identity", "A non-empty world ID is required.")
	if typeof(region_id_value) != TYPE_STRING or String(region_id_value).strip_edges().is_empty():
		return ServiceResult.failure(&"invalid_world_snapshot_identity", "A non-empty region ID is required.")
	if typeof(tick_value) != TYPE_INT or int(tick_value) < 0 or int(tick_value) > 9007199254740990:
		return ServiceResult.failure(&"invalid_world_snapshot_tick", "The snapshot tick number must be a non-negative integer.")
	if typeof(systems_value) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_world_snapshot_systems", "The snapshot must contain a system-record map.")

	var system_records: Dictionary = systems_value
	if system_records.is_empty():
		return ServiceResult.failure(&"invalid_world_snapshot_systems", "A world snapshot must contain at least one simulation-system record.")
	for system_id in system_records:
		if typeof(system_id) != TYPE_STRING or String(system_id).strip_edges().is_empty():
			return ServiceResult.failure(&"invalid_world_snapshot_system_id", "Every snapshot system must have a non-empty string ID.")
		if typeof(system_records[system_id]) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_world_snapshot_system_record", "Every system snapshot must be a record object.")

	var snapshot := WorldSnapshot.new(
		StringName(world_id_value),
		StringName(region_id_value),
		int(tick_value),
		system_records
	)
	return ServiceResult.success(snapshot)


## Parses untrusted snapshot text without mutating a runtime.
static func from_json(json_text: String) -> ServiceResult:
	var parser := JSON.new()
	var parse_error: Error = parser.parse(json_text)
	if parse_error != OK:
		return ServiceResult.failure(
			&"invalid_world_snapshot_json",
			"Snapshot JSON could not be parsed at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		)
	if typeof(parser.data) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_world_snapshot_json", "Snapshot JSON must contain an object at the root.")
	return from_dictionary(_normalize_json_numbers(parser.data))


## Godot JSON numbers may be floats. Restore integral JSON values before strict
## domain decoders inspect integer fields; fractional physical values stay floats.
static func _normalize_json_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0:
		return int(value)
	if typeof(value) == TYPE_DICTIONARY:
		var record: Dictionary = {}
		for key in value:
			record[key] = _normalize_json_numbers(value[key])
		return record
	if typeof(value) == TYPE_ARRAY:
		var items: Array = []
		for item in value:
			items.append(_normalize_json_numbers(item))
		return items
	return value
