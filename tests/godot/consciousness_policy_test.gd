extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/health/consciousness.default.v1.json"))
	var causes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/health/suppression.combined.v1.json"))
	var parsed: ServiceResult = ConsciousnessState.from_record(fixture)
	_check(parsed.is_success and ConsciousnessState.create_alert("body.human1").value.to_record() == parsed.value.to_record(), "default record must match alert constructor")
	var initial: ConsciousnessState = parsed.value
	var before: Dictionary = initial.to_record()
	var causes_before: Array = causes.duplicate(true)
	var plan: ServiceResult = ConsciousnessPolicy.plan(initial, causes, 6)
	_check(plan.is_success and plan.value["after"]["state"] == "unconscious" and plan.value["suppression_permille"] == 800 and not plan.value["consciousness_allows_voluntary_actions"], "injury and sedation must combine to knock out")
	_check(initial.to_record() == before and causes == causes_before, "planning must not mutate current state or inputs")
	var state: ConsciousnessState = ConsciousnessState.from_record(plan.value["after"]).value
	plan.value["after"]["causes"].clear()
	_check(state.to_record()["causes"].size() == 2, "saved records must be detached")
	var strong: Array = [_cause("injury.remaining", "injury", 800)]
	state = _next(state, strong, 12)
	_check(state.to_record()["state"] == "unconscious", "removing a chemical must not clear continuing injury")
	state = _next(state, [], 18)
	_check(state.to_record()["recovery_since_tick"] == 18, "safe assessment must start recovery without immediate waking")
	state = _next(state, [_cause("chemical.remaining", "chemical", 600)], 24)
	_check(state.to_record()["recovery_since_tick"] == -1, "renewed suppression must reset recovery")
	state = _next(state, [], 30)
	state = ConsciousnessState.from_record(JSON.parse_string(JSON.stringify(state.to_record()))).value
	for tick in range(36, 90, 6):
		state = _next(state, [], tick)
	_check(state.to_record()["state"] == "unconscious", "recovery must remain unconscious before sixty safe ticks")
	state = _next(state, [], 90)
	_check(state.to_record()["state"] == "alert" and state.to_record()["transition_tick"] == 90, "saved recovery must wake after a complete safe interval")
	state = _next(state, [_cause("chemical.light", "chemical", 250)], 96)
	_check(state.to_record()["state"] == "impaired", "impairment engage boundary must apply")
	state = _next(state, [_cause("chemical.light", "chemical", 200)], 102)
	_check(state.to_record()["state"] == "impaired", "impairment must retain hysteresis")
	state = _next(state, [_cause("chemical.light", "chemical", 150)], 108)
	_check(state.to_record()["state"] == "alert", "impairment release boundary must apply")
	state = _next(state, strong, 114)
	state = _next(state, [], 120)
	state = _next(state, [], 600)
	_check(state.to_record()["state"] == "unconscious" and state.to_record()["recovery_since_tick"] == 600, "missing assessments must not grant free recovery")
	_check(not ConsciousnessPolicy.plan(state, [], 600).is_success and not ConsciousnessPolicy.plan(state, [], 599).is_success, "same or old tick must reject replay")
	_check(not ConsciousnessPolicy.plan(state, [strong[0], strong[0]], 606).is_success, "duplicate cause IDs must reject")
	_check(not ConsciousnessPolicy.plan(state, [_cause("bad", "chemical", NAN)], 606).is_success, "nonfinite suppression must reject")
	_check(not ConsciousnessPolicy.plan(state, [_cause("bad", "unknown", 100)], 606).is_success, "unknown cause kinds must reject")
	var invalid: Dictionary = fixture.duplicate(true)
	invalid["unexpected"] = true
	_check(not ConsciousnessState.from_record(invalid).is_success, "extra fields must reject")
	invalid = state.to_record()
	invalid["recovery_since_tick"] = 601
	_check(not ConsciousnessState.from_record(invalid).is_success, "future recovery must reject")
	invalid = fixture.duplicate(true)
	invalid["causes"] = strong
	_check(not ConsciousnessState.from_record(invalid).is_success, "alert state with knockout-level suppression must reject")
	var many: Array = []
	for index in range(17):
		many.append(_cause("cause-%d" % index, "injury", 100))
	_check(not ConsciousnessPolicy.plan(state, many, 606).is_success, "cause capacity must be bounded")
	plan = ConsciousnessPolicy.plan(initial, [_cause("a", "injury", 1000), _cause("b", "chemical", 1000)], 6)
	_check(plan.value["suppression_permille"] == 1000, "combined suppression must saturate")
	var boundary: ConsciousnessState = _next(initial, [_cause("injury.boundary", "injury", 750)], 6)
	_check(boundary.to_record()["state"] == "unconscious", "exact knockout boundary must apply")
	boundary = _next(boundary, [_cause("chemical.boundary", "chemical", 500)], 12)
	_check(boundary.to_record()["recovery_since_tick"] == 12, "exact recovery threshold must start an interval")
	for tick in range(18, 73, 6):
		boundary = _next(boundary, [_cause("chemical.boundary", "chemical", 500)], tick)
	_check(boundary.to_record()["state"] == "impaired", "recovery with residual suppression must wake impaired")
	_check(not ConsciousnessPolicy.plan(initial, [_cause("bad", "injury", 250.5)], 6).is_success, "fractional suppression must reject")
	var detached: Dictionary = boundary.to_record()
	detached["state"] = "unconscious"
	_check(boundary.to_record()["state"] == "impaired", "record observations must not mutate the stored state")
	invalid = fixture.duplicate(true)
	invalid["state_revision"] = ConsciousnessState.MAX_INTEGER
	_check(not ConsciousnessPolicy.plan(ConsciousnessState.from_record(invalid).value, [], 6).is_success, "revision exhaustion must reject")
	if _failures == 0:
		print("Consciousness combined causes, recovery, hysteresis and record validation scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _next(state: ConsciousnessState, causes: Array, tick: int) -> ConsciousnessState:
	var planned: ServiceResult = ConsciousnessPolicy.plan(state, causes, tick)
	_check(planned.is_success, "assessment must plan at tick %d" % tick)
	return ConsciousnessState.from_record(planned.value["after"]).value if planned.is_success else state


func _cause(id: String, kind: String, strength: Variant) -> Dictionary:
	return {"cause_id": id, "kind": kind, "suppression_permille": strength}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
