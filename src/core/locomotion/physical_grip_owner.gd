extends RefCounted
class_name PhysicalGripOwner

## Canonical grip intents and hand reservations. Trusted adapters supply contact/loadout observations.
## This owner neither applies physics nor authenticates player sessions.
const MAX_EXACT_INTEGER: int = 9007199254740990
const MAX_SESSIONS: int = 32
const MAX_RECEIPTS: int = 128
var _record: Dictionary = {}


static func create(owner_id: String) -> ServiceResult:
	return from_record({"schema_version": 1, "owner_id": owner_id, "state_revision": 0, "sessions": [], "receipts": []}, false)


func to_record() -> Dictionary:
	return _record.duplicate(true)


func profiling_counters() -> Dictionary:
	var participants: int = 0
	var hands: int = 0
	var paused: int = 0
	for session in _record["sessions"]:
		paused += 1 if session["paused"] else 0
		participants += session["participants"].size()
		for participant in session["participants"]:
			hands += participant["hand_ids"].size()
	return {"sessions": _record["sessions"].size(), "participants": participants, "reserved_hands": hands, "paused_sessions": paused, "retained_receipts": _record["receipts"].size()}


func hand_is_reserved(body_id: String, hand_id: String) -> bool:
	for session in _record["sessions"]:
		for participant in session["participants"]:
			if participant["body_id"] == body_id and participant["hand_ids"].has(hand_id):
				return true
	return false


## Joining is explicit for one bound actor. Existing contributors cannot be changed by joining.
## Insufficient group force may retain a waiting grip; other availability failures reject.
func join(request: Dictionary, observation: Dictionary) -> ServiceResult:
	var checked: ServiceResult = _request(request)
	if not checked.is_success:
		return checked
	var assessment: ServiceResult = PhysicalInteractionPolicy.assess(observation)
	if not assessment.is_success or observation["action"] == "push_off":
		return _failure("A validated sustained grip observation is required.")
	var proposed: Array = assessment.value["proposed_hand_reservations"]
	var actor: Dictionary = {}
	for participant in proposed:
		if participant["body_id"] == request["body_id"]:
			actor = participant
	if actor.is_empty() or actor["hand_ids"].is_empty():
		return _failure("The joining body must propose usable hands.")
	var fingerprint: String = _fingerprint("join", request, [observation["target_id"], observation["action"], actor["hand_ids"]])
	var receipt: ServiceResult = _retained(request["request_id"], fingerprint)
	if receipt != null:
		return receipt
	if not _current(request):
		return _failure("The grip revision is stale or exhausted.")
	for reason in assessment.value["reasons"]:
		if reason != "insufficient_force":
			return _failure("Grip contact, capability or target requirements are unavailable.")
	var candidate: Dictionary = to_record()
	var index: int = _session_index(request["session_id"])
	if index < 0:
		if candidate["sessions"].size() >= MAX_SESSIONS or proposed.size() != 1:
			return _failure("A new session starts with one participant within owner limits.")
		for existing in candidate["sessions"]:
			if existing["target_id"] == observation["target_id"]:
				return _failure("Join the existing target session instead of creating competing ownership.")
		candidate["sessions"].append({"session_id": request["session_id"], "target_id": observation["target_id"], "action": observation["action"], "paused": false, "participants": proposed.duplicate(true)})
	else:
		var session: Dictionary = candidate["sessions"][index]
		if session["paused"] or not _matches(session, observation, false) or proposed.size() != session["participants"].size() + 1:
			return _failure("Joining requires an active matching target and all existing participants unchanged.")
		for participant in session["participants"]:
			if participant["body_id"] == request["body_id"]:
				return _failure("This body already participates in the session.")
		session["participants"].append(actor.duplicate(true))
	for hand_id in actor["hand_ids"]:
		if hand_is_reserved(request["body_id"], hand_id):
			return _failure("A proposed hand is already reserved by a grip.")
	return _commit(candidate, request["request_id"], fingerprint)


## Release requires membership, not fresh contact. It must remain possible after contact loss.
func release(request: Dictionary) -> ServiceResult:
	var checked: ServiceResult = _request(request)
	if not checked.is_success:
		return checked
	var fingerprint: String = _fingerprint("release", request, [])
	var receipt: ServiceResult = _retained(request["request_id"], fingerprint)
	if receipt != null:
		return receipt
	if not _current(request):
		return _failure("The grip revision is stale or exhausted.")
	var index: int = _session_index(request["session_id"])
	if index < 0:
		return _failure("The session is not registered.")
	var candidate: Dictionary = to_record()
	var participants: Array = candidate["sessions"][index]["participants"]
	var removed: bool = false
	for participant_index in range(participants.size() - 1, -1, -1):
		if participants[participant_index]["body_id"] == request["body_id"]:
			participants.remove_at(participant_index)
			removed = true
	if not removed:
		return _failure("Only a session participant may release their own hands.")
	if participants.is_empty():
		candidate["sessions"].remove_at(index)
	return _commit(candidate, request["request_id"], fingerprint)


