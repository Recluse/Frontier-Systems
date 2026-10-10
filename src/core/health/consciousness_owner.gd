extends RefCounted
class_name ConsciousnessOwner

## One body's canonical consciousness and bounded assessment receipts.
## Only a trusted health adapter may supply current causes; this is not a player API.
const MAX_RECEIPTS: int = 64
const MAX_COUNTER: int = 1000000000
var _record: Dictionary = {}
var _receipts_by_id: Dictionary = {}
var _rejections: int = 0
var _retries: int = 0
var _transitions: int = 0


static func create(body_id: String) -> ServiceResult:
	var state: ServiceResult = ConsciousnessState.create_alert(body_id)
	if not state.is_success:
		return state
	return from_record({"schema_version": 1, "state": state.value.to_record(), "receipts": []})


func to_record() -> Dictionary:
	return _record.duplicate(true)


func state_observation() -> Dictionary:
	return _record["state"].duplicate(true)


## One capability input, not a permission or overall body viability verdict.
func allows_voluntary_actions() -> bool:
	return _record["state"]["state"] != "unconscious"


func profiling_counters() -> Dictionary:
	return {"assessments": _record["state"]["state_revision"], "active_causes": _record["state"]["causes"].size(),
		"retained_receipts": _record["receipts"].size(), "rejected_assessments": _rejections,
		"retry_acknowledgements": _retries, "transitions_since_load": _transitions}


