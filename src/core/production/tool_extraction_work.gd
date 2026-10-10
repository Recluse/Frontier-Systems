extends RefCounted
class_name ToolExtractionWork

## Persisted, bounded work binding. Production owns its reserved material.
const CYCLE_TICKS: int = 60
const CYCLE_MASS: int = 1000000
const MAX_CYCLES: int = 10
const REASONS: Array[String] = ["", "capability", "carrier", "power", "energy", "capacity", "restart"]


static func valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not ToolComponentCatalog.exact(value, ["request_id", "principal_id", "tool_id", "carrier_id", "deposit_id", "remaining_cycles", "completed_cycles", "status", "pause_reason"]): return false
	for field in ["request_id", "principal_id", "tool_id", "carrier_id", "deposit_id"]:
		if not ControlContractValidation.is_id(value[field]): return false
	return ControlContractValidation.is_integer(value["remaining_cycles"], 1, MAX_CYCLES) and ControlContractValidation.is_integer(value["completed_cycles"], 0, MAX_CYCLES - 1) and int(value["remaining_cycles"]) + int(value["completed_cycles"]) <= MAX_CYCLES and value["status"] in ["running", "paused"] and value["pause_reason"] in REASONS and ((value["status"] == "running") == (value["pause_reason"] == ""))


static func context(record: Dictionary, world_id: StringName, region_id: StringName) -> AuthenticatedCommandContext:
	# The prototype host binds fixed invite principals with inventory.operate.
	# Never restore client-provided grants; public identity integration replaces this adapter.
	return AuthenticatedCommandContext.for_local_development(StringName(record["principal_id"]), world_id, region_id)
