extends "res://tests/godot/world_pointer_picking_test.gd"

## Dedicated actual-client held-look handoff; no target/button signal substitution.
func key(code: Key, pressed: bool, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.location = location
	event.pressed = pressed
	Input.parse_input_event(event)
	await settle()

func look(pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.window_id = root.get_window_id()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)
	await settle()

func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(25, 12)
	Input.parse_input_event(event)
	await settle()

func no_picks(count: int, label: String) -> void:
	check(picked_walls.size() == count and picked_items.is_empty() and picked_sources.is_empty() and workstation_picks == 0, label + " causes no unintended world selection")
	unchanged(label)

func run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: check(false, "Pointer fixture deadline"); quit(1))
	OS.set_environment("FRONTIER_EVENT_URL", "")
	OS.set_environment("FRONTIER_EVENT_TOKEN", "")
	PlayerInputSettings.instance()._reset_map()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 900)
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "detached canonical fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	# Pay for a physical wall through existing deterministic command/tick seams.
	for _batch in range(4):
		move(ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		for _tick in range(120): step()
	command("process", {"recipe_id": "craft.plate"})
	for _tick in range(120): step()
	command("materialize_plate", {})
	command("wall_build", {"item_id": frame()["production"]["components"][0], "position": [0, 0, -1000], "quarter_turn": 0})
	# Drop a real owned fixture backpack into the reachable tray.
	var drop := InventoryDevelopmentCommand.new()
	drop.command_id = &"pointer-fixture-drop"
	drop.authenticated_context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	drop.operation = "world"
	drop.payload = {"operation": "drop", "item_id": "backpack-1", "world_container_id": "world.tray-1", "destination_container_id": "", "slot_id": "", "expected_revision": frame()["inventory"]["inventory_revision"]}
	check(world.enqueue_command(drop).is_success, "fixture queues target backpack drop")
	step()
	check(last.is_success, "canonical backpack drop succeeds")
	client = PointerClient.new()
	root.add_child(client)
	client.set_process(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	var observation: Dictionary = frame()
	observation["position"] = [0, 950, 0]
	observation["players"] = []
	observation["terrain"] = {}
	check(remote._projection.accept_record(observation["production"]).is_success, "real client projection accepts fixture")
	remote._observation = observation.duplicate(true)
	remote.observation_received.emit(observation)
	remote.observation_received.emit(observation)
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)
	client._habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	client._habitat.camera.set_process(false)
	viewport = client._habitat.get_viewport()
	container = viewport.get_parent()
	for child in client._habitat.find_children("*", "Control", true, false):
		if child is HabitatTargetFeedback: feedback = child
	check(feedback != null, "actual habitat feedback exists")
	client._habitat.world_inventory.item_selected.connect(func(root_id: String, id: String) -> void: picked_items.append(JSON.stringify([root_id, id])))
	client._habitat.production.source_selected.connect(func(id: String) -> void: picked_sources.append(id))
	client._habitat.production.wall_selected.connect(func(id: String) -> void: picked_walls.append(id))
	client._habitat.production.workstation_selected.connect(func() -> void: workstation_picks += 1)
	await settle()
	canonical = world.capture_world_snapshot_json().value
	var wall_id: String = observation["production"]["walls"].keys()[0]
	var wall: StaticBody3D = client._habitat.production._spatial_walls[wall_id]
	await aim(wall)
	await world_click()
	var machinery: MachineryPanel = client._machinery_panel
	check(picked_walls == [wall_id] and machinery._selected(machinery._wall) == wall_id, "native wall pick opens real inspection")
	var scroll: ScrollContainer = machinery.get_parent()
	scroll.ensure_control_visible(machinery._new_wall)
	await settle()
	var world_point: Vector2 = container.get_global_rect().get_center()
	var controls: PlayerInputSettings = PlayerInputSettings.instance()
	await look(true, world_point)
	check(client._habitat.camera._looking, "RMB reaches actual nested camera")
	if DisplayServer.get_name() != "headless":
		check(controls.can_navigate(client._habitat.camera), "native RMB owns camera capture")
	await key(KEY_ALT, true, KEY_LOCATION_LEFT)
	check(Input.is_action_pressed("look") and Input.is_action_pressed("ui_cursor"), "RMB remains physically held during cursor handoff")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Left Alt exposes UI cursor")
	await key(KEY_ALT, false, KEY_LOCATION_LEFT)
	if DisplayServer.get_name() != "headless":
		check(controls.can_navigate(client._habitat.camera), "Alt release without editor restores held-look capture")
	await key(KEY_ALT, true, KEY_LOCATION_LEFT)
	var pose: Transform3D = client._habitat.camera.transform
	await pointer(machinery._new_wall.get_global_rect().get_center())
	check(Input.is_action_pressed("look") and client._habitat.camera._looking, "UI activation keeps RMB gesture held")
	check(machinery._selected(machinery._wall).is_empty() and machinery._coordinate_grid.visible and machinery._show_placement.button_pressed, "held-look pointer activates real new-wall button")
	check(root.gui_get_focus_owner() == machinery._axes[0].get_line_edit(), "real activation focuses coordinate editor")
	check(client._habitat.camera.transform == pose, "UI pointer movement does not rotate camera")
	no_picks(1, "held-look UI activation")
	await key(KEY_ALT, false, KEY_LOCATION_LEFT)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not controls.can_navigate(client._habitat.camera), "Alt release respects focused editor while RMB stays held")
	await motion(world_point)
	await world_click()
	check(client._habitat.camera.transform == pose and machinery._coordinate_grid.visible, "focused editor blocks look and world retargeting")
	no_picks(1, "focused editor after Alt release")
	scroll.ensure_control_visible(machinery._axes[0])
	await settle()
	check(root.gui_get_focus_owner() == machinery._axes[0].get_line_edit(), "capture retains real editor focus")
	await capture_editor()
	# Escape is dispatched with RMB still down and editor still focused.
	await key(KEY_ESCAPE, true)
	await key(KEY_ESCAPE, false)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and controls._owner == null and not client._habitat.camera._looking, "Escape clears camera gesture and global capture with editor focused")
	await motion(world_point)
	check(client._habitat.camera.transform == pose, "Escape prevents stale look motion")
	await look(false, machinery._new_wall.get_global_rect().get_center())
	no_picks(1, "Escape and RMB release over UI")
	root.gui_release_focus()
	await aim(wall)
	await world_click()
	check(picked_walls.size() == 2 and machinery._selected(machinery._wall) == wall_id, "world picking recovers after editor handoff")
	unchanged("world picking recovery")
	# Use the actual visible camera button, then sampled character physics.
	var first_person: Button
	for candidate in client.find_children("*", "Button", true, false):
		if candidate.text == "First person": first_person = candidate
	check(first_person != null, "actual First person button exists")
	await pointer(first_person.get_global_rect().get_center())
	root.gui_release_focus()
	var body: LocalHabitatCharacter = client._habitat.character
	check(body.navigation_enabled(), "pointer camera button activates real character")
	body.read_local_keyboard = true
	body.set_physics_process(true)
	await settle()
	await look(true, world_point)
	if DisplayServer.get_name() != "headless":
		check(controls.can_navigate(body), "fresh RMB captures actual character")
		var start: Vector3 = body.position
		await key(KEY_W, true)
		check(body.position.distance_to(start) > 0.1, "actual character samples held W")
	await key(KEY_ALT, true, KEY_LOCATION_LEFT)
	# Activate new-wall again while RMB remains held in character mode.
	scroll.ensure_control_visible(machinery._new_wall)
	await settle()
	check(scroll.get_global_rect().encloses(machinery._new_wall.get_global_rect()), "character handoff button is visible")
	await pointer(machinery._new_wall.get_global_rect().get_center())
	check(root.gui_get_focus_owner() == machinery._axes[0].get_line_edit(), "character held-look UI activation focuses editor")
	var start: Vector3 = body.position
	var yaw: float = body.rotation.y
	await key(KEY_W, true)
	await key(KEY_ALT, false, KEY_LOCATION_LEFT)
	await motion(world_point)
	check(Vector2(body.position.x - start.x, body.position.z - start.z).length() < 0.02 and body.rotation.y == yaw and body._axes == Vector2.ZERO, "focused editor suppresses held movement and look after Alt release")
	await key(KEY_ESCAPE, true)
	await key(KEY_ESCAPE, false)
	await key(KEY_W, false)
	await look(false, world_point)
	no_picks(2, "character editor and Escape")
	root.gui_release_focus()
	await look(true, world_point)
	await key(KEY_W, true)
	# Inject the same Window notification delivered by native focus loss, propagating
	# through the tree rather than calling individual body/control handlers.
	root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await settle()
	start = body.position
	yaw = body.rotation.y
	await motion(world_point)
	check(not body._looking and body._axes == Vector2.ZERO and controls._owner == null and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "window focus loss clears gesture/capture/movement")
	check(Vector2(body.position.x - start.x, body.position.z - start.z).length() < 0.02 and body.rotation.y == yaw, "held W and motion cannot resume after focus loss")
	root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await settle()
	check(not controls.can_navigate(body), "focus return alone does not recapture")
	await key(KEY_W, false)
	await look(false, world_point)
	await look(true, world_point)
	if DisplayServer.get_name() != "headless":
		start = body.position
		await key(KEY_W, true)
		check(controls.can_navigate(body) and body._axes == Vector2(0, -1), "fresh RMB and W recover keyboard sampling after focus loss")
		# W reaches an existing habitat collider; reverse to verify real motion.
		await key(KEY_W, false)
		await key(KEY_S, true)
		check(body.position.distance_to(start) > 0.1, "fresh gesture recovers real collision-aware movement")
		await key(KEY_S, false)
	await key(KEY_W, false)
	await look(false, world_point)
	start = body.position
	await motion(world_point)
	check(not body._looking and body._axes == Vector2.ZERO and controls._owner == null and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "final releases leave no stuck movement/look")
	no_picks(2, "focus loss and fresh gesture recovery")
	print("Held-look UI activation: %d failures; injected engine dispatch; native movement/capture %s; human/controller/VR unverified" % [failures, "exercised" if DisplayServer.get_name() != "headless" else "not run"])
	client.free()
	world.free()
	controls.release_all()
	controls._reset_map()
	quit(1 if failures else 0)

func capture_editor() -> void:
	if OS.get_cmdline_user_args().has("--capture-held-look"):
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://var/ci/held-look-ui-activation/captures")
		check(root.get_texture().get_image().save_png("res://var/ci/held-look-ui-activation/captures/editor-handoff.png") == OK, "ignored internal actual-client capture")
