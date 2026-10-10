extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/locomotion/cooperative-object-move.v1.json"))
	var owner: PhysicalGripOwner = PhysicalGripOwner.create("grips.prototype").value
	var first: Dictionary = fixture.duplicate(true)
	first["participants"].pop_back()
	var start: Dictionary = _request("start", "session.crate", "body.human-1", 0)
	_check(owner.join(start, first).is_success, "one participant can establish a waiting cooperative grip")
	_check(owner.hand_is_reserved("body.human-1", "hand.left"), "joining must reserve the proposed hand")
	_check(not owner.assess_session("session.crate", first).value["allowed"], "insufficient solo force must not move the object")
	var before: Dictionary = owner.to_record()
	_check(owner.join(start, first).is_success and owner.to_record() == before, "retained join retry must not mutate reservations")
	var changed: Dictionary = first.duplicate(true)
	changed["target_id"] = "object.other"
	_check(not owner.join(start, changed).is_success, "request ID reuse with changed intent must reject")
	_check(not owner.join(_request("stale", "session.crate", "body.human-2", 0), fixture).is_success, "stale revision must not join")
	_check(owner.join(_request("join", "session.crate", "body.human-2", 1), fixture).is_success, "second explicitly joining body must complete the group")
	_check(owner.assess_session("session.crate", fixture).value["allowed"], "complete cooperative group must pass fresh assessment")
	_check(owner.profiling_counters()["reserved_hands"] == 2, "bounded counters must reflect reservations")
	changed = first.duplicate(true)
	changed["target_id"] = "object.other"
	changed["required_force_millinewtons"] = 0
	_check(not owner.join(_request("double", "session.other", "body.human-1", 2), changed).is_success, "same hand cannot be reserved on two objects")
	_check(owner.to_record()["state_revision"] == 2, "failed commits must leave owner revision unchanged")
	changed = fixture.duplicate(true)
	changed["participants"][0]["free_hand_ids"] = ["hand.right"]
	_check(not owner.assess_session("session.crate", changed).is_success, "assessment cannot silently replace a reserved hand")
	changed = fixture.duplicate(true)
	changed["participants"][1]["contact"] = false
	_check(not owner.assess_session("session.crate", changed).value["allowed"], "lost contact must prevent fresh force application")
	var decoded: ServiceResult = PhysicalGripOwner.from_record(JSON.parse_string(JSON.stringify(owner.to_record())))
	_check(decoded.is_success, "saved owner must round trip")
	var restored: PhysicalGripOwner = decoded.value
	_check(restored.hand_is_reserved("body.human-2", "hand.right"), "paused recovery must preserve reservations until release or revalidation")
	_check(not restored.assess_session("session.crate", fixture).value["allowed"], "restored grips must never immediately reactivate physics")
	_check(not restored.resume(_request("bad-resume", "session.crate", "body.human-2", 2), changed).is_success, "resume must reject lost contact")
	_check(not restored.resume(_request("outsider", "session.crate", "body.other", 2), fixture).is_success, "outsider cannot resume another group's session")
	_check(restored.resume(_request("resume", "session.crate", "body.human-2", 2), fixture).is_success, "fresh member observation can explicitly resume")
	_check(restored.assess_session("session.crate", fixture).value["allowed"], "resumed group must be assessed using fresh observations")
	var recovered_again: PhysicalGripOwner = PhysicalGripOwner.from_record(restored.to_record()).value
	_check(recovered_again.resume(_request("resume", "session.crate", "body.human-2", 2), fixture).is_success, "old retained resume must acknowledge without reapplying")
	_check(not recovered_again.assess_session("session.crate", fixture).value["allowed"], "resume retry must not reactivate a newly restored paused session")
	_check(not restored.release(_request("outsider-release", "session.crate", "body.other", 3)).is_success, "release cannot remove other participants")
	_check(restored.release(_request("leave", "session.crate", "body.human-2", 3)).is_success, "member can leave without fresh contact")
	_check(not restored.hand_is_reserved("body.human-2", "hand.right"), "leaving releases own hand only")
	_check(not restored.assess_session("session.crate", first).value["allowed"], "remaining group loses insufficient cooperative capability")
	_check(restored.release(_request("last", "session.crate", "body.human-1", 4)).is_success, "last release removes session")
	_check(restored.to_record()["sessions"].is_empty(), "empty sessions must not retain target ownership")
	var final_record: Dictionary = restored.to_record()
	_check(restored.release(_request("last", "session.crate", "body.human-1", 4)).is_success and restored.to_record() == final_record, "release retry after session deletion must acknowledge once")
	var malformed: Dictionary = owner.to_record()
	malformed["sessions"][0]["participants"].append(malformed["sessions"][0]["participants"][0].duplicate(true))
	_check(not PhysicalGripOwner.from_record(malformed).is_success, "duplicate participants in recovery must reject")
	malformed = owner.to_record()
	var duplicate: Dictionary = malformed["sessions"][0].duplicate(true)
	duplicate["session_id"] = "session.other"
	duplicate["target_id"] = "object.other"
	malformed["sessions"].append(duplicate)
	_check(not PhysicalGripOwner.from_record(malformed).is_success, "duplicate hand reservation across restored sessions must reject")
	malformed = owner.to_record()
	malformed["receipts"][0]["result_revision"] = 100
	_check(not PhysicalGripOwner.from_record(malformed).is_success, "future receipt revisions must reject")
	var detached: Dictionary = owner.to_record()
	detached["sessions"].clear()
	_check(not owner.to_record()["sessions"].is_empty(), "record observations must be detached")
	var separate: PhysicalGripOwner = PhysicalGripOwner.create("grips.separate-hands").value
	var other_hand: Dictionary = first.duplicate(true)
	other_hand["required_force_millinewtons"] = 0
	_check(separate.join(_request("left", "session.left", "body.human-1", 0), other_hand).is_success, "first hand can acquire a grip")
	other_hand["participants"][0]["free_hand_ids"] = ["hand.right"]
	_check(not separate.join(_request("same-target", "session.right", "body.human-1", 1), other_hand).is_success, "one target must not have competing sessions")
	other_hand["target_id"] = "object.other"
	_check(separate.join(_request("right", "session.right", "body.human-1", 1), other_hand).is_success, "distinct hands on the same body can hold different objects")
	var bounded: PhysicalGripOwner = PhysicalGripOwner.create("grips.bounded").value
	var simple: Dictionary = first.duplicate(true)
	simple["required_force_millinewtons"] = 0
	for cycle in range(65):
		_check(bounded.join(_request("join-%d" % cycle, "session.simple", "body.human-1", cycle * 2), simple).is_success, "bounded receipt setup join must succeed")
		_check(bounded.release(_request("release-%d" % cycle, "session.simple", "body.human-1", cycle * 2 + 1)).is_success, "bounded receipt setup release must succeed")
	_check(bounded.to_record()["receipts"].size() == 128, "receipt retention must be bounded")
	_check(not bounded.join(_request("join-0", "session.simple", "body.human-1", 0), simple).is_success, "evicted retry with stale revision must not replay")
	malformed = bounded.to_record()
	malformed["state_revision"] = PhysicalGripOwner.MAX_EXACT_INTEGER
	var exhausted: PhysicalGripOwner = PhysicalGripOwner.from_record(malformed).value
	_check(not exhausted.join(_request("exhausted", "session.simple", "body.human-1", PhysicalGripOwner.MAX_EXACT_INTEGER), simple).is_success, "revision exhaustion must reject new commits")
	if _failures == 0:
		print("Physical grip ownership, reservations, cooperative release and recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _request(id: String, session_id: String, body_id: String, revision: int) -> Dictionary:
	return {"request_id": id, "session_id": session_id, "body_id": body_id, "expected_revision": revision}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
