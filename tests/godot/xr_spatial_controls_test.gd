extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	_check(world.start_simulation().is_success, "world must start")
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var panel := XRSpatialAirlockPanel.new()
	root.add_child(panel)
	_check(panel.configure(world).is_success and panel._buttons.size() == 8, "spatial panel must build the closed eight-control surface")
	var pointer := XRSpatialPointer.new()
	root.add_child(pointer)
	_check(pointer.configure(panel).is_success, "pointer must configure")
	await _frames()
	var area: Area3D = panel._buttons["open_equalization"]["area"]
	var ray_from: Vector3 = area.global_position + Vector3(0, 0, 1)
	var before: String = world.capture_world_snapshot_json().value
	_stage(pointer, ray_from, 1.0)
	await _frames()
	_check(panel._hovered == "open_equalization" and panel._pending.is_empty(), "real ray hit must highlight without accepting an initially held trigger")
	_check(world.capture_world_snapshot_json().value == before, "ray queries/highlights must not mutate canonical state")
	_stage(pointer, ray_from, 0.0)
	await _frames()
	_stage(pointer, ray_from, 1.0)
	await _frames()
	var pending: String = panel._pending
	_check(not pending.is_empty() and not world.pressure_snapshot().value["equalization_valve_open"], "selection must enqueue without applying before the world tick")
	_check(not panel.submit("open_vent").is_success and panel._pending == pending, "pending guard must prevent duplicate/spam commands")
	runner._physics_process(1.0 / 60.0)
	_check(world.pressure_snapshot().value["equalization_valve_open"] and panel._pending.is_empty(), "existing airlock command must apply at the fixed tick and report completion")
	before = world.capture_world_snapshot_json().value
	await _frames()
	_check(world.capture_world_snapshot_json().value == before and pointer.profiling_counters()["queued_selections"] == 1, "held trigger must not apply a second command")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = ray_from - Vector3(0, 0, 0.5)
	root.add_child(wall)
	XRSpatialAirlockPanel._shape(wall, Vector3(0.3, 0.3, 0.1))
	_stage(pointer, ray_from, 0.0)
	await _frames()
	_stage(pointer, ray_from, 1.0)
	await _frames()
	_check(panel._hovered.is_empty() and panel._pending.is_empty(), "nearer scene walls must occlude button selection")
	wall.free()
	await _frames()
	_check(panel._hovered == "open_equalization" and panel._pending.is_empty(), "moving onto a button with held trigger must not activate it")
	var spoof := Area3D.new()
	spoof.collision_layer = XRSpatialAirlockPanel.BUTTON_LAYER
	spoof.collision_mask = 0
	spoof.position = ray_from - Vector3(0, 0, 0.5)
	spoof.set_meta("xr_button_id", "open_equalization")
	root.add_child(spoof)
	XRSpatialAirlockPanel._shape(spoof, Vector3(0.3, 0.3, 0.1))
	_stage(pointer, ray_from, 0.0)
	await _frames()
	_stage(pointer, ray_from, 1.0)
	await _frames()
	_check(panel._pending.is_empty() and panel._hovered.is_empty(), "unregistered colliders cannot impersonate a panel button through metadata")
	spoof.free()
	pointer.stage_input(false, true, 0.0, ray_from, Vector3(0, 0, -1))
	await _frames()
	_stage(pointer, ray_from, 1.0)
	await _frames()
	_check(panel._pending.is_empty(), "focus regain with held trigger must require release")
	_stage(pointer, ray_from, 0.0)
	await _frames()
	pointer.reset_input()
	_check(not pointer._beam.visible and panel._hovered.is_empty(), "recenter reset must immediately hide stale pointer presentation")
	_stage(pointer, ray_from, 1.0)
	await _frames()
	_check(panel._pending.is_empty(), "recenter with held trigger must require a fresh release")
	_stage(pointer, ray_from, 0.0)
	pointer._sample_time_usec = Time.get_ticks_usec() - 300000
	await _frames()
	_check(not pointer._beam.visible and panel._hovered.is_empty(), "stale render samples must hide pointer and clear selection")
	_check(not pointer.stage_input(true, true, NAN, ray_from, Vector3(0, 0, -1)).is_success, "nonfinite input must reject")
	_check(not panel.submit("unregistered").is_success, "panel command surface must reject unknown IDs")
	_check(panel.submit("open_inner").is_success, "normal door operation must enqueue through the shared command")
	runner._physics_process(1.0 / 60.0)
	_check(not world.pressure_snapshot().value["inner_door_open"] and panel._feedback.text.begins_with("Rejected:"), "pressure/access interlocks must reject unsafe opening and show feedback")
	world.free()
	_stage(pointer, ray_from, 0.0)
	await _frames()
	_check(not panel.is_available() and panel._pending.is_empty() and not pointer._beam.visible and not panel.submit("open_equalization").is_success, "shutdown must disable pointer and command submission")
	pointer.free()
	panel.free()
	if _failures == 0:
		print("Spatial XR ray selection, occlusion and queued airlock authority scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _stage(pointer: XRSpatialPointer, ray_from: Vector3, trigger: float) -> void:
	_check(pointer.stage_input(true, true, trigger, ray_from, Vector3(0, 0, -1)).is_success, "valid pointer sample must stage")


func _frames() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
