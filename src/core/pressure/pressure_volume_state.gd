extends RefCounted
class_name PressureVolumeState

## Isothermal gas state for one fixed-volume compartment.
## Pressure is absolute kPa; gas quantity is mol; volume is cubic metres.

const SCHEMA_VERSION: int = 1
const GAS_CONSTANT_J_PER_MOL_K: float = 8.314462618

var volume_id: StringName
var volume_m3: float
var temperature_kelvin: float
var gas_moles: float


func _init(
	id: StringName = &"",
	volume: float = 1.0,
	temperature: float = 293.15,
	initial_gas_moles: float = 0.0
) -> void:
	volume_id = id
	volume_m3 = volume
	temperature_kelvin = temperature
	gas_moles = initial_gas_moles


static func from_pressure(
	id: StringName,
	volume: float,
	temperature: float,
	pressure_kpa: float
) -> PressureVolumeState:
	var moles: float = pressure_kpa * 1000.0 * volume / (GAS_CONSTANT_J_PER_MOL_K * temperature)
	return PressureVolumeState.new(id, volume, temperature, moles)


func pressure_kpa() -> float:
	if volume_m3 <= 0.0 or temperature_kelvin <= 0.0 or gas_moles <= 0.0:
		return 0.0
	return gas_moles * GAS_CONSTANT_J_PER_MOL_K * temperature_kelvin / volume_m3 / 1000.0


func is_valid() -> bool:
	return (
		volume_id != &""
		and is_finite(volume_m3)
		and volume_m3 > 0.0
		and is_finite(temperature_kelvin)
		and temperature_kelvin > 0.0
		and is_finite(gas_moles)
		and gas_moles >= 0.0
		and is_finite(pressure_kpa())
	)


func to_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"volume_id": String(volume_id),
		"volume_m3": volume_m3,
		"temperature_kelvin": temperature_kelvin,
		"gas_moles": gas_moles,
	}


func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"volume_id": volume_id,
		"volume_m3": volume_m3,
		"temperature_kelvin": temperature_kelvin,
		"gas_moles": gas_moles,
		"pressure_kpa_absolute": pressure_kpa(),
	}


static func from_record(record: Dictionary) -> ServiceResult:
	if typeof(record.get("schema_version")) != TYPE_INT or record["schema_version"] != SCHEMA_VERSION:
		return ServiceResult.failure(&"unsupported_pressure_volume_version", "The pressure-volume record version is not supported.")
	var id_value: Variant = record.get("volume_id")
	var volume_value: Variant = record.get("volume_m3")
	var temperature_value: Variant = record.get("temperature_kelvin")
	var moles_value: Variant = record.get("gas_moles")
	if typeof(id_value) != TYPE_STRING or String(id_value).strip_edges().is_empty():
		return ServiceResult.failure(&"invalid_pressure_volume_id", "A non-empty pressure-volume ID is required.")
	if not _is_number(volume_value) or not _is_number(temperature_value) or not _is_number(moles_value):
		return ServiceResult.failure(&"invalid_pressure_volume_value", "Volume, temperature, and gas quantity must be numeric.")

	var volume := PressureVolumeState.new(
		StringName(id_value),
		float(volume_value),
		float(temperature_value),
		float(moles_value)
	)
	if not volume.is_valid():
		return ServiceResult.failure(&"invalid_pressure_volume_value", "The pressure-volume record contains an invalid physical value.")
	return ServiceResult.success(volume)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
