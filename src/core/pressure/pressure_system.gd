extends SimulationSystem
class_name PressureSystem

## First isothermal gas network and airlock example for the world simulation.

const SYSTEM_ID: StringName = &"pressure"
const SNAPSHOT_SCHEMA_VERSION: int = 1
const PROTOTYPE_TEMPERATURE_K: float = 293.15
const PROTOTYPE_HABITAT_ID: StringName = &"habitat_main"
const PROTOTYPE_CHAMBER_ID: StringName = &"airlock_chamber"
const PROTOTYPE_EXTERIOR_ID: StringName = &"exterior_reservoir"

var volumes: Dictionary = {}
var airlocks: Dictionary = {}
var sensors: Dictionary = {}
var total_transferred_moles: float = 0.0


func _init() -> void:
	system_id = SYSTEM_ID
	_create_prototype_state()


func simulate_tick(_tick_number: int, fixed_delta: float) -> void:
	for airlock_value in airlocks.values():
		var airlock := airlock_value as AirlockState
		if airlock.equalization_valve_open:
			_step_transfer(
				airlock.habitat_volume_id,
				airlock.chamber_volume_id,
				airlock.equalization_conductance_mol_per_second_kpa,
				fixed_delta
			)
		if airlock.vent_valve_open:
			_step_transfer(
				airlock.chamber_volume_id,
				airlock.exterior_volume_id,
				airlock.vent_conductance_mol_per_second_kpa,
				fixed_delta
			)
	_sample_sensors(_tick_number)


func profiling_counters() -> Dictionary:
	return {"volumes": volumes.size(), "airlocks": airlocks.size(), "sensors": sensors.size(), "total_transferred_moles": total_transferred_moles}


func validate_airlock_action(airlock_id: StringName, action: int) -> ServiceResult:
	var airlock := airlocks.get(airlock_id) as AirlockState
	if airlock == null:
		return ServiceResult.failure(&"unknown_airlock", "The requested airlock does not exist.")
	if action < AirlockState.Action.OPEN_INNER or action > AirlockState.Action.CLOSE_VENT:
		return ServiceResult.failure(&"unknown_airlock_action", "The requested airlock action is not supported.")

	var habitat := volumes.get(airlock.habitat_volume_id) as PressureVolumeState
	var chamber := volumes.get(airlock.chamber_volume_id) as PressureVolumeState
	var exterior := volumes.get(airlock.exterior_volume_id) as PressureVolumeState
	if habitat == null or chamber == null or exterior == null:
		return ServiceResult.failure(&"airlock_volume_missing", "The airlock is missing a connected pressure volume.")

	var inner_difference_kpa: float = absf(habitat.pressure_kpa() - chamber.pressure_kpa())
	var outer_difference_kpa: float = absf(chamber.pressure_kpa() - exterior.pressure_kpa())
	match action:
		AirlockState.Action.OPEN_INNER:
			if airlock.outer_door_open:
				return ServiceResult.failure(&"outer_door_open", "Close the exterior door before opening the habitat door.")
			if airlock.equalization_valve_open or airlock.vent_valve_open:
				return ServiceResult.failure(&"airlock_valve_open", "Close the airlock valves before opening a door.")
			if inner_difference_kpa > AirlockState.MAX_SAFE_DOOR_DIFFERENTIAL_KPA:
				return ServiceResult.failure(&"unsafe_pressure_difference", "Equalize the chamber with the habitat before opening the inner door.")
		AirlockState.Action.OPEN_OUTER:
			if airlock.inner_door_open:
				return ServiceResult.failure(&"inner_door_open", "Close the habitat door before opening the exterior door.")
			if airlock.equalization_valve_open or airlock.vent_valve_open:
				return ServiceResult.failure(&"airlock_valve_open", "Close the airlock valves before opening a door.")
			if outer_difference_kpa > AirlockState.MAX_SAFE_DOOR_DIFFERENTIAL_KPA:
				return ServiceResult.failure(&"unsafe_pressure_difference", "Vent the chamber to the exterior before opening the outer door.")
		AirlockState.Action.OPEN_EQUALIZATION:
			if airlock.inner_door_open or airlock.outer_door_open:
				return ServiceResult.failure(&"airlock_door_open", "Close both airlock doors before equalizing pressure.")
			if airlock.vent_valve_open:
				return ServiceResult.failure(&"vent_valve_open", "Close the vent valve before equalizing with the habitat.")
		AirlockState.Action.OPEN_VENT:
			if airlock.inner_door_open or airlock.outer_door_open:
				return ServiceResult.failure(&"airlock_door_open", "Close both airlock doors before venting the chamber.")
			if airlock.equalization_valve_open:
				return ServiceResult.failure(&"equalization_valve_open", "Close the habitat equalization valve before venting.")

	return ServiceResult.success({"airlock_id": airlock_id, "action": action})


