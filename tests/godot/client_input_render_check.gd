extends SceneTree

## Injected Godot events exercise actual handlers and keyboard sampling, not physical input.
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var controls := PlayerInputSettings.instance()
	controls._reset_map() # In memory only; never save a player's settings.
	var world := WorldRuntime.new()
	root.add_child(world)
	var preview := ProceduralHabitatPreview.new()
	root.add_child(preview)
	check(preview.observe_snapshot(world.pressure_snapshot().value).is_success, "fixture observation applies")
	preview.activate_character(LocalHabitatCharacter.CameraMode.FIRST_PERSON)
	var body: LocalHabitatCharacter = preview.character
	await frames(20)
	check(body.read_local_keyboard, "fixture retains real keyboard sampling")
	var before: String = world.capture_world_snapshot_json().value
	mouse(true)
	await frames(2)
	check(controls.can_navigate(body), "RMB event captures the actual character")
	var start: Vector3 = body.position
	key(KEY_W, true)
	await frames(12)
	key(KEY_W, false)
	check(body.position.distance_to(start) > 0.2, "held W is sampled by real character physics")
	var yaw: float = body.rotation.y
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(30, 10)
	Input.parse_input_event(motion)
	await frames(2)
	check(absf(angle_difference(yaw, body.rotation.y)) > 0.05 and body._pitch < 0.0, "mouse motion changes actual yaw and pitch")
	key(KEY_ALT, true, KEY_LOCATION_LEFT)
	await frames(2)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not controls.can_navigate(body), "Alt releases cursor ownership")
	start = body.position
	key(KEY_W, true)
	await frames(8)
	key(KEY_W, false)
	check(Vector2(body.position.x - start.x, body.position.z - start.z).length() < 0.02, "movement is suppressed during cursor handoff")
	key(KEY_ALT, false, KEY_LOCATION_LEFT)
	await frames(2)
	check(controls.can_navigate(body), "releasing Alt while RMB held recaptures")
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await frames(2)
	check(not controls.can_navigate(body) and not body._looking, "Escape releases both ownership and look handler")
	mouse(false)
	mouse(true)
	await frames(2)
	body.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	controls.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not body._looking and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "focus-loss notifications release capture")
	mouse(false)
	mouse(true)
	await frames(2)
	check(controls.can_navigate(body), "fresh RMB after focus loss recovers navigation")
	controls.rebinding = true
	controls.release_all()
	mouse(false)
	mouse(true)
	await frames(2)
	check(not controls.can_navigate(body), "rebinding prevents recapture")
	controls.rebinding = false
	mouse(false)
	check(world.capture_world_snapshot_json().value == before, "local input fixture leaves canonical state unchanged")
	# A real focused button receives viewport-dispatched keyboard activation.
	var button := Button.new()
	button.text = "Input acceptance fixture"
	root.add_child(button)
	var activations: Array[int] = [0]
	button.pressed.connect(func() -> void: activations[0] += 1)
	button.grab_focus()
	await process_frame
	await process_frame
	key(KEY_ENTER, true)
	key(KEY_ENTER, false)
	await process_frame
	await process_frame
	check(activations[0] == 1, "focused visible button activates through injected keyboard events")
	button.free()
	preview.free()
	world.free()
	controls.release_all()
	# Build the actual client's viewport/UI with an invalid empty invite. Validation
	# rejects before socket connect; no host or port reservation is needed here.
	var previous_key: String = OS.get_environment("FRONTIER_INVITE_KEY")
	OS.set_environment("FRONTIER_INVITE_KEY", "")
	var client := FirstPlayableBootstrap.new()
	root.add_child(client)
	await process_frame
	await process_frame
	var camera_button: Button
	for candidate in client.find_children("*", "Button", true, false):
		if candidate.text == "First person": camera_button = candidate
	check(camera_button != null, "actual client builds its visible camera button")
	if camera_button != null:
		camera_button.grab_focus()
		key(KEY_ENTER, true)
		key(KEY_ENTER, false)
		await process_frame
		await process_frame
		camera_button.release_focus()
		body = client._habitat.character
		check(body.navigation_enabled() and body.read_local_keyboard, "actual visible camera button activates keyboard-sampled character")
		mouse(true, Vector2(1500, 600))
		await frames(2)
		check(controls.can_navigate(body), "actual client nested viewport receives injected RMB")
		start = body.position
		key(KEY_W, true)
		await frames(12)
		key(KEY_W, false)
		check(body.position.distance_to(start) > 0.2, "actual client nested character walks from sampled keyboard")
		mouse(false, Vector2(1500, 600))
		key(KEY_I, true)
		key(KEY_I, false)
		await process_frame
		await process_frame
		check(client._tabs.current_tab == 1, "actual client inventory hotkey reaches visible tab")
		key(KEY_F10, true)
		key(KEY_F10, false)
		await process_frame
		await process_frame
		check(client._tabs.current_tab == 2, "actual client settings hotkey reaches visible tab")
	client.free()
	OS.set_environment("FRONTIER_INVITE_KEY", previous_key)
	if failures == 0:
		print("Injected actual-handler keyboard/look/cursor/focus acceptance passed; physical input and human acceptance unverified.")
	quit(0 if failures == 0 else 1)


func key(code: Key, pressed: bool, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.location = location
	event.pressed = pressed
	Input.parse_input_event(event)


func mouse(pressed: bool, position: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)


func frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