## Recovery stays paused until an adapter rechecks all participants and their authorization.
func resume(request: Dictionary, observation: Dictionary) -> ServiceResult:
	var checked: ServiceResult = _request(request)
	if not checked.is_success:
		return checked
	var assessment: ServiceResult = PhysicalInteractionPolicy.assess(observation)
	if not assessment.is_success:
		return assessment
	var fingerprint: String = _fingerprint("resume", request, [])
	var receipt: ServiceResult = _retained(request["request_id"], fingerprint)
	if receipt != null:
		return receipt
	var index: int = _session_index(request["session_id"])
	if not _current(request) or index < 0 or not _matches(_record["sessions"][index], observation, true):
		return _failure("Resume requires the current complete session observation.")
	var member: bool = false
	for participant in _record["sessions"][index]["participants"]:
		member = member or participant["body_id"] == request["body_id"]
	if not member or not _record["sessions"][index]["paused"]:
		return _failure("A member must resume a paused session.")
	for reason in assessment.value["reasons"]:
		if reason != "insufficient_force":
			return _failure("Fresh participant and contact checks must pass before resume.")
	var candidate: Dictionary = to_record()
	candidate["sessions"][index]["paused"] = false
	return _commit(candidate, request["request_id"], fingerprint)


## Fresh assessment only. Never cache this as permission to apply future forces.
func assess_session(session_id: String, observation: Dictionary) -> ServiceResult:
	var index: int = _session_index(session_id)
	if index < 0 or not _matches(_record["sessions"][index], observation, true):
		return _failure("The observation must match the registered session and hands.")
	var assessment: ServiceResult = PhysicalInteractionPolicy.assess(observation)
	if not assessment.is_success:
		return assessment
	if _record["sessions"][index]["paused"]:
		assessment.value["allowed"] = false
		assessment.value["reasons"].append("session_paused")
	return assessment


static func from_record(record: Dictionary, pause_on_restore: bool = true) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "owner_id", "state_revision", "sessions", "receipts"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_id(record.get("owner_id")) or not ControlContractValidation.is_integer(record.get("state_revision"), 0, MAX_EXACT_INTEGER) or typeof(record.get("sessions")) != TYPE_ARRAY or record["sessions"].size() > MAX_SESSIONS or typeof(record.get("receipts")) != TYPE_ARRAY or record["receipts"].size() > MAX_RECEIPTS:
		return _failure("A bounded versioned grip owner record is required.")
	var session_ids: Dictionary = {}
	var targets: Dictionary = {}
	var hands: Dictionary = {}
	for session in record["sessions"]:
		if typeof(session) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(session, PackedStringArray(["session_id", "target_id", "action", "paused", "participants"])) or not ControlContractValidation.is_id(session.get("session_id")) or session_ids.has(session["session_id"]) or not ControlContractValidation.is_id(session.get("target_id")) or targets.has(session["target_id"]) or session.get("action") not in ["grab", "pull_along", "move_world_object"] or typeof(session.get("paused")) != TYPE_BOOL or typeof(session.get("participants")) != TYPE_ARRAY or session["participants"].is_empty() or session["participants"].size() > 16:
			return _failure("Sessions require distinct identities/targets and bounded participants.")
		if session["action"] != "move_world_object" and session["participants"].size() != 1:
			return _failure("Traversal sessions have one body.")
		session_ids[session["session_id"]] = true
		targets[session["target_id"]] = true
		var bodies: Dictionary = {}
		for participant in session["participants"]:
			if typeof(participant) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(participant, PackedStringArray(["body_id", "hand_ids"])) or not ControlContractValidation.is_id(participant.get("body_id")) or bodies.has(participant["body_id"]):
				return _failure("Session participants require distinct bodies.")
			bodies[participant["body_id"]] = true
			var decoded: ServiceResult = ControlContractValidation.decode_ids(participant["hand_ids"], 1, 8)
			if not decoded.is_success:
				return decoded
			for hand_id in decoded.value:
				var key: String = JSON.stringify([participant["body_id"], hand_id])
				if hands.has(key):
					return _failure("A hand cannot be reserved twice.")
				hands[key] = true
	var requests: Dictionary = {}
	var previous_revision: int = 0
	for receipt in record["receipts"]:
		if typeof(receipt) != TYPE_DICTIONARY or not ControlContractValidation.has_exact_fields(receipt, PackedStringArray(["request_id", "fingerprint", "result_revision"])) or not ControlContractValidation.is_id(receipt.get("request_id")) or requests.has(receipt["request_id"]) or typeof(receipt.get("fingerprint")) != TYPE_STRING or receipt["fingerprint"].length() != 64 or not ControlContractValidation.is_integer(receipt.get("result_revision"), previous_revision + 1, int(record["state_revision"])):
			return _failure("Retained receipts require unique IDs and ordered committed revisions.")
		for character in receipt["fingerprint"]:
			if not "0123456789abcdef".contains(character):
				return _failure("Receipt fingerprints must be hexadecimal SHA-256.")
		previous_revision = int(receipt["result_revision"])
		requests[receipt["request_id"]] = true
	var owner := PhysicalGripOwner.new()
	owner._record = record.duplicate(true)
	owner._record["state_revision"] = int(record["state_revision"])
	for receipt in owner._record["receipts"]:
		receipt["result_revision"] = int(receipt["result_revision"])
	if pause_on_restore:
		for session in owner._record["sessions"]:
			session["paused"] = true
	return ServiceResult.success(owner)