func apply_airlock_action(airlock_id: StringName, action: int) -> ServiceResult:
	var validation := validate_airlock_action(airlock_id, action)
	if not validation.is_success:
		return validation
	var airlock := airlocks[airlock_id] as AirlockState
	match action:
		AirlockState.Action.OPEN_INNER:
			airlock.inner_door_open = true
		AirlockState.Action.CLOSE_INNER:
			airlock.inner_door_open = false
		AirlockState.Action.OPEN_OUTER:
			airlock.outer_door_open = true
		AirlockState.Action.CLOSE_OUTER:
			airlock.outer_door_open = false
		AirlockState.Action.OPEN_EQUALIZATION:
			airlock.equalization_valve_open = true
		AirlockState.Action.CLOSE_EQUALIZATION:
			airlock.equalization_valve_open = false
		AirlockState.Action.OPEN_VENT:
			airlock.vent_valve_open = true
		AirlockState.Action.CLOSE_VENT:
			airlock.vent_valve_open = false

	return ServiceResult.success(_snapshot_airlock(airlock))


func airlock_snapshot(airlock_id: StringName) -> ServiceResult:
	var airlock := airlocks.get(airlock_id) as AirlockState
	if airlock == null:
		return ServiceResult.failure(&"unknown_airlock", "The requested airlock does not exist.")
	return ServiceResult.success(_snapshot_airlock(airlock))


func capture_snapshot() -> ServiceResult:
	if not is_finite(total_transferred_moles) or total_transferred_moles < 0.0:
		return ServiceResult.failure(&"invalid_pressure_system_state", "Transferred gas quantity must be finite and non-negative.")
	var volume_records: Array[Dictionary] = []
	for volume_id in _sorted_ids(volumes):
		var volume := volumes[volume_id] as PressureVolumeState
		if volume == null or not volume.is_valid():
			return ServiceResult.failure(&"invalid_pressure_volume", "The pressure system contains an invalid volume.")
		volume_records.append(volume.to_record())

	var airlock_records: Array[Dictionary] = []
	for airlock_id in _sorted_ids(airlocks):
		var airlock := airlocks[airlock_id] as AirlockState
		if airlock == null:
			return ServiceResult.failure(&"invalid_airlock", "The pressure system contains an invalid airlock.")
		airlock_records.append(airlock.to_record())

	var sensor_records: Array[Dictionary] = []
	for sensor_id in _sorted_ids(sensors):
		var sensor := sensors[sensor_id] as PressureSensorState
		if sensor == null:
			return ServiceResult.failure(&"invalid_pressure_sensor", "The pressure system contains an invalid sensor.")
		sensor_records.append(sensor.to_record())

	return ServiceResult.success({
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"volumes": volume_records,
		"airlocks": airlock_records,
		"sensors": sensor_records,
		"total_transferred_moles": total_transferred_moles,
	})


func validate_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	var decoded: ServiceResult = _decode_snapshot_record(record, snapshot_tick_number)
	if not decoded.is_success:
		return decoded
	return ServiceResult.success()


