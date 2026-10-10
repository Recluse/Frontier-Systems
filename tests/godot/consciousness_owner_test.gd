extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var owner: ConsciousnessOwner = ConsciousnessOwner.create("body.human1").value
	var causes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/health/suppression.combined.v1.json"))
	var request: Dictionary = _request(owner, "assessment.first", causes, 6)
	var result: ServiceResult = owner.assess(request, 6)
	_check(result.is_success and result.value["state"] == "unconscious" and result.value["transitioned"], "trusted combined causes must commit knockout")
	var saved: Dictionary = owner.to_record()
	var receipt: Dictionary = result.value.duplicate(true)
	result.value["state"] = "alert"
	_check(owner.to_record() == saved, "receipt observations must not alias owner state")
	var retry: Dictionary = request.duplicate(true)
	retry["causes"].reverse()
	_check(owner.assess(retry, 900).value == receipt and owner.to_record() == saved, "reordered equivalent retry must acknowledge without reapplying")
	retry["causes"][0]["suppression_permille"] = 999
	_check(not owner.assess(retry, 12).is_success and owner.to_record() == saved, "changed retained request must reject atomically")
	var wrong: Dictionary = _request(owner, "assessment.wrong-body", [], 12)
	wrong["body_id"] = "body.human2"
	_check(not owner.assess(wrong, 12).is_success, "other body must reject")
	wrong = _request(owner, "assessment.stale", [], 12)
	wrong["expected_state_revision"] = 0
	_check(not owner.assess(wrong, 12).is_success, "stale body revision must reject")
	_check(not owner.assess(_request(owner, "assessment.old", [], 6), 6).is_success, "already assessed tick must reject new effects")
	_check(not owner.assess(_request(owner, "assessment.not-fresh", [], 12), 13).is_success, "new effects require same-tick observation")
	_check(owner.to_record() == saved, "failed transactions must preserve canonical state and receipts")
	_check(owner.assess(_request(owner, "assessment.recovery", [], 12), 12).is_success, "safe assessment must start recovery")
	var recovery_record: Dictionary = owner.to_record()
	owner = ConsciousnessOwner.from_record(JSON.parse_string(JSON.stringify(recovery_record)), 12).value
	_check(owner.state_observation()["state"] == "unconscious" and owner.state_observation()["recovery_since_tick"] == 12, "JSON restore must retain unconscious recovery progress")
	_check(owner.assess(request, 18).is_success and owner.to_record() == recovery_record, "restored retained retry must acknowledge without rewinding")
	for tick in range(18, 73, 6):
		_check(owner.assess(_request(owner, "recovery-%d" % tick, [], tick), tick).is_success, "fresh safe assessments must commit")
	_check(owner.state_observation()["state"] == "alert", "owner must commit recovery after complete interval")
	var invalid: Dictionary = owner.to_record()
	invalid["receipts"].pop_back()
	_check(not ConsciousnessOwner.from_record(invalid).is_success, "missing receipt tail must reject")
	invalid = owner.to_record()
	invalid["receipts"][-1]["state"] = "unconscious"
	_check(not ConsciousnessOwner.from_record(invalid).is_success, "receipt state mismatch must reject")
	invalid = owner.to_record()
	invalid["receipts"][-1]["fingerprint"] = "z".repeat(64)
	_check(not ConsciousnessOwner.from_record(invalid).is_success, "invalid receipt fingerprint must reject")
	invalid = owner.to_record()
	invalid["receipts"][-1]["commit_tick"] = invalid["receipts"][-2]["commit_tick"]
	_check(not ConsciousnessOwner.from_record(invalid).is_success, "nonincreasing receipt ticks must reject")
	_check(not ConsciousnessOwner.from_record(owner.to_record(), 71).is_success, "future assessments must reject against snapshot tick")
	for tick in range(78, 480, 6):
		_check(owner.assess(_request(owner, "bounded-%d" % tick, [], tick), tick).is_success, "bounded history must continue committing")
	_check(owner.to_record()["receipts"].size() == ConsciousnessOwner.MAX_RECEIPTS, "receipt retention must remain bounded")
	owner = ConsciousnessOwner.from_record(JSON.parse_string(JSON.stringify(owner.to_record())), 474).value
	var before: Dictionary = owner.to_record()
	_check(not owner.assess(request, 480).is_success and owner.to_record() == before, "evicted old request must fail stale revision without replay")
	invalid = owner.to_record()
	invalid["receipts"][0]["state_revision"] -= 1
	_check(not ConsciousnessOwner.from_record(invalid).is_success, "receipt revision gap must reject")
	invalid = owner.to_record()
	invalid["receipts"][1]["request_id"] = invalid["receipts"][0]["request_id"]
	_check(not ConsciousnessOwner.from_record(invalid).is_success, "duplicate receipt IDs must reject")
	var observation: Dictionary = owner.state_observation()
	observation["body_id"] = "tampered"
	_check(owner.to_record() == before, "state observations must be detached")
	_check(owner.profiling_counters()["retained_receipts"] == 64 and owner.profiling_counters()["rejected_assessments"] == 1, "bounded volatile diagnostics must not enter canonical save")
	var fresh: ConsciousnessOwner = ConsciousnessOwner.create("body.human2").value
	invalid = fresh.to_record()
	invalid["state"]["last_assessed_tick"] = 6
	_check(not ConsciousnessOwner.from_record(invalid).is_success, "uncommitted initial owner must not invent assessment history")
	if _failures == 0:
		print("Consciousness atomic ownership, retry, saved recovery and bounded receipt scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _request(owner: ConsciousnessOwner, id: String, causes: Array, tick: int) -> Dictionary:
	var state: Dictionary = owner.state_observation()
	return {"schema_version": 1, "request_id": id, "body_id": state["body_id"],
		"expected_state_revision": state["state_revision"], "observed_tick": tick, "causes": causes.duplicate(true)}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
