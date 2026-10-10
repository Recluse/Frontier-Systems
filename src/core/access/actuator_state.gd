extends RefCounted
class_name ActuatorState

## Reusable physical actuator state for access-controlled equipment.

const SCHEMA_VERSION: int = 1
const MODES := ["powered", "manual", "disabled", "jammed"]
const LATCH_STATES := ["engaged", "released", "damaged"]

var actuator_id: StringName
var mode: StringName = &"powered"
var position: float = 0.0
var latch_state: StringName = &"engaged"
var seal_condition: float = 1.0
var integrity: float = 1.0
var maximum_force_newtons: float = 0.0
var effective_pressure_area_m2: float = 0.0
var manual_override_available: bool = false
var override_actor_id: StringName = &""
var override_route: StringName = &""
var override_expires_tick: int = -1


func to_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"actuator_id": String(actuator_id),
		"mode": String(mode),
		"position": position,
		"latch_state": String(latch_state),
		"seal_condition": seal_condition,
		"integrity": integrity,
		"maximum_force_newtons": maximum_force_newtons,
		"effective_pressure_area_m2": effective_pressure_area_m2,
		"manual_override_available": manual_override_available,
		"override_actor_id": String(override_actor_id),
		"override_route": String(override_route),
		"override_expires_tick": override_expires_tick,
	}


func is_valid() -> bool:
	return (
		not String(actuator_id).strip_edges().is_empty()
		and MODES.has(String(mode))
		and LATCH_STATES.has(String(latch_state))
		and is_finite(position) and position >= 0.0 and position <= 1.0
		and is_finite(seal_condition) and seal_condition >= 0.0 and seal_condition <= 1.0
		and is_finite(integrity) and integrity >= 0.0 and integrity <= 1.0
		and is_finite(maximum_force_newtons) and maximum_force_newtons >= 0.0
		and is_finite(effective_pressure_area_m2) and effective_pressure_area_m2 >= 0.0
		and override_expires_tick >= -1
	)


func authorizes_actor(actor_id: StringName, tick_number: int) -> bool:
	return (
		not String(actor_id).strip_edges().is_empty()
		and actor_id == override_actor_id
		and override_expires_tick >= tick_number
		and override_route in [&"electrical", &"mechanical", &"combined"]
	)


static func from_record(record: Dictionary) -> ServiceResult:
	if typeof(record.get("schema_version")) != TYPE_INT or record["schema_version"] != SCHEMA_VERSION:
		return ServiceResult.failure(&"unsupported_actuator_version", "The actuator record version is not supported.")
	if record.size() != 13:
		return ServiceResult.failure(&"invalid_actuator_record", "The actuator record has missing or unsupported fields.")
	var actuator := ActuatorState.new()
	var string_fields := ["actuator_id", "mode", "latch_state", "override_actor_id", "override_route"]
	for field_name in string_fields:
		if typeof(record.get(field_name)) != TYPE_STRING:
			return ServiceResult.failure(&"invalid_actuator_record", "Actuator string fields must be strings.")
	actuator.actuator_id = StringName(record["actuator_id"])
	actuator.mode = StringName(record["mode"])
	actuator.latch_state = StringName(record["latch_state"])
	actuator.override_actor_id = StringName(record["override_actor_id"])
	actuator.override_route = StringName(record["override_route"])
	var numeric_fields := {
		"position": "position",
		"seal_condition": "seal_condition",
		"integrity": "integrity",
		"maximum_force_newtons": "maximum_force_newtons",
		"effective_pressure_area_m2": "effective_pressure_area_m2",
	}
	for record_key in numeric_fields:
		var field_value: Variant = record.get(record_key)
		if typeof(field_value) != TYPE_INT and typeof(field_value) != TYPE_FLOAT:
			return ServiceResult.failure(&"invalid_actuator_record", "Actuator physical limits must be numeric.")
		actuator.set(numeric_fields[record_key], float(field_value))
	var manual_value: Variant = record.get("manual_override_available")
	var expiry_value: Variant = record.get("override_expires_tick")
	if typeof(manual_value) != TYPE_BOOL or typeof(expiry_value) != TYPE_INT:
		return ServiceResult.failure(&"invalid_actuator_record", "Actuator override availability and expiry must have valid types.")
	actuator.manual_override_available = manual_value
	actuator.override_expires_tick = expiry_value
	if not actuator.is_valid():
		return ServiceResult.failure(&"invalid_actuator_record", "Actuator state is outside its supported range.")
	if not MODES.has(String(actuator.mode)) or not LATCH_STATES.has(String(actuator.latch_state)):
		return ServiceResult.failure(&"invalid_actuator_record", "Actuator mode or latch state is not supported.")
	if actuator.override_route != &"" and actuator.override_route not in [&"electrical", &"mechanical", &"combined"]:
		return ServiceResult.failure(&"invalid_actuator_record", "Actuator override route is not supported.")
	if (
		(String(actuator.override_actor_id).is_empty() and (actuator.override_route != &"" or actuator.override_expires_tick != -1))
		or (not String(actuator.override_actor_id).is_empty() and (actuator.override_route == &"" or actuator.override_expires_tick < 0))
	):
		return ServiceResult.failure(&"invalid_actuator_record", "Actuator override actor, route, and expiry must be present together.")
	return ServiceResult.success(actuator)
