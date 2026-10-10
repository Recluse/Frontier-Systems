extends RefCounted
class_name LinearMotionState

## Exact linear momentum contract; derived velocities are floating-point observations.
const MAX_MOMENTUM_MICRO_NS: int = 1000000000000
const MAX_EXACT_INTEGER: int = 9007199254740990
const MAX_MASS_MILLIGRAMS: int = 1000000000000
const MAX_LOCAL_SPEED_M_S: float = 10000.0
var _record: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


func velocity_m_s() -> Array:
	var mass: float = float(_record["mass_milligrams"])
	var momentum: Array = _record["linear_momentum_micro_ns"]
	return [float(momentum[0]) / mass, float(momentum[1]) / mass, float(momentum[2]) / mass]


static func from_record(record: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "body_id", "frame_id", "state_revision", "mass_milligrams", "linear_momentum_micro_ns"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(record.get("body_id")) or not ControlContractValidation.is_id(record.get("frame_id")) or not ControlContractValidation.is_integer(record.get("state_revision"), 0, MAX_EXACT_INTEGER) or not ControlContractValidation.is_integer(record.get("mass_milligrams"), 1, MAX_MASS_MILLIGRAMS) or not vector_valid(record.get("linear_momentum_micro_ns"), MAX_MOMENTUM_MICRO_NS):
		return ServiceResult.failure(&"invalid_linear_motion", "A complete bounded mass/momentum record is required.")
	var state := LinearMotionState.new()
	state._record = record.duplicate(true)
	state._record["schema_version"] = 1
	state._record["state_revision"] = int(record["state_revision"])
	state._record["mass_milligrams"] = int(record["mass_milligrams"])
	for index in range(3):
		state._record["linear_momentum_micro_ns"][index] = int(record["linear_momentum_micro_ns"][index])
	var speed_squared: float = 0.0
	for component in state.velocity_m_s():
		speed_squared += component * component
	if speed_squared > MAX_LOCAL_SPEED_M_S * MAX_LOCAL_SPEED_M_S:
		return ServiceResult.failure(&"invalid_linear_motion", "Local-frame speed exceeds prototype limits.")
	return ServiceResult.success(state)


static func vector_valid(value: Variant, bound: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for component in value:
		if not ControlContractValidation.is_integer(component, -bound, bound):
			return false
	return true