## Trusted lifecycle preparation only: never publishes or creates player receipts.
## The composing canonical owner must compare/commit before installing this owner.
## Remove this body's reservations across bounded sessions; preserve every other member.
func prepare_controller_invalidation(body_id: String) -> ServiceResult:
	if not ControlContractValidation.is_id(body_id):
		return _failure("Controller invalidation requires a stable body ID.")
	var candidate: Dictionary = to_record()
	var changed: bool = false
	for index in range(candidate["sessions"].size() - 1, -1, -1):
		var participants: Array = candidate["sessions"][index]["participants"]
		for member in range(participants.size() - 1, -1, -1):
			if participants[member]["body_id"] == body_id:
				participants.remove_at(member)
				changed = true
		if participants.is_empty():
			candidate["sessions"].remove_at(index)
	if changed:
		if int(candidate["state_revision"]) >= MAX_EXACT_INTEGER:
			return _failure("Grip invalidation revision is exhausted.")
		candidate["state_revision"] = int(candidate["state_revision"]) + 1
	return from_record(candidate, false)


func _session_index(id: String) -> int:
	for index in range(_record["sessions"].size()):
		if _record["sessions"][index]["session_id"] == id:
			return index
	return -1


static func _matches(session: Dictionary, observation: Dictionary, exact: bool) -> bool:
	var assessed: ServiceResult = PhysicalInteractionPolicy.assess(observation)
	if not assessed.is_success or session["target_id"] != observation["target_id"] or session["action"] != observation["action"]:
		return false
	var proposed: Array = assessed.value["proposed_hand_reservations"]
	if exact and proposed.size() != session["participants"].size():
		return false
	for participant in session["participants"]:
		var found: bool = false
		for candidate in proposed:
			if candidate["body_id"] == participant["body_id"] and candidate["hand_ids"] == participant["hand_ids"]:
				found = true
		if not found:
			return false
	return true


static func _request(request: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(request, PackedStringArray(["request_id", "session_id", "body_id", "expected_revision"])) or not ControlContractValidation.is_integer(request.get("expected_revision"), 0, MAX_EXACT_INTEGER):
		return _failure("A complete versioned-revision grip request is required.")
	for field in ["request_id", "session_id", "body_id"]:
		if not ControlContractValidation.is_id(request[field]):
			return _failure("Grip request identities must be stable bounded IDs.")
	return ServiceResult.success()


func _current(request: Dictionary) -> bool:
	return int(request["expected_revision"]) == int(_record["state_revision"]) and int(_record["state_revision"]) < MAX_EXACT_INTEGER


func _fingerprint(operation: String, request: Dictionary, extra: Array) -> String:
	return JSON.stringify([_record["owner_id"], operation, request["request_id"], request["session_id"], request["body_id"], int(request["expected_revision"]), extra]).sha256_text()


func _retained(id: String, fingerprint: String) -> ServiceResult:
	for receipt in _record["receipts"]:
		if receipt["request_id"] == id:
			return ServiceResult.success(receipt.duplicate(true)) if receipt["fingerprint"] == fingerprint else _failure("This retained request ID identifies different intent.")
	return null


func _commit(candidate: Dictionary, id: String, fingerprint: String) -> ServiceResult:
	candidate["state_revision"] = int(_record["state_revision"]) + 1
	var receipt := {"request_id": id, "fingerprint": fingerprint, "result_revision": candidate["state_revision"]}
	candidate["receipts"].append(receipt)
	if candidate["receipts"].size() > MAX_RECEIPTS:
		candidate["receipts"].pop_front()
	var checked: ServiceResult = from_record(candidate, false)
	if not checked.is_success:
		return checked
	_record = checked.value.to_record()
	return ServiceResult.success(receipt.duplicate(true))


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_physical_grip", message)
