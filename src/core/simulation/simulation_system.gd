extends Node
class_name SimulationSystem

## Base class for deterministic, server-authoritative systems executed per physics tick.

@export var system_id: StringName
@export var tick_priority: int = 0


func simulate_tick(_tick_number: int, _fixed_delta: float) -> void:
	pass


## Optional bounded numeric counters. Called only while history capture is enabled.
## Implementations must not perform I/O or mutate canonical state.
func profiling_counters() -> Dictionary:
	return {}


func capture_snapshot() -> ServiceResult:
	return ServiceResult.failure(&"snapshot_not_supported", "This simulation system does not implement snapshots.")


func validate_snapshot_record(_record: Dictionary, _snapshot_tick_number: int) -> ServiceResult:
	return ServiceResult.failure(&"snapshot_not_supported", "This simulation system cannot restore snapshots.")


func restore_snapshot_record(_record: Dictionary, _snapshot_tick_number: int) -> ServiceResult:
	return ServiceResult.failure(&"snapshot_not_supported", "This simulation system cannot restore snapshots.")
