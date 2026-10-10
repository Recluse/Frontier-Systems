extends SceneTree

## Real local physics against snapshot-driven barriers; no GPU or keyboard required.
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	var pressure := world.get_simulation_system(PressureSystem.SYSTEM_ID) as PressureSystem
	for volume: PressureVolumeState in pressure.volumes.values():
		volume.gas_moles = 0.0
	var preview := ProceduralHabitatPreview.new()
	root.add_child(preview)
	_check(preview.observe_snapshot(world.pressure_snapshot().value).is_success, "closed-door observation must apply")
	preview.character.read_local_keyboard = false
	preview.activate_character(LocalHabitatCharacter.CameraMode.FIRST_PERSON)
	await _frames(20)
	_check(preview.character.is_on_floor(), "capsule must settle on procedural habitat floor")
	_check(not preview.character._mesh.visible and preview.character._arm.spring_length == 0.0, "first person must hide body and retract camera arm")
	_check(not preview.character.set_motion_intent(Vector2(NAN, 0.0), false).is_success, "nonfinite movement must reject")
	_check(preview.character.set_motion_intent(Vector2(1.0, -1.0), false).is_success and preview.character._axes.length() <= 1.000001, "diagonal intent must normalize")
	preview.character.set_motion_intent(Vector2(0.0, -1.0), false)
	await _frames(80)
	_check(preview.character.position.x > -3.0 and preview.character.position.x < -1.1, "walking must advance but stop at the closed inner barrier")
	_check(_door(world, AirlockState.Action.OPEN_INNER).is_success, "physical test fixture must open door through a real command")
	preview.observe_snapshot(world.pressure_snapshot().value)
	await _frames(40)
	_check(preview.character.position.x > -0.5 and preview.character.position.x < 0.9, "open inner door must permit chamber entry while closed outer door still blocks")
	preview.character.set_motion_intent(Vector2.ZERO, false)
	var before: ServiceResult = world.capture_world_snapshot_json()
	preview.activate_character(LocalHabitatCharacter.CameraMode.THIRD_PERSON)
	_check(preview.character._mesh.visible and preview.character._arm.spring_length == 3.0, "third person must show body and extend collision-aware arm")
	_check(_door(world, AirlockState.Action.CLOSE_INNER).is_success, "door must close behind the local body")
	preview.observe_snapshot(world.pressure_snapshot().value)
	await _frames(4)
	_check(preview.character._arm.get_hit_length() < 3.0, "third-person camera arm must shorten against closed door behind body")
	before = world.capture_world_snapshot_json()
	preview.activate_character(LocalHabitatCharacter.CameraMode.FIRST_PERSON)
	preview.character.set_motion_intent(Vector2.ZERO, true)
	var standing_y: float = preview.character.position.y
	await _frames(8)
	_check(preview.character.position.y > standing_y + 0.05, "grounded local jump must lift the body")
	_check(world.capture_world_snapshot_json().value == before.value, "local movement and camera changes must not change world state")
	preview.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	_check(not preview.character.is_physics_processing() and preview.camera.current, "inspection mode must release character controls and camera")
	preview.free()
	world.free()
	if _failures == 0:
		print("Local character collision and camera scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _door(world: WorldRuntime, action: int) -> ServiceResult:
	var command := AirlockCommand.new()
	command.command_id = world.next_local_request_id()
	command.airlock_id = WorldRuntime.PROTOTYPE_AIRLOCK_ID
	command.action = action
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(&"test-operator", world.world_id, world.region_id)
	return command.execute(world)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