func restore_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	var decoded: ServiceResult = _decode_snapshot_record(record, snapshot_tick_number)
	if not decoded.is_success:
		return decoded
	var state: Dictionary = decoded.value
	volumes = state["volumes"]
	airlocks = state["airlocks"]
	sensors = state["sensors"]
	total_transferred_moles = state["total_transferred_moles"]
	return ServiceResult.success()


func _step_transfer(first_id: StringName, second_id: StringName, conductance: float, delta_seconds: float) -> void:
	var first := volumes.get(first_id) as PressureVolumeState
	var second := volumes.get(second_id) as PressureVolumeState
	var result := PressureFlowSolver.calculate_transfer(first, second, conductance, delta_seconds)
	if not result.is_valid or result.transferred_moles <= 0.0:
		return
	var source := volumes[result.source_volume_id] as PressureVolumeState
	var receiver := volumes[result.receiver_volume_id] as PressureVolumeState
	source.gas_moles -= result.transferred_moles
	receiver.gas_moles += result.transferred_moles
	total_transferred_moles += result.transferred_moles


func _snapshot_airlock(airlock: AirlockState) -> Dictionary:
	var habitat := volumes[airlock.habitat_volume_id] as PressureVolumeState
	var chamber := volumes[airlock.chamber_volume_id] as PressureVolumeState
	var exterior := volumes[airlock.exterior_volume_id] as PressureVolumeState
	var result: Dictionary = airlock.snapshot(
		habitat.pressure_kpa(),
		chamber.pressure_kpa(),
		exterior.pressure_kpa()
	)
	result["habitat_volume"] = habitat.snapshot()
	result["chamber_volume"] = chamber.snapshot()
	result["exterior_volume"] = exterior.snapshot()
	result["pressure_sensors"] = {
		"habitat": _sensor_for_volume(airlock.habitat_volume_id).snapshot(),
		"chamber": _sensor_for_volume(airlock.chamber_volume_id).snapshot(),
		"exterior": _sensor_for_volume(airlock.exterior_volume_id).snapshot(),
	}
	result["total_transferred_moles"] = total_transferred_moles
	return result


func _sample_sensors(tick_number: int) -> void:
	for sensor_value in sensors.values():
		var sensor := sensor_value as PressureSensorState
		var volume := volumes.get(sensor.volume_id) as PressureVolumeState
		sensor.sample(volume, tick_number)


