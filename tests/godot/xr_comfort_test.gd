extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var policy := XRComfortPolicy.create_default()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/xr/comfort.default.v1.json"))
	_check(XRComfortPolicy.from_record(fixture).value.to_record() == policy.to_record(), "default fixture and policy settings must agree")
	_check(policy.sample_input(_input(0.9)).value["yaw_degrees"] == 0, "initially held stick must not turn before neutral")
	policy.sample_input(_input(0.0))
	_check(policy.sample_input(_input(0.8)).value["yaw_degrees"] == -30, "right input must produce one configured right snap")
	_check(policy.sample_input(_input(0.9)).value["yaw_degrees"] == 0 and policy.sample_input(_input(-0.9)).value["yaw_degrees"] == 0, "holding or reversing without neutral must not repeat")
	policy.sample_input(_input(0.2))
	_check(policy.sample_input(_input(-0.8)).value["yaw_degrees"] == 30, "neutral release must rearm left snap")
	policy.sample_input(_input(0.0))
	var lost: Dictionary = _input(0.0)
	lost["session_focused"] = false
	policy.sample_input(lost)
	_check(policy.sample_input(_input(0.9)).value["yaw_degrees"] == 0, "focus restoration with held stick must not turn")
	policy.sample_input(_input(0.0))
	lost = _input(0.0)
	lost["right_tracked"] = false
	policy.sample_input(lost)
	_check(policy.sample_input(_input(0.9)).value["yaw_degrees"] == 0, "tracking restoration must require neutral")
	var invalid: Dictionary = _input(NAN)
	_check(not policy.sample_input(invalid).is_success, "nonfinite axes must reject")
	invalid = XRComfortPolicy.DEFAULTS.duplicate(true)
	invalid["turn_release_permille"] = invalid["turn_engage_permille"]
	_check(not XRComfortPolicy.from_record(invalid).is_success, "thresholds must have hysteresis")
	invalid = XRComfortPolicy.DEFAULTS.duplicate(true)
	invalid["seated_height_offset_mm"] = 1001
	_check(not XRComfortPolicy.from_record(invalid).is_success, "height offsets must be bounded")
	var disabled: Dictionary = XRComfortPolicy.DEFAULTS.duplicate(true)
	disabled["snap_turn_degrees"] = 0
	var no_turn: XRComfortPolicy = XRComfortPolicy.from_record(disabled).value
	no_turn.sample_input(_input(0.0))
	_check(no_turn.sample_input(_input(1.0)).value["yaw_degrees"] == 0, "snap turning must be disableable")
	policy = XRComfortPolicy.create_default()
	policy.sample_input(_input(0.0))
	var buttons: Dictionary = _input(0.0)
	buttons["seated_pressed"] = true
	_check(policy.sample_input(buttons).value["toggle_seated"] and not policy.sample_input(buttons).value["toggle_seated"], "seated input must trigger once per press")
	lost["left_tracked"] = false
	policy.sample_input(lost)
	_check(not policy.sample_input(buttons).value["toggle_seated"], "tracking loss must reset held button gates")
	var path: String = "user://xr-comfort-test-%s-%s.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	_check(XRComfortPolicy.load_preferences(path).value.to_record() == XRComfortPolicy.DEFAULTS, "missing preferences must use defaults")
	_check(policy.save_preferences(path).is_success, "preferences must save")
	var seated: Dictionary = XRComfortPolicy.DEFAULTS.duplicate(true)
	seated["seated_mode"] = true
	seated["seated_height_offset_mm"] = 650
	var saved: XRComfortPolicy = XRComfortPolicy.from_record(seated).value
	_check(saved.save_preferences(path).is_success, "existing preferences must replace atomically on Windows")
	_check(XRComfortPolicy.load_preferences(path).value.to_record() == seated, "saved preferences must normalize through JSON recovery")
	_check(not saved.save_preferences("user://../escape.json").is_success, "preference paths must not escape the user leaf")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("x".repeat(XRComfortPolicy.MAX_BYTES + 1))
	file.close()
	_check(not XRComfortPolicy.load_preferences(path).is_success, "oversized preferences must reject")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	_check(not XRComfortPolicy.load_preferences(path).is_success, "malformed local JSON must reject")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	var world := WorldRuntime.new()
	root.add_child(world)
	world.start_simulation()
	world.get_node("SimulationRunner").set_physics_process(false)
	var before: String = world.capture_world_snapshot_json().value
	var rig := OptionalXRClient.new()
	root.add_child(rig)
	rig.build_preview()
	rig.camera.position = Vector3(0.6, 1.3, 0.4)
	var pivot: Vector3 = rig.camera.global_position
	_check(rig.apply_snap_turn(-30).is_success and rig.camera.global_position.distance_to(pivot) < 0.00001, "snap rotation must preserve the headset pivot with room-scale offset")
	_check(rig.apply_comfort_settings(seated, false).is_success and is_equal_approx(rig.origin.position.y, 0.65), "seated settings must shift the whole tracked origin")
	rig.consume_comfort_input(_input(0.0), false)
	var height: Dictionary = _input(0.0)
	height["height_up_pressed"] = true
	rig.consume_comfort_input(height, false)
	_check(rig._comfort.to_record()["seated_height_offset_mm"] == 700, "height button must apply one bounded increment")
	rig.consume_comfort_input(height, false)
	_check(rig._comfort.to_record()["seated_height_offset_mm"] == 700, "held height input must not repeat or resave")
	var warning: ServiceResult = rig.apply_comfort_settings(seated, true, "user://../escape.json")
	_check(warning.is_success and not warning.value["preferences_saved"] and warning.value["warning"] != "" and is_equal_approx(rig.origin.position.y, 0.65), "save failure must report feedback while retaining the applied view setting")
	_check(world.capture_world_snapshot_json().value == before and Engine.physics_ticks_per_second == 60, "comfort changes must preserve world state and simulation rate")
	rig.free()
	world.free()
	if _failures == 0:
		print("XR comfort input gates, pivot transforms and local preference recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _input(axis: float) -> Dictionary:
	return {"schema_version": 1, "turn_axis": axis, "session_focused": true, "left_tracked": true, "right_tracked": true, "seated_pressed": false, "height_up_pressed": false, "height_down_pressed": false}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
