extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/locomotion/push-off.default.v1.json"))
	var owner: LinearMotionOwner = LinearMotionOwner.create("motion.prototype", [fixture["actor"], fixture["target"]]).value
	var initial: Dictionary = owner.to_record()
	var request: Dictionary = _request("push-1", owner, fixture["impulse_micro_ns"])
	var committed: ServiceResult = owner.push_off(request, fixture["contact"], 1, 1)
	_check(committed.is_success, "paired impulse must commit")
	committed.value["fingerprint"] = "caller edit"
	_check(owner.to_record()["receipts"][0]["fingerprint"] != "caller edit", "returned receipts must be detached")
	_check(owner.to_record()["state_revision"] == 1 and owner.to_record()["last_commit_tick"] == 1, "owner revision and tick must advance together")
	var actor: Dictionary = owner.state_observation("body.human-1").value
	var target: Dictionary = owner.state_observation("assembly.salvage-crate").value
	_check(actor["state_revision"] == 1 and target["state_revision"] == 1 and actor["linear_momentum_micro_ns"][0] == 8000000 and target["linear_momentum_micro_ns"][0] == -8000000, "both body records must change atomically")
	var before: Dictionary = owner.to_record()
	_check(owner.push_off(JSON.parse_string(JSON.stringify(request)), {}, 99, 100).is_success and owner.to_record() == before, "retained normalized retry acknowledges without fresh contact or replay")
	_check(owner.profiling_counters()["retry_acknowledgements"] == 1, "retry profiling must count acknowledgement outside canonical state")
	var changed: Dictionary = request.duplicate(true)
	changed["impulse_micro_ns"][0] += 1
	_check(not owner.push_off(changed, fixture["contact"], 2, 2).is_success and owner.to_record() == before, "changed retained intent must reject atomically")
	changed = request.duplicate(true)
	changed["request_id"] = "competing"
	_check(not owner.push_off(changed, fixture["contact"], 2, 2).is_success, "competing stale owner revision must reject")
	changed = _request("stale-body", owner, fixture["impulse_micro_ns"])
	changed["expected_target_revision"] = 0
	_check(not owner.push_off(changed, fixture["contact"], 2, 2).is_success, "target revision must be checked separately")
	changed = _request("stale-contact", owner, fixture["impulse_micro_ns"])
	_check(not owner.push_off(changed, fixture["contact"], 1, 2).is_success, "old contact cannot authorize a new effect")
	var lost: Dictionary = fixture["contact"].duplicate(true)
	lost["capability_observation"]["participants"][0]["contact"] = false
	_check(not owner.push_off(_request("lost-contact", owner, fixture["impulse_micro_ns"]), lost, 2, 2).is_success and owner.to_record() == before, "contact failure must preserve both states and receipt history")
	var restored_result: ServiceResult = LinearMotionOwner.from_record(JSON.parse_string(JSON.stringify(owner.to_record())), 1)
	_check(restored_result.is_success, "committed state and receipts must recover through JSON")
	var restored: LinearMotionOwner = restored_result.value
	_check(restored.to_record() == before and restored.push_off(request, {}, -1, -1).is_success and restored.to_record() == before, "restored retry must not impart another impulse")
	_check(restored.push_off(_request("push-2", restored, fixture["impulse_micro_ns"]), fixture["contact"], 2, 2).is_success, "new fresh request may commit after recovery")
	_check(not restored.push_off(_request("past-tick", restored, fixture["impulse_micro_ns"]), fixture["contact"], 1, 1).is_success, "new effects cannot go back in tick time")
	var detached: Dictionary = restored.state_observation("body.human-1").value
	detached["linear_momentum_micro_ns"][0] = 0
	_check(restored.state_observation("body.human-1").value["linear_momentum_micro_ns"][0] == 16000000, "body observations must be detached")
	_check(restored.push_off(_request("same-tick", restored, fixture["impulse_micro_ns"]), fixture["contact"], 2, 2).is_success, "fresh successive revisions can commit within one tick")
	changed = _request("unknown-body", restored, fixture["impulse_micro_ns"])
	changed["target_body_id"] = "assembly.missing"
	_check(not restored.push_off(changed, fixture["contact"], 3, 3).is_success, "unregistered targets must reject")
	var bad: Dictionary = before.duplicate(true)
	bad["states"].append(bad["states"][0].duplicate(true))
	_check(not LinearMotionOwner.from_record(bad).is_success, "duplicate body identities must reject")
	bad = before.duplicate(true)
	bad["receipts"][0]["actor_revision"] = 2
	_check(not LinearMotionOwner.from_record(bad).is_success, "future receipt body revision must reject")
	_check(not LinearMotionOwner.from_record(before, 0).is_success, "future snapshot commits must reject")
	var overflow_target: Dictionary = fixture["target"].duplicate(true)
	overflow_target["mass_milligrams"] = LinearMotionState.MAX_MASS_MILLIGRAMS
	overflow_target["linear_momentum_micro_ns"] = [-LinearMotionState.MAX_MOMENTUM_MICRO_NS, 0, 0]
	var overflow_owner: LinearMotionOwner = LinearMotionOwner.create("motion.overflow", [fixture["actor"], overflow_target]).value
	var overflow_before: Dictionary = overflow_owner.to_record()
	_check(not overflow_owner.push_off(_request("overflow", overflow_owner, fixture["impulse_micro_ns"]), fixture["contact"], 1, 1).is_success and overflow_owner.to_record() == overflow_before, "target limit failure must not commit the valid actor side")
	var exhausted_target: Dictionary = fixture["target"].duplicate(true)
	exhausted_target["state_revision"] = LinearMotionState.MAX_EXACT_INTEGER
	var body_exhausted: LinearMotionOwner = LinearMotionOwner.create("motion.body-exhausted", [fixture["actor"], exhausted_target]).value
	var body_before: Dictionary = body_exhausted.to_record()
	_check(not body_exhausted.push_off(_request("body-exhausted", body_exhausted, fixture["impulse_micro_ns"]), fixture["contact"], 1, 1).is_success and body_exhausted.to_record() == body_before, "exhausted target revision must leave both states unchanged")
	var bounded: LinearMotionOwner = LinearMotionOwner.from_record(initial).value
	var first_request: Dictionary = {}
	for tick in range(1, 131):
		var intent: Dictionary = _request("bounded-%d" % tick, bounded, [1, 0, 0])
		if tick == 1:
			first_request = intent.duplicate(true)
		_check(bounded.push_off(intent, fixture["contact"], tick, tick).is_success, "bounded receipt setup must commit")
	_check(bounded.to_record()["receipts"].size() == 128, "receipt retention must remain bounded")
	_check(not bounded.push_off(first_request, fixture["contact"], 131, 131).is_success, "evicted stale request must not replay")
	_check(LinearMotionOwner.from_record(JSON.parse_string(JSON.stringify(bounded.to_record())), 130).is_success, "evicted receipt tail must remain recoverable")
	bad = bounded.to_record()
	bad["receipts"].pop_front()
	_check(not LinearMotionOwner.from_record(bad).is_success, "missing receipt inside the retention window must reject")
	bad = bounded.to_record()
	bad["state_revision"] = LinearMotionState.MAX_EXACT_INTEGER
	for index in range(128):
		bad["receipts"][index]["result_owner_revision"] = LinearMotionState.MAX_EXACT_INTEGER - 127 + index
	var exhausted: LinearMotionOwner = LinearMotionOwner.from_record(bad).value
	_check(not exhausted.push_off(_request("exhausted", exhausted, [1, 0, 0]), fixture["contact"], 131, 131).is_success, "exhausted owner revision must reject")
	if _failures == 0:
		print("Atomic linear motion, same-tick contact, retry and recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _request(id: String, owner: LinearMotionOwner, impulse: Array) -> Dictionary:
	return {"schema_version": 1, "request_id": id, "actor_body_id": "body.human-1", "target_body_id": "assembly.salvage-crate", "expected_owner_revision": owner.to_record()["state_revision"], "expected_actor_revision": owner.state_observation("body.human-1").value["state_revision"], "expected_target_revision": owner.state_observation("assembly.salvage-crate").value["state_revision"], "impulse_micro_ns": impulse.duplicate()}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