func _decode_snapshot_record(record: Dictionary, snapshot_tick_number: int) -> ServiceResult:
	if typeof(record.get("schema_version")) != TYPE_INT or record["schema_version"] != SNAPSHOT_SCHEMA_VERSION:
		return ServiceResult.failure(&"unsupported_pressure_system_version", "The pressure-system record version is not supported.")
	var volume_values: Variant = record.get("volumes")
	var airlock_values: Variant = record.get("airlocks")
	var sensor_values: Variant = record.get("sensors")
	var transferred_value: Variant = record.get("total_transferred_moles")
	if typeof(volume_values) != TYPE_ARRAY or typeof(airlock_values) != TYPE_ARRAY or typeof(sensor_values) != TYPE_ARRAY:
		return ServiceResult.failure(&"invalid_pressure_system_record", "Pressure volumes, airlocks, and sensors must be arrays.")
	var volume_records: Array = volume_values
	var airlock_records: Array = airlock_values
	var sensor_records: Array = sensor_values
	if volume_records.is_empty() or airlock_records.is_empty() or sensor_records.is_empty():
		return ServiceResult.failure(&"empty_pressure_system_record", "A pressure system snapshot must include at least one volume, airlock, and sensor.")
	if not _is_number(transferred_value) or not is_finite(float(transferred_value)) or float(transferred_value) < 0.0:
		return ServiceResult.failure(&"invalid_pressure_system_record", "Transferred gas quantity must be finite and non-negative.")

	var decoded_volumes: Dictionary = {}
	for volume_value in volume_records:
		if typeof(volume_value) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_pressure_volume_record", "Each pressure volume must be a record object.")
		var volume_result: ServiceResult = PressureVolumeState.from_record(volume_value)
		if not volume_result.is_success:
			return volume_result
		var volume: PressureVolumeState = volume_result.value
		if decoded_volumes.has(volume.volume_id):
			return ServiceResult.failure(&"duplicate_pressure_volume_id", "Pressure volume IDs must be unique within a system.")
		decoded_volumes[volume.volume_id] = volume

	var decoded_airlocks: Dictionary = {}
	for airlock_value in airlock_records:
		if typeof(airlock_value) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_airlock_record", "Each airlock must be a record object.")
		var airlock_result: ServiceResult = AirlockState.from_record(airlock_value)
		if not airlock_result.is_success:
			return airlock_result
		var airlock: AirlockState = airlock_result.value
		if decoded_airlocks.has(airlock.airlock_id):
			return ServiceResult.failure(&"duplicate_airlock_id", "Airlock IDs must be unique within a system.")
		decoded_airlocks[airlock.airlock_id] = airlock

	var decoded_sensors: Dictionary = {}
	for sensor_value in sensor_records:
		if typeof(sensor_value) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_pressure_sensor_record", "Each pressure sensor must be a record object.")
		var sensor_result: ServiceResult = PressureSensorState.from_record(sensor_value)
		if not sensor_result.is_success:
			return sensor_result
		var sensor: PressureSensorState = sensor_result.value
		if decoded_sensors.has(sensor.sensor_id):
			return ServiceResult.failure(&"duplicate_pressure_sensor_id", "Pressure sensor IDs must be unique within a system.")
		if not decoded_volumes.has(sensor.volume_id):
			return ServiceResult.failure(&"pressure_sensor_volume_missing", "Every sensor must reference a pressure volume in this system.")
		if sensor.last_sampled_tick > snapshot_tick_number:
			return ServiceResult.failure(&"future_pressure_sensor_sample", "A pressure sensor cannot be sampled after the saved world tick.")
		decoded_sensors[sensor.sensor_id] = sensor

	for airlock_value in decoded_airlocks.values():
		var airlock := airlock_value as AirlockState
		if (
			not decoded_volumes.has(airlock.habitat_volume_id)
			or not decoded_volumes.has(airlock.chamber_volume_id)
			or not decoded_volumes.has(airlock.exterior_volume_id)
		):
			return ServiceResult.failure(&"airlock_volume_missing", "Every airlock must reference three saved pressure volumes.")
		if (
			airlock.habitat_volume_id == airlock.chamber_volume_id
			or airlock.habitat_volume_id == airlock.exterior_volume_id
			or airlock.chamber_volume_id == airlock.exterior_volume_id
		):
			return ServiceResult.failure(&"invalid_airlock_topology", "An airlock must connect three distinct pressure volumes.")
		if airlock.inner_door_open and airlock.outer_door_open:
			return ServiceResult.failure(&"unsafe_airlock_snapshot", "An airlock snapshot cannot have both doors open.")
		if (airlock.inner_door_open or airlock.outer_door_open) and (airlock.equalization_valve_open or airlock.vent_valve_open):
			return ServiceResult.failure(&"unsafe_airlock_snapshot", "Airlock valves must be closed while either door is open.")
		if airlock.equalization_valve_open and airlock.vent_valve_open:
			return ServiceResult.failure(&"unsafe_airlock_snapshot", "The equalization and vent valves cannot both be open.")
		var habitat := decoded_volumes[airlock.habitat_volume_id] as PressureVolumeState
		var chamber := decoded_volumes[airlock.chamber_volume_id] as PressureVolumeState
		var exterior := decoded_volumes[airlock.exterior_volume_id] as PressureVolumeState
		if airlock.inner_door_open and absf(habitat.pressure_kpa() - chamber.pressure_kpa()) > AirlockState.MAX_SAFE_DOOR_DIFFERENTIAL_KPA:
			return ServiceResult.failure(&"unsafe_airlock_snapshot", "An open inner door exceeds the permitted pressure differential.")
		if airlock.outer_door_open and absf(chamber.pressure_kpa() - exterior.pressure_kpa()) > AirlockState.MAX_SAFE_DOOR_DIFFERENTIAL_KPA:
			return ServiceResult.failure(&"unsafe_airlock_snapshot", "An open exterior door exceeds the permitted pressure differential.")
		if not _has_sensor_for_volume(decoded_sensors, airlock.habitat_volume_id):
			return ServiceResult.failure(&"airlock_sensor_missing", "Every airlock volume must have a pressure sensor.")
		if not _has_sensor_for_volume(decoded_sensors, airlock.chamber_volume_id):
			return ServiceResult.failure(&"airlock_sensor_missing", "Every airlock volume must have a pressure sensor.")
		if not _has_sensor_for_volume(decoded_sensors, airlock.exterior_volume_id):
			return ServiceResult.failure(&"airlock_sensor_missing", "Every airlock volume must have a pressure sensor.")

	return ServiceResult.success({
		"volumes": decoded_volumes,
		"airlocks": decoded_airlocks,
		"sensors": decoded_sensors,
		"total_transferred_moles": float(transferred_value),
	})


