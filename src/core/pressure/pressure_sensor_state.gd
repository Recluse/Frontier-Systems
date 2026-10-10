extends RefCounted
class_name PressureSensorState

## Versioned pressure telemetry record for one connected volume.
## The prototype sensor is ideal and samples once per simulation tick.

const SCHEMA_VERSION: int = 1

var sensor_id: StringName
var volume_id: StringName
var pressure_kpa_absolute: float = 0.0
var last_sampled_tick: int = 0
var sample_count: int = 0


func _init(id: StringName = &"", connected_volume_id: StringName = &"") -> void:
	sensor_id = id
	volume_id = connected_volume_id


func sample(volume: PressureVolumeState, tick_number: int) -> void:
	if volume == null or volume.volume_id != volume_id:
		return
	pressure_kpa_absolute = volume.pressure_kpa()
	last_sampled_tick = tick_number
	sample_count += 1


func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"sensor_id": sensor_id,
		"volume_id": volume_id,
		"pressure_kpa_absolute": pressure_kpa_absolute,
		"last_sampled_tick": last_sampled_tick,
		"sample_count": sample_count,
	}


func to_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"sensor_id": String(sensor_id),
		"volume_id": String(volume_id),
		"pressure_kpa_absolute": pressure_kpa_absolute,
		"last_sampled_tick": last_sampled_tick,
		"sample_count": sample_count,
	}


static func from_record(record: Dictionary) -> ServiceResult:
	if typeof(record.get("schema_version")) != TYPE_INT or record["schema_version"] != SCHEMA_VERSION:
		return ServiceResult.failure(&"unsupported_pressure_sensor_version", "The pressure-sensor record version is not supported.")
	var sensor_id_value: Variant = record.get("sensor_id")
	var volume_id_value: Variant = record.get("volume_id")
	var pressure_value: Variant = record.get("pressure_kpa_absolute")
	var sampled_tick_value: Variant = record.get("last_sampled_tick")
	var sample_count_value: Variant = record.get("sample_count")
	if (
		typeof(sensor_id_value) != TYPE_STRING
		or String(sensor_id_value).strip_edges().is_empty()
		or typeof(volume_id_value) != TYPE_STRING
		or String(volume_id_value).strip_edges().is_empty()
	):
		return ServiceResult.failure(&"invalid_pressure_sensor_id", "Pressure sensor and connected volume IDs must be non-empty strings.")
	if not _is_number(pressure_value) or typeof(sampled_tick_value) != TYPE_INT or typeof(sample_count_value) != TYPE_INT:
		return ServiceResult.failure(&"invalid_pressure_sensor_state", "Pressure sensor readings and counters have invalid types.")
	var pressure_kpa: float = float(pressure_value)
	if (
		not is_finite(pressure_kpa)
		or pressure_kpa < 0.0
		or int(sampled_tick_value) < 0
		or int(sample_count_value) < 0
	):
		return ServiceResult.failure(&"invalid_pressure_sensor_state", "Pressure sensor readings and counters must be non-negative and finite.")
	var sensor := PressureSensorState.new(StringName(sensor_id_value), StringName(volume_id_value))
	sensor.pressure_kpa_absolute = pressure_kpa
	sensor.last_sampled_tick = int(sampled_tick_value)
	sensor.sample_count = int(sample_count_value)
	return ServiceResult.success(sensor)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
