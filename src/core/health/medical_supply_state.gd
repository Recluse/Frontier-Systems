extends RefCounted
class_name MedicalSupplyState

## Finite charges for a stable physical item ID. Inventory owns item location.
const MAX_CHARGES: int = 1000
var _record: Dictionary = {}


static func from_record(record: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "supply_id", "definition_id", "state_revision", "last_changed_tick", "charges_remaining"])
	if not ControlContractValidation.has_exact_fields(record, fields) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(record.get("supply_id")) or not ControlContractValidation.is_id(record.get("definition_id")):
		return _failure("An exact versioned supply record with stable item and definition IDs is required.")
	for field in ["state_revision", "last_changed_tick"]:
		if not ControlContractValidation.is_integer(record[field], 0, ConsciousnessState.MAX_INTEGER):
			return _failure("Supply revisions and ticks must be bounded integers.")
	if not ControlContractValidation.is_integer(record["charges_remaining"], 0, MAX_CHARGES) or (int(record["state_revision"]) == 0 and int(record["last_changed_tick"]) != 0) or (int(record["state_revision"]) > 0 and int(record["last_changed_tick"]) == 0):
		return _failure("Finite supply charges and revision timing must be consistent.")
	var state := MedicalSupplyState.new()
	state._record = record.duplicate(true)
	for field in ["schema_version", "state_revision", "last_changed_tick", "charges_remaining"]:
		state._record[field] = int(record[field])
	return ServiceResult.success(state)


func to_record() -> Dictionary:
	return _record.duplicate(true)


## Pure candidate, never a debit. The transaction owner commits both candidates.
func plan_consumption(expected_revision: int, charges: int, tick: int) -> ServiceResult:
	if _record.is_empty() or expected_revision != int(_record["state_revision"]) or expected_revision >= ConsciousnessState.MAX_INTEGER or charges < 1 or charges > MAX_CHARGES or tick <= int(_record["last_changed_tick"]) or tick > ConsciousnessState.MAX_INTEGER:
		return _failure("Consumption requires a current revision, positive charge cost and fresh tick.")
	if charges > int(_record["charges_remaining"]):
		return _failure("The supply has insufficient charges.")
	var before: Dictionary = to_record()
	var after: Dictionary = before.duplicate(true)
	after["charges_remaining"] = int(before["charges_remaining"]) - charges
	after["state_revision"] = expected_revision + 1
	after["last_changed_tick"] = tick
	return ServiceResult.success({"before": before, "after": after, "consumed_charges": charges})


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_medical_supply", message)