func _sorted_ids(values: Dictionary) -> Array:
	var ids: Array = values.keys()
	ids.sort_custom(_compare_ids)
	return ids


func _compare_ids(left: Variant, right: Variant) -> bool:
	return String(left) < String(right)


func _sensor_for_volume(volume_id: StringName) -> PressureSensorState:
	for sensor_id in _sorted_ids(sensors):
		var sensor := sensors[sensor_id] as PressureSensorState
		if sensor != null and sensor.volume_id == volume_id:
			return sensor
	return null


func _has_sensor_for_volume(sensor_records: Dictionary, volume_id: StringName) -> bool:
	for sensor_value in sensor_records.values():
		var sensor := sensor_value as PressureSensorState
		if sensor != null and sensor.volume_id == volume_id:
			return true
	return false


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _create_prototype_state() -> void:
	var habitat := PressureVolumeState.from_pressure(
		PROTOTYPE_HABITAT_ID,
		1000.0,
		PROTOTYPE_TEMPERATURE_K,
		101.325
	)
	var chamber := PressureVolumeState.from_pressure(
		PROTOTYPE_CHAMBER_ID,
		10.0,
		PROTOTYPE_TEMPERATURE_K,
		0.0
	)
	var exterior := PressureVolumeState.from_pressure(
		PROTOTYPE_EXTERIOR_ID,
		1_000_000_000.0,
		PROTOTYPE_TEMPERATURE_K,
		0.0
	)
	volumes = {
		habitat.volume_id: habitat,
		chamber.volume_id: chamber,
		exterior.volume_id: exterior,
	}
	var habitat_sensor := PressureSensorState.new(&"sensor_habitat", habitat.volume_id)
	var chamber_sensor := PressureSensorState.new(&"sensor_chamber", chamber.volume_id)
	var exterior_sensor := PressureSensorState.new(&"sensor_exterior", exterior.volume_id)
	sensors = {
		habitat_sensor.sensor_id: habitat_sensor,
		chamber_sensor.sensor_id: chamber_sensor,
		exterior_sensor.sensor_id: exterior_sensor,
	}
	_sample_sensors(0)
	var airlock := AirlockState.new(
		&"habitat_airlock",
		PROTOTYPE_HABITAT_ID,
		PROTOTYPE_CHAMBER_ID,
		PROTOTYPE_EXTERIOR_ID
	)
	airlocks[airlock.airlock_id] = airlock
