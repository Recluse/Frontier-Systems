extends SceneTree

## Snapshot/display contracts checked without GPU rendering or player authority.
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	var preview := ProceduralHabitatPreview.new()
	root.add_child(preview)
	var captured: ServiceResult = world.capture_world_snapshot_json()
	_check(captured.is_success, "world snapshot must be available before preview observations")
	var observation: ServiceResult = world.pressure_snapshot()
	_check(preview.observe_snapshot(observation.value).is_success, "preview must consume real pressure observation")
	_check(preview.presentation_snapshot()["inner_target_height"] == 1.2, "closed doors must be displayed at closed height")
	var record: Dictionary = observation.value.duplicate(true)
	record["inner_door_open"] = true
	_check(preview.observe_snapshot(record).is_success, "open-door observation must update display target")
	_check(preview.presentation_snapshot()["inner_target_height"] == 3.7, "open door must have a raised visual target")
	preview._process(0.1)
	_check((preview.get_node("InnerDoor") as MeshInstance3D).position.y > 1.2, "visual door must interpolate toward observed state")
	_check(world.capture_world_snapshot_json().value == captured.value, "display animation must not alter world state")
	var before: Dictionary = preview.presentation_snapshot()
	record["pressure_sensors"]["chamber"]["pressure_kpa_absolute"] = NAN
	_check(not preview.observe_snapshot(record).is_success, "nonfinite pressure observation must reject")
	_check(preview.presentation_snapshot() == before, "invalid observation must leave previous display targets intact")
	preview.camera.set_mode(HabitatInspectionCamera.Mode.FREE_LOOK)
	_check(preview.camera.position == Vector3(-4.0, 1.7, 0.0), "interior inspection camera must initialize near the chamber")
	preview.camera.set_mode(HabitatInspectionCamera.Mode.OVERVIEW)
	_check(preview.camera.position.distance_to(HabitatInspectionCamera.PIVOT) > 20.0, "overview must frame the cutaway from outside")
	_check(world.capture_world_snapshot_json().value == captured.value, "camera modes must not mutate canonical state")
	preview.free()
	world.free()
	# Headless bootstrap normally omits presentation; exercise its client layout
	# explicitly without requiring a GPU or a visible native window.
	root.size = Vector2i(1280, 800)
	var bootstrap := FrontierBootstrap.new()
	root.add_child(bootstrap)
	bootstrap.runtime_mode = FrontierBootstrap.RuntimeMode.CLIENT
	bootstrap._create_client_status_view()
	await process_frame
	await process_frame
	bootstrap._process(0.0)
	_check(bootstrap._habitat_preview != null, "client layout must create a preview")
	var view: Viewport = bootstrap._habitat_preview.get_viewport()
	_check(view is SubViewport and view.own_world_3d, "preview must use its own presentation world")
	_check(view.size.x > 100 and view.size.y > 100, "client layout must allocate usable preview space")
	bootstrap._set_preview_camera_mode(HabitatInspectionCamera.Mode.FREE_LOOK)
	_check(bootstrap._habitat_preview.camera.mode == HabitatInspectionCamera.Mode.FREE_LOOK, "panel camera control must reach the inspection camera")
	bootstrap.free()
	if _failures == 0:
		print("Procedural habitat preview scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
