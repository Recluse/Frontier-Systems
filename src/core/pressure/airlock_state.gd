extends RefCounted
class_name AirlockState

## Stateful doors and valves for a three-volume pressure airlock.

enum Action {
	OPEN_INNER,
	CLOSE_INNER,
	OPEN_OUTER,
	CLOSE_OUTER,
	OPEN_EQUALIZATION,
	CLOSE_EQUALIZATION,
	OPEN_VENT,
	CLOSE_VENT,
}

const MAX_SAFE_DOOR_DIFFERENTIAL_KPA: float = 2.0
const SCHEMA_VERSION: int = 1

var airlock_id: StringName
var habitat_volume_id: StringName
var chamber_volume_id: StringName
var exterior_volume_id: StringName
var inner_door_open: bool = false
var outer_door_open: bool = false
var equalization_valve_open: bool = false
var vent_valve_open: bool = false
var equalization_conductance_mol_per_second_kpa: float = 0.8
var vent_conductance_mol_per_second_kpa: float = 1.2


func _init(
	id: StringName = &"",
	habitat_id: StringName = &"",
	chamber_id: StringName = &"",
	exterior_id: StringName = &""
) -> void:
	airlock_id = id
	habitat_volume_id = habitat_id
	chamber_volume_id = chamber_id
	exterior_volume_id = exterior_id


func snapshot(habitat_pressure_kpa: float, chamber_pressure_kpa: float, exterior_pressure_kpa: float) -> Dictionary:
	return {
		"airlock_id": airlock_id,
		"inner_door_open": inner_door_open,
		"outer_door_open": outer_door_open,
		"equalization_valve_open": equalization_valve_open,
		"vent_valve_open": vent_valve_open,
		"habitat_pressure_kpa_absolute": habitat_pressure_kpa,
		"chamber_pressure_kpa_absolute": chamber_pressure_kpa,
		"exterior_pressure_kpa_absolute": exterior_pressure_kpa,
		"inner_pressure_difference_kpa": absf(habitat_pressure_kpa - chamber_pressure_kpa),
		"outer_pressure_difference_kpa": absf(chamber_pressure_kpa - exterior_pressure_kpa),
		"safe_door_pressure_difference_kpa": MAX_SAFE_DOOR_DIFFERENTIAL_KPA,
	}


func to_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"airlock_id": String(airlock_id),
		"habitat_volume_id": String(habitat_volume_id),
		"chamber_volume_id": String(chamber_volume_id),
		"exterior_volume_id": String(exterior_volume_id),
		"inner_door_open": inner_door_open,
		"outer_door_open": outer_door_open,
		"equalization_valve_open": equalization_valve_open,
		"vent_valve_open": vent_valve_open,
		"equalization_conductance_mol_per_second_kpa": equalization_conductance_mol_per_second_kpa,
		"vent_conductance_mol_per_second_kpa": vent_conductance_mol_per_second_kpa,
	}


static func from_record(record: Dictionary) -> ServiceResult:
	if typeof(record.get("schema_version")) != TYPE_INT or record["schema_version"] != SCHEMA_VERSION:
		return ServiceResult.failure(&"unsupported_airlock_version", "The airlock record version is not supported.")
	var id_values: Array = [
		record.get("airlock_id"),
		record.get("habitat_volume_id"),
		record.get("chamber_volume_id"),
		record.get("exterior_volume_id"),
	]
	for id_value in id_values:
		if typeof(id_value) != TYPE_STRING or String(id_value).strip_edges().is_empty():
			return ServiceResult.failure(&"invalid_airlock_id", "Airlock and connected volume IDs must be non-empty strings.")
	for state_key in ["inner_door_open", "outer_door_open", "equalization_valve_open", "vent_valve_open"]:
		if typeof(record.get(state_key)) != TYPE_BOOL:
			return ServiceResult.failure(&"invalid_airlock_state", "Airlock door and valve states must be boolean.")
	var equalization_value: Variant = record.get("equalization_conductance_mol_per_second_kpa")
	var vent_value: Variant = record.get("vent_conductance_mol_per_second_kpa")
	if not _is_number(equalization_value) or not _is_number(vent_value):
		return ServiceResult.failure(&"invalid_airlock_conductance", "Airlock conductances must be numeric.")
	var equalization_conductance: float = float(equalization_value)
	var vent_conductance: float = float(vent_value)
	if (
		not is_finite(equalization_conductance)
		or equalization_conductance < 0.0
		or not is_finite(vent_conductance)
		or vent_conductance < 0.0
	):
		return ServiceResult.failure(&"invalid_airlock_conductance", "Airlock conductances must be finite and non-negative.")

	var airlock := AirlockState.new(
		StringName(id_values[0]),
		StringName(id_values[1]),
		StringName(id_values[2]),
		StringName(id_values[3])
	)
	airlock.inner_door_open = record["inner_door_open"]
	airlock.outer_door_open = record["outer_door_open"]
	airlock.equalization_valve_open = record["equalization_valve_open"]
	airlock.vent_valve_open = record["vent_valve_open"]
	airlock.equalization_conductance_mol_per_second_kpa = equalization_conductance
	airlock.vent_conductance_mol_per_second_kpa = vent_conductance
	return ServiceResult.success(airlock)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