func assess(request: Dictionary, commit_tick: int) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "request_id", "body_id", "expected_state_revision", "observed_tick", "causes"])
	if not ControlContractValidation.has_exact_fields(request, fields) or not ControlContractValidation.is_integer(request.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(request.get("request_id")) or not ControlContractValidation.is_id(request.get("body_id")):
		return _reject("An exact versioned assessment with stable IDs is required.")
	if not ControlContractValidation.is_integer(request["expected_state_revision"], 0, ConsciousnessState.MAX_INTEGER) or not ControlContractValidation.is_integer(request["observed_tick"], 1, ConsciousnessState.MAX_INTEGER):
		return _reject("Expected revision and observation tick must be bounded integers.")
	var causes: ServiceResult = ConsciousnessState.decode_causes(request["causes"])
	if not causes.is_success:
		return _reject(causes.message)
	var current: Dictionary = _record["state"]
	if request["body_id"] != current["body_id"]:
		return _reject("An assessment must identify this owner's body.")
	var fingerprint: String = JSON.stringify([request["request_id"], request["body_id"], int(request["expected_state_revision"]), int(request["observed_tick"]), causes.value]).sha256_text()
	if _receipts_by_id.has(request["request_id"]):
		var retained: Dictionary = _receipts_by_id[request["request_id"]]
		if retained["fingerprint"] != fingerprint:
			return _reject("The retained request ID identifies different assessment content.")
		_retries = mini(_retries + 1, MAX_COUNTER)
		return ServiceResult.success(retained.duplicate(true))
	if commit_tick != int(request["observed_tick"]) or commit_tick <= int(current["last_assessed_tick"]) or commit_tick > ConsciousnessState.MAX_INTEGER or int(request["expected_state_revision"]) != int(current["state_revision"]):
		return _reject("New assessments require current body revision and a fresh same-tick observation.")
	var state: ServiceResult = ConsciousnessState.from_record(current)
	var planned: ServiceResult = ConsciousnessPolicy.plan(state.value, causes.value, commit_tick)
	if not planned.is_success:
		return _reject(planned.message)
	var receipt := {"request_id": request["request_id"], "fingerprint": fingerprint,
		"state_revision": planned.value["after"]["state_revision"], "commit_tick": commit_tick,
		"state": planned.value["after"]["state"], "transitioned": planned.value["transitioned"]}
	# Existing receipts are private immutable records validated on creation/load.
	# Validate only the new policy state; do not re-decode the retained history.
	var receipts: Array = _record["receipts"].duplicate()
	receipts.append(receipt)
	var evicted_id: String = ""
	if receipts.size() > MAX_RECEIPTS:
		evicted_id = receipts.pop_front()["request_id"]
	_record = {"schema_version": 1, "state": planned.value["after"], "receipts": receipts}
	if not evicted_id.is_empty():
		_receipts_by_id.erase(evicted_id)
	_receipts_by_id[receipt["request_id"]] = receipt
	if receipt["transitioned"]:
		_transitions = mini(_transitions + 1, MAX_COUNTER)
	return ServiceResult.success(receipt.duplicate(true))


static func from_record(record: Dictionary, snapshot_tick: int = -1) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "state", "receipts"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or typeof(record.get("state")) != TYPE_DICTIONARY or typeof(record.get("receipts")) != TYPE_ARRAY:
		return _failure("A versioned consciousness owner record is required.")
	var parsed: ServiceResult = ConsciousnessState.from_record(record["state"])
	if not parsed.is_success:
		return _failure(parsed.message)
	var state: Dictionary = parsed.value.to_record()
	var revision: int = state["state_revision"]
	if snapshot_tick < -1 or snapshot_tick > ConsciousnessState.MAX_INTEGER or (snapshot_tick >= 0 and int(state["last_assessed_tick"]) > snapshot_tick):
		return _failure("Saved assessments cannot be ahead of the snapshot tick.")
	if record["receipts"].size() != mini(revision, MAX_RECEIPTS):
		return _failure("Every assessment in the bounded receipt tail must be retained.")
	if revision == 0 and state != ConsciousnessState.create_alert(state["body_id"]).value.to_record():
		return _failure("A new owner must start with its unassessed alert record.")
	var normalized := {"schema_version": 1, "state": state, "receipts": []}
	var ids: Dictionary = {}
	var previous_tick: int = 0
	var previous_state: String = "alert" if revision <= MAX_RECEIPTS else ""
	var latest_transition: int = -1
	for index in range(record["receipts"].size()):
		var raw: Variant = record["receipts"][index]
		var fields := PackedStringArray(["request_id", "fingerprint", "state_revision", "commit_tick", "state", "transitioned"])
		if typeof(raw) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw, fields) or not ControlContractValidation.is_id(raw.get("request_id")) or ids.has(raw["request_id"]) or typeof(raw.get("fingerprint")) != TYPE_STRING or raw["fingerprint"].length() != 64:
			return _failure("Assessment receipts require exact fields, unique IDs and SHA-256 fingerprints.")
		for character in raw["fingerprint"]:
			if not "0123456789abcdef".contains(character):
				return _failure("Receipt fingerprints must be hexadecimal SHA-256.")
		if not ControlContractValidation.is_integer(raw["state_revision"], 1, ConsciousnessState.MAX_INTEGER) or int(raw["state_revision"]) != revision - record["receipts"].size() + index + 1 or not ControlContractValidation.is_integer(raw["commit_tick"], 1, ConsciousnessState.MAX_INTEGER) or int(raw["commit_tick"]) <= previous_tick or not ["alert", "impaired", "unconscious"].has(raw["state"]) or typeof(raw["transitioned"]) != TYPE_BOOL:
			return _failure("Receipt revisions, ticks and states must form an ordered assessment tail.")
		if not previous_state.is_empty() and raw["transitioned"] != (previous_state != raw["state"]):
			return _failure("Receipt transition flags contradict successive states.")
		if raw["transitioned"]:
			latest_transition = int(raw["commit_tick"])
		var receipt: Dictionary = raw.duplicate(true)
		receipt["state_revision"] = int(raw["state_revision"])
		receipt["commit_tick"] = int(raw["commit_tick"])
		normalized["receipts"].append(receipt)
		ids[raw["request_id"]] = true
		previous_tick = receipt["commit_tick"]
		previous_state = receipt["state"]
	if revision > 0 and (previous_tick != state["last_assessed_tick"] or previous_state != state["state"]):
		return _failure("Latest receipt must match canonical state and assessment tick.")
	if latest_transition >= 0 and latest_transition != state["transition_tick"]:
		return _failure("Latest retained transition must match canonical transition tick.")
	if latest_transition < 0 and ((revision <= MAX_RECEIPTS and state["transition_tick"] != 0) or (revision > MAX_RECEIPTS and int(state["transition_tick"]) >= int(normalized["receipts"][0]["commit_tick"]))):
		return _failure("Canonical transition tick is inconsistent with the retained tail.")
	var owner := ConsciousnessOwner.new()
	owner._record = normalized
	for receipt in normalized["receipts"]:
		owner._receipts_by_id[receipt["request_id"]] = receipt
	return ServiceResult.success(owner)


func _reject(message: String) -> ServiceResult:
	_rejections = mini(_rejections + 1, MAX_COUNTER)
	return _failure(message)


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_consciousness_owner", message)
