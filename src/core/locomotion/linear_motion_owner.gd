extends RefCounted
class_name LinearMotionOwner

## Single domain owner for exact momentum and atomic paired impulses.
## A trusted fixed-tick adapter supplies authorization, loadout and fresh collision contact.
const MAX_STATES: int = 64
const MAX_RECEIPTS: int = 128
var _record: Dictionary = {}
var _rejections: int = 0
var _retry_acknowledgements: int = 0


static func create(owner_id: String, states: Array) -> ServiceResult:
	return from_record({"schema_version": 1, "owner_id": owner_id, "state_revision": 0, "last_commit_tick": 0, "states": states.duplicate(true), "receipts": []})


func to_record() -> Dictionary:
	return _record.duplicate(true)


func state_observation(body_id: String) -> ServiceResult:
	var index: int = _state_index(body_id)
	if index < 0:
		return _failure("The body is not registered with this motion owner.")
	return ServiceResult.success(_record["states"][index].duplicate(true))


func profiling_counters() -> Dictionary:
	return {"motion_states": _record["states"].size(), "retained_receipts": _record["receipts"].size(), "committed_impulses": _record["state_revision"], "rejected_commits": _rejections, "retry_acknowledgements": _retry_acknowledgements}


## Retained identical retries acknowledge without contact revalidation or another impulse.
## New effects require current owner/body revisions and same-tick trusted contact.
func push_off(request: Dictionary, contact: Dictionary, observed_tick: int, commit_tick: int) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "request_id", "actor_body_id", "target_body_id", "expected_owner_revision", "expected_actor_revision", "expected_target_revision", "impulse_micro_ns"])
	if not ControlContractValidation.has_exact_fields(request, fields) or not ControlContractValidation.is_integer(request.get("schema_version"), 1, 1) or not LinearMotionState.vector_valid(request.get("impulse_micro_ns"), PushOffImpulsePlanner.MAX_IMPULSE_MICRO_NS):
		return _reject("A complete bounded push-off intent is required.")
	for field in ["request_id", "actor_body_id", "target_body_id"]:
		if not ControlContractValidation.is_id(request[field]):
			return _reject("Push-off request identities must be stable bounded IDs.")
	for field in ["expected_owner_revision", "expected_actor_revision", "expected_target_revision"]:
		if not ControlContractValidation.is_integer(request[field], 0, LinearMotionState.MAX_EXACT_INTEGER):
			return _reject("Expected revisions must be exact bounded counters.")
	var impulse: Array = [int(request["impulse_micro_ns"][0]), int(request["impulse_micro_ns"][1]), int(request["impulse_micro_ns"][2])]
	var fingerprint: String = JSON.stringify([_record["owner_id"], request["request_id"], request["actor_body_id"], request["target_body_id"], int(request["expected_owner_revision"]), int(request["expected_actor_revision"]), int(request["expected_target_revision"]), impulse]).sha256_text()
	for receipt in _record["receipts"]:
		if receipt["request_id"] == request["request_id"]:
			if receipt["fingerprint"] != fingerprint:
				return _reject("This retained request ID identifies different impulse intent.")
			_retry_acknowledgements = mini(_retry_acknowledgements + 1, LinearMotionState.MAX_EXACT_INTEGER)
			return ServiceResult.success(receipt.duplicate(true))
	var actor_index: int = _state_index(request["actor_body_id"])
	var target_index: int = _state_index(request["target_body_id"])
	if actor_index < 0 or target_index < 0 or actor_index == target_index:
		return _reject("Distinct registered actor and target motion states are required.")
	if commit_tick < 1 or commit_tick > LinearMotionState.MAX_EXACT_INTEGER or observed_tick != commit_tick or commit_tick < int(_record["last_commit_tick"]):
		return _reject("New impulses require fresh same-tick contact at a nondecreasing tick.")
	var actor: Dictionary = _record["states"][actor_index]
	var target: Dictionary = _record["states"][target_index]
	if int(request["expected_owner_revision"]) != int(_record["state_revision"]) or int(request["expected_actor_revision"]) != int(actor["state_revision"]) or int(request["expected_target_revision"]) != int(target["state_revision"]) or int(_record["state_revision"]) >= LinearMotionState.MAX_EXACT_INTEGER:
		return _reject("Owner/body revisions are stale or exhausted.")
	var planned: ServiceResult = PushOffImpulsePlanner.plan(actor, target, contact, impulse)
	if not planned.is_success:
		return _reject(planned.message)
	var candidate: Dictionary = to_record()
	candidate["states"][actor_index] = planned.value["actor_after"]
	candidate["states"][target_index] = planned.value["target_after"]
	candidate["state_revision"] = int(_record["state_revision"]) + 1
	candidate["last_commit_tick"] = commit_tick
	var receipt := {"request_id": request["request_id"], "fingerprint": fingerprint, "actor_body_id": request["actor_body_id"], "target_body_id": request["target_body_id"], "result_owner_revision": candidate["state_revision"], "actor_revision": planned.value["actor_after"]["state_revision"], "target_revision": planned.value["target_after"]["state_revision"], "commit_tick": commit_tick}
	candidate["receipts"].append(receipt)
	if candidate["receipts"].size() > MAX_RECEIPTS:
		candidate["receipts"].pop_front()
	var checked: ServiceResult = from_record(candidate, commit_tick)
	if not checked.is_success:
		return _reject(checked.message)
	_record = checked.value.to_record()
	return ServiceResult.success(receipt.duplicate(true))


