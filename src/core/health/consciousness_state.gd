extends RefCounted
class_name ConsciousnessState

## Detached canonical consciousness record. Does not represent death or posture.
const MAX_INTEGER: int = 9007199254740990
const MAX_CAUSES: int = 16
const KINDS: Array[String] = ["injury", "chemical", "oxygen_delivery", "circulation", "temperature"]
var _record: Dictionary = {}


func to_record() -> Dictionary:
	return _record.duplicate(true)


static func create_alert(body_id: String) -> ServiceResult:
	return from_record({"schema_version": 1, "body_id": body_id, "state_revision": 0,
		"state": "alert", "last_assessed_tick": 0, "transition_tick": 0,
		"recovery_since_tick": -1, "causes": []})


static func decode_causes(value: Variant) -> ServiceResult:
	if typeof(value) != TYPE_ARRAY or value.size() > MAX_CAUSES:
		return ServiceResult.failure(&"invalid_consciousness_causes", "At most sixteen trusted cause records are supported.")
	var decoded: Array = []
	var ids: Dictionary = {}
	for entry in value:
		if typeof(entry) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(entry, PackedStringArray(["cause_id", "kind", "suppression_permille"])):
			return ServiceResult.failure(&"invalid_consciousness_cause", "A cause requires exact identity, kind and suppression fields.")
		if not ControlContractValidation.is_id(entry["cause_id"]) or ids.has(entry["cause_id"]) or not KINDS.has(entry["kind"]) or not ControlContractValidation.is_integer(entry["suppression_permille"], 0, 1000):
			return ServiceResult.failure(&"invalid_consciousness_cause", "Cause IDs must be unique and suppression bounded integral permille.")
		ids[entry["cause_id"]] = true
		decoded.append({"cause_id": entry["cause_id"], "kind": entry["kind"], "suppression_permille": int(entry["suppression_permille"])})
	decoded.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["cause_id"] < b["cause_id"])
	return ServiceResult.success(decoded)


static func suppression(causes: Array) -> int:
	var total: int = 0
	for cause in causes:
		total = mini(1000, total + int(cause["suppression_permille"]))
	return total


static func from_record(record: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "body_id", "state_revision", "state", "last_assessed_tick", "transition_tick", "recovery_since_tick", "causes"])):
		return ServiceResult.failure(&"invalid_consciousness_state", "An exact versioned consciousness record is required.")
	if not ControlContractValidation.is_integer(record["schema_version"], 1, 1) or not ControlContractValidation.is_id(record["body_id"]) or not ["alert", "impaired", "unconscious"].has(record["state"]):
		return ServiceResult.failure(&"invalid_consciousness_state", "Unsupported schema, body identity or state.")
	for field in ["state_revision", "last_assessed_tick", "transition_tick"]:
		if not ControlContractValidation.is_integer(record[field], 0, MAX_INTEGER):
			return ServiceResult.failure(&"invalid_consciousness_state", "Revisions and ticks must be bounded integers.")
	if not ControlContractValidation.is_integer(record["recovery_since_tick"], -1, MAX_INTEGER):
		return ServiceResult.failure(&"invalid_consciousness_state", "Recovery tick must be a bounded integer or -1.")
	var causes: ServiceResult = decode_causes(record["causes"])
	if not causes.is_success:
		return causes
	var total: int = suppression(causes.value)
	var tick: int = int(record["last_assessed_tick"])
	var transition: int = int(record["transition_tick"])
	var recovery: int = int(record["recovery_since_tick"])
	if transition > tick or recovery > tick or (recovery >= 0 and recovery < transition):
		return ServiceResult.failure(&"invalid_consciousness_state", "State timing is inconsistent.")
	if record["state"] != "unconscious" and recovery != -1:
		return ServiceResult.failure(&"invalid_consciousness_state", "Only unconscious bodies retain recovery progress.")
	if (record["state"] == "alert" and total >= 250) or (record["state"] == "impaired" and (total <= 150 or total >= 750)):
		return ServiceResult.failure(&"invalid_consciousness_state", "Conscious state contradicts its assessed causes.")
	if record["state"] == "unconscious" and ((total <= 500 and recovery < 0) or (total > 500 and recovery != -1)):
		return ServiceResult.failure(&"invalid_consciousness_state", "Unconscious recovery progress contradicts its causes.")
	var state := ConsciousnessState.new()
	state._record = record.duplicate(true)
	for field in ["schema_version", "state_revision", "last_assessed_tick", "transition_tick", "recovery_since_tick"]:
		state._record[field] = int(record[field])
	state._record["causes"] = causes.value
	return ServiceResult.success(state)
