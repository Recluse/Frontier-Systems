extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/locomotion/push-off.default.v1.json"))
	var before: Dictionary = fixture.duplicate(true)
	var planned: ServiceResult = _plan(fixture)
	_check(planned.is_success, "default push-off must plan")
	_check(fixture == before, "planning must not mutate input state or trusted observations")
	_check(planned.value["required_force_millinewtons"] == 80000, "required force must derive from impulse and duration, not the supplied zero")
	var actor: LinearMotionState = LinearMotionState.from_record(planned.value["actor_after"]).value
	var target: LinearMotionState = LinearMotionState.from_record(planned.value["target_after"]).value
	_check(is_equal_approx(actor.velocity_m_s()[0], 0.1) and is_equal_approx(target.velocity_m_s()[0], -8.0 / 120.0), "opposite reaction velocities must account for mass")
	for index in range(3):
		_check(planned.value["actor_after"]["linear_momentum_micro_ns"][index] + planned.value["target_after"]["linear_momentum_micro_ns"][index] == 0, "each axis must conserve momentum exactly")
	_check(LinearMotionState.from_record(JSON.parse_string(JSON.stringify(planned.value["actor_after"]))).is_success, "momentum records must round trip through JSON")
	var changed: Dictionary = fixture.duplicate(true)
	changed["actor"]["linear_momentum_micro_ns"] = [4000000, 3000000, 0]
	var moving: ServiceResult = _plan(changed)
	_check(moving.value["actor_after"]["linear_momentum_micro_ns"] == [12000000, 3000000, 0], "impulse must preserve existing tangential drift")
	changed = fixture.duplicate(true)
	changed["target"]["mass_milligrams"] = LinearMotionState.MAX_MASS_MILLIGRAMS
	var massive: ServiceResult = _plan(changed)
	_check(massive.is_success and massive.value["target_after"]["linear_momentum_micro_ns"][0] == -8000000, "massive assemblies still receive exact reaction momentum")
	changed["contact"]["capability_observation"]["movable"] = false
	_check(_plan(changed).is_success, "anchored geometry can push against its finite-mass backing assembly")
	changed = fixture.duplicate(true)
	changed["contact"]["capability_observation"]["participants"][0]["free_hand_ids"] = []
	_check(not _plan(changed).is_success, "push-off requires a usable hand")
	changed = fixture.duplicate(true)
	changed["contact"]["capability_observation"]["participants"][0]["contact"] = false
	_check(not _plan(changed).is_success, "lost contact must reject")
	changed = fixture.duplicate(true)
	changed["impulse_micro_ns"] = [21000000, 0, 0]
	_check(not _plan(changed).is_success, "claimed zero force must not bypass actual effort limits")
	changed = fixture.duplicate(true)
	changed["contact"]["capability_observation"]["contact_force_limit_millinewtons"] = 79999
	_check(not _plan(changed).is_success, "weak surfaces must limit impulses")
	changed = fixture.duplicate(true)
	changed["impulse_micro_ns"] = [-8000000, 0, 0]
	_check(not _plan(changed).is_success, "push-off cannot pull inward")
	changed["impulse_micro_ns"] = [8000000, 1, 0]
	_check(not _plan(changed).is_success, "unsupported tangential impulses must reject")
	changed["impulse_micro_ns"] = [0, 0, 0]
	_check(not _plan(changed).is_success, "zero impulse must not advance revisions")
	changed = fixture.duplicate(true)
	changed["contact"]["normal_permille"] = [600, 800, 0]
	changed["impulse_micro_ns"] = [4800000, 6400000, 0]
	_check(_plan(changed).is_success, "exact diagonal normals must preserve vector impulses")
	changed["contact"]["normal_permille"] = [600, 799, 0]
	_check(not _plan(changed).is_success, "nonunit normals must reject")
	changed = fixture.duplicate(true)
	changed["target"]["frame_id"] = "frame.other"
	_check(not _plan(changed).is_success, "different frames require explicit transformation")
	changed = fixture.duplicate(true)
	changed["target"]["body_id"] = changed["actor"]["body_id"]
	_check(not _plan(changed).is_success, "one body cannot push against itself as a second momentum owner")
	changed = fixture.duplicate(true)
	changed["contact"]["capability_observation"]["participants"][0]["body_id"] = "body.other"
	_check(not _plan(changed).is_success, "capability observations cannot substitute a different actor")
	changed = fixture.duplicate(true)
	changed["contact"]["capability_observation"]["target_id"] = "assembly.other"
	_check(not _plan(changed).is_success, "contact identity must match the actual momentum target")
	changed = fixture.duplicate(true)
	changed["actor"]["mass_milligrams"] = LinearMotionState.MAX_MASS_MILLIGRAMS
	changed["actor"]["linear_momentum_micro_ns"] = [LinearMotionState.MAX_MOMENTUM_MICRO_NS, 0, 0]
	_check(not _plan(changed).is_success, "momentum overflow must reject the whole plan")
	changed = fixture.duplicate(true)
	changed["contact"]["duration_microseconds"] = 33333
	changed["contact"]["capability_observation"]["participants"][0]["force_budget_millinewtons"] = 1000000
	changed["contact"]["capability_observation"]["contact_force_limit_millinewtons"] = 1000000
	_check(_plan(changed).value["required_force_millinewtons"] == 240003, "fractional force requirement must round upward with integer arithmetic")
	changed = fixture.duplicate(true)
	changed["actor"]["mass_milligrams"] = 0
	_check(not _plan(changed).is_success, "zero mass is invalid")
	changed = fixture.duplicate(true)
	changed["actor"]["state_revision"] = LinearMotionState.MAX_EXACT_INTEGER
	_check(not _plan(changed).is_success, "exhausted revisions must reject")
	changed = fixture.duplicate(true)
	changed["actor"]["mass_milligrams"] = 1
	_check(not _plan(changed).is_success, "resulting local speed must remain bounded")
	changed = fixture.duplicate(true)
	changed["impulse_micro_ns"] = [0.5, 0, 0]
	_check(not _plan(changed).is_success, "fractional impulse units must reject")
	if _failures == 0:
		print("Conservative push-off momentum and contact/effort boundary scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _plan(fixture: Dictionary) -> ServiceResult:
	return PushOffImpulsePlanner.plan(fixture["actor"], fixture["target"], fixture["contact"], fixture["impulse_micro_ns"])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