## Optional snapshot tick rejects records claiming future commits. No impulse is replayed.
static func from_record(record: Dictionary, snapshot_tick: int = -1) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "owner_id", "state_revision", "last_commit_tick", "states", "receipts"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(record.get("owner_id")) or not ControlContractValidation.is_integer(record.get("state_revision"), 0, LinearMotionState.MAX_EXACT_INTEGER) or not ControlContractValidation.is_integer(record.get("last_commit_tick"), 0, LinearMotionState.MAX_EXACT_INTEGER) or typeof(record.get("states")) != TYPE_ARRAY or record["states"].size() > MAX_STATES or typeof(record.get("receipts")) != TYPE_ARRAY or record["receipts"].size() > MAX_RECEIPTS:
		return _failure("A bounded versioned motion owner record is required.")
	if snapshot_tick < -1 or snapshot_tick > LinearMotionState.MAX_EXACT_INTEGER or (snapshot_tick >= 0 and int(record["last_commit_tick"]) > snapshot_tick):
		return _failure("Saved motion commits cannot be ahead of the snapshot tick.")
	if record["receipts"].size() != mini(int(record["state_revision"]), MAX_RECEIPTS):
		return _failure("The bounded tail must retain every committed receipt within its retention window.")
	var normalized: Dictionary = record.duplicate(true)
	normalized["schema_version"] = 1
	normalized["state_revision"] = int(record["state_revision"])
	normalized["last_commit_tick"] = int(record["last_commit_tick"])
	var states: Dictionary = {}
	for index in range(record["states"].size()):
		var raw: Variant = record["states"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("Motion states must be record objects.")
		var parsed: ServiceResult = LinearMotionState.from_record(raw)
		if not parsed.is_success or states.has(raw["body_id"]):
			return _failure("Motion states require valid unique body identities.")
		normalized["states"][index] = parsed.value.to_record()
		states[raw["body_id"]] = normalized["states"][index]
	var requests: Dictionary = {}
	var previous_revision: int = 0
	var previous_tick: int = 0
	var body_revisions: Dictionary = {}
	for index in range(record["receipts"].size()):
		var raw: Variant = record["receipts"][index]
		var fields := PackedStringArray(["request_id", "fingerprint", "actor_body_id", "target_body_id", "result_owner_revision", "actor_revision", "target_revision", "commit_tick"])
		if typeof(raw) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(raw, fields) or not ControlContractValidation.is_id(raw.get("request_id")) or requests.has(raw["request_id"]) or typeof(raw.get("fingerprint")) != TYPE_STRING or raw["fingerprint"].length() != 64:
			return _failure("Retained impulse receipts require unique IDs and SHA-256 fingerprints.")
		for character in raw["fingerprint"]:
			if not "0123456789abcdef".contains(character):
				return _failure("Receipt fingerprints must be hexadecimal SHA-256.")
		if not ControlContractValidation.is_id(raw["actor_body_id"]) or not ControlContractValidation.is_id(raw["target_body_id"]) or raw["actor_body_id"] == raw["target_body_id"] or not states.has(raw["actor_body_id"]) or not states.has(raw["target_body_id"]):
			return _failure("Receipt bodies must reference distinct registered states.")
		var expected_revision: int = normalized["state_revision"] - record["receipts"].size() + index + 1
		if not ControlContractValidation.is_integer(raw["result_owner_revision"], expected_revision, expected_revision) or not ControlContractValidation.is_integer(raw["commit_tick"], maxi(1, previous_tick), normalized["last_commit_tick"]):
			return _failure("Receipt revisions/ticks must be ordered within canonical state.")
		for role in ["actor", "target"]:
			if not ControlContractValidation.is_integer(raw[role + "_revision"], 1, states[raw[role + "_body_id"]]["state_revision"]):
				return _failure("Receipt body revisions cannot be ahead of canonical motion.")
			var body_id: String = raw[role + "_body_id"]
			if body_revisions.has(body_id) and int(raw[role + "_revision"]) != int(body_revisions[body_id]) + 1:
				return _failure("Retained body revisions must advance once per impulse.")
			body_revisions[body_id] = int(raw[role + "_revision"])
		if states[raw["actor_body_id"]]["frame_id"] != states[raw["target_body_id"]]["frame_id"]:
			return _failure("Receipt bodies must share their unchanged reference frame.")
		var receipt: Dictionary = raw.duplicate(true)
		for field in ["result_owner_revision", "actor_revision", "target_revision", "commit_tick"]:
			receipt[field] = int(receipt[field])
		normalized["receipts"][index] = receipt
		requests[raw["request_id"]] = true
		previous_revision = receipt["result_owner_revision"]
		previous_tick = receipt["commit_tick"]
	for body_id in body_revisions:
		if body_revisions[body_id] != states[body_id]["state_revision"]:
			return _failure("The latest retained body receipt must match canonical motion revision.")
	if (normalized["state_revision"] == 0 and (previous_revision != 0 or normalized["last_commit_tick"] != 0)) or (normalized["state_revision"] > 0 and (previous_revision != normalized["state_revision"] or previous_tick != normalized["last_commit_tick"])):
		return _failure("The latest retained receipt must match the owner's committed revision and tick.")
	var owner := LinearMotionOwner.new()
	owner._record = normalized
	return ServiceResult.success(owner)


func _state_index(body_id: String) -> int:
	for index in range(_record["states"].size()):
		if _record["states"][index]["body_id"] == body_id:
			return index
	return -1


func _reject(message: String) -> ServiceResult:
	_rejections = mini(_rejections + 1, LinearMotionState.MAX_EXACT_INTEGER)
	return _failure(message)


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_linear_motion_owner", message)
