extends "res://tests/godot/first_playable_client_render_check.gd"

## Actual client with injected input/GUI activation. Never physical or human acceptance.
var _failed: bool = false
var _last_ui_outcome: Dictionary = {}


func _run() -> void:
	if not OS.get_cmdline_user_args().has("--ports-reserved"):
		push_error("Coordinator reservation of 27850 required before binding.")
		quit(1)
		return
	PlayerInputSettings.instance()._reset_map()
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:27850")
	OS.set_environment("FRONTIER_INVITE_KEY", "render-player-one-key-000000000000000")
	var directory: String = "user://client-ui-acceptance-%d" % Time.get_ticks_usec()
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	var store := WorldPersistenceAdapter.new()
	root.add_child(store)
	var host := FirstPlayableHost.new()
	host.persistence = store
	root.add_child(host)
	var keys: Array[String] = [OS.get_environment("FRONTIER_INVITE_KEY"), "render-player-two-key-000000000000000"]
	if not store.configure(world, directory).is_success or not host.configure(world, keys, 27850).is_success or not world.start_simulation().is_success:
		push_error("Fresh host/persistence fixture failed.")
		quit(1)
		return
	var client := FirstPlayableBootstrap.new()
	root.add_child(client)
	client._remote.terrain_retry_directory = directory.path_join("retry")
	if not await _wait_until(func() -> bool: return client._production_panel != null, 5.0):
		_failed = true
	else:
		await _exercise(client)
	if not _failed:
		client._open_panel(0)
		var persisted: Dictionary = {}
		client._remote.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void:
			if command is CheckpointRequest:
				persisted["success"] = result.is_success
				persisted["visible"] = client._checkpoint_status.text == "Shared world checkpoint confirmed on disk."
		)
		if not await _wait_until(func() -> bool: return not store.status()["busy"], 4.0): _failed = true
		if not _failed and not await _press_named(client._content, "Save shared world now"): _failed = true
		if not _failed and not await _wait_until(func() -> bool: return persisted.has("success"), 5.0): _failed = true
		if not _failed and (not persisted["success"] or not persisted["visible"]):
			push_error("Save did not report a successful visible disk acknowledgement.")
			_failed = true
		var latest: ServiceResult = LocalWorldSaveStore.read_latest(directory)
		if not _failed and (not latest.is_success or latest.value.is_empty()): _failed = true
		if not _failed:
			var expected: Dictionary = client._latest.duplicate(true)
			# Observe the real disconnect handler before restarting client/host.
			host.free()
			if not await _wait_until(func() -> bool: return client._latest.is_empty() and client._status.text == "Host connection closed", 4.0): _failed = true
			client.free()
			store.free()
			world.free()
			world = WorldRuntime.new()
			world.resource_carriers_enabled = true
			root.add_child(world)
			store = WorldPersistenceAdapter.new()
			root.add_child(store)
			host = FirstPlayableHost.new()
			host.persistence = store
			root.add_child(host)
			if not store.configure(world, directory).is_success or not host.configure(world, keys, 27850).is_success or not world.start_simulation().is_success: _failed = true
			client = FirstPlayableBootstrap.new()
			root.add_child(client)
			client._remote.terrain_retry_directory = directory.path_join("retry-reconnected")
			if not await _wait_until(func() -> bool: return not client._latest.is_empty(), 5.0): _failed = true
			if not _failed:
				var restored: Dictionary = client._latest
				if restored["production"]["deposits"] != expected["production"]["deposits"] or restored["production"]["walls"] != expected["production"]["walls"] or restored["production"]["structures"] != expected["production"]["structures"] or restored["inventory"]["items"] != expected["inventory"]["items"] or restored["production"]["store"] != expected["production"]["store"]:
					push_error("Actual restarted client differs from durable finite resources, construction or inventory.")
					_failed = true
				else:
					print("Actual-client save UI acknowledgement, disconnect clearing, startup reconnect and durable depletion/items/walls/equipment passed. No reconnect button exists; client restart is injected.")
	if not _failed:
		await RenderingServer.frame_post_draw
		var capture: String = OS.get_environment("FRONTIER_VERIFICATION_CAPTURE_DIRECTORY")
		if capture.is_empty(): capture = "res://var/ci/render-client-acceptance/capture"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture))
		if root.get_texture().get_image().save_png(capture.path_join("client.png")) != OK: _failed = true
	client.free()
	host.free()
	store.free()
	world.free()
	PlayerInputSettings.instance().release_all()
	print("Injected real-client UI acceptance %s; human tutorial gate remains open." % ("FAILED" if _failed else "PASSED"))
	quit(1 if _failed else 0)


func _exercise(client: FirstPlayableBootstrap) -> void:
	if not client._habitat.character.read_local_keyboard:
		push_error("Acceptance must retain keyboard sampling.")
		_failed = true
		return
	_key(KEY_F1, true)
	_key(KEY_F1, false)
	await process_frame
	await process_frame
	if not await _wait_until(func() -> bool: return client._habitat.character.navigation_enabled()): _failed = true
	_key(KEY_I, true)
	_key(KEY_I, false)
	await process_frame
	await process_frame
	if not await _wait_until(func() -> bool: return client._tabs.current_tab == 1): _failed = true
	_key(KEY_I, true)
	_key(KEY_I, false)
	await process_frame
	await process_frame
	if not await _wait_until(func() -> bool: return not client._tabs.visible): _failed = true
	if _failed: return
	print("Acceptance walk to ore")
	if not await _walk(client, Vector3(-9, 0.95, 1)): _failed = true; return
	for _collection in range(2):
		if not await _guide_action(client): _failed = true; return
	if not await _walk(client, Vector3(-6, 0.95, 2)): _failed = true; return
	for _step in range(8):
		if not await _guide_action(client): _failed = true; return
	if not client._production_panel._guide._recrafted: _failed = true; return
	if not await _collect_reprinted_plate(client): _failed = true; return
	if not await _wait_until(func() -> bool: return client._latest["production"]["components"].size() == 1): _failed = true; return
	# Extra paid material for a carrier; all extraction/refinement use visible controls.
	for _batch in range(2):
		print("Acceptance walk to ore")
		if not await _walk(client, Vector3(-9, 0.95, 1)): _failed = true; return
		if not await _press(client._production_panel._extract_button): _failed = true; return
		if not await _wait_until(func() -> bool: return client._production_panel._pending.is_empty()): _failed = true; return
		if not await _walk(client, Vector3(-6, 0.95, 2)): _failed = true; return
		for index in range(client._production_panel._cargo_material.item_count):
			if client._production_panel._cargo_material.get_item_text(index) == "ore.iron": client._production_panel._cargo_material.select(index)
		if not await _press_named(client._production_panel, "Unload selected mass to workstation"): _failed = true; return
		if not await _wait_until(func() -> bool: return client._production_panel._pending.is_empty()): _failed = true; return
		_select(client._production_panel._recipe, "refine.iron")
		if not await _press_named(client._production_panel, "Run selected recipe"): _failed = true; return
		if not await _wait_until(func() -> bool: return client._production_panel._pending.is_empty() and client._latest["production"]["job"].is_empty(), 5.0): _failed = true; return
	_select(client._production_panel._blueprint, "equipment.canister")
	if not await _press(client._production_panel._fabricate_button): _failed = true; return
	if not await _wait_until(func() -> bool: return client._latest["production"]["structures"].size() == 1):
		push_error("Equipment fabrication: " + client._production_panel._feedback.text)
		_failed = true
		return
	client._open_panel(3)
	var panel: MachineryPanel = client._machinery_panel
	_select_wall_plate(panel, client._latest["production"]["components"][0])
	panel._axes[0].value = 0
	panel._axes[1].value = 0
	panel._axes[2].value = -1
	if not await _press(panel._wall_build_button): _failed = true; return
	if not await _wait_until(func() -> bool: return client._latest["production"]["walls"].size() == 1): _failed = true; return
	var id: String = client._latest["production"]["walls"].keys()[0]
	if not client._habitat.production._spatial_walls.has(id): _failed = true; return
	panel.select_wall(id) # Fixture selection, not pointer/world picking acceptance.
	if not await _press(panel._wall_remove_button): _failed = true; return
	if not await _wait_until(func() -> bool: return client._latest["production"]["walls"].is_empty() and client._latest["production"]["components"].size() == 1): _failed = true; return
	_select_wall_plate(panel, client._latest["production"]["components"][0])
	if not await _press(panel._wall_build_button): _failed = true; return
	if not await _wait_until(func() -> bool: return client._latest["production"]["walls"].size() == 1): _failed = true; return
	if client._latest["production"]["deposits"]["deposit.iron"] != 6000000:
		push_error("Finite UI extraction did not consume exactly 4 kg ore.")
		_failed = true
	print("Actual keyboard-sampled walking, visible guide/equipment/wall buttons, finite fabrication/removal/rebuild exercised. Selector choices and wall coordinates are fixture-injected.")


func _walk(client: FirstPlayableBootstrap, target: Vector3) -> bool:
	var body: LocalHabitatCharacter = client._habitat.character
	client._open_panel(0)
	root.gui_release_focus()
	client._habitat.activate_character(LocalHabitatCharacter.CameraMode.FIRST_PERSON)
	_mouse(true)
	await physics_frame
	if not PlayerInputSettings.instance().can_navigate(body):
		push_error("Real client failed RMB capture.")
		_mouse(false)
		return false
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var delta := Vector2(target.x - body.position.x, target.z - body.position.z)
		if delta.length() < 0.18: break
		var motion := InputEventMouseMotion.new()
		motion.relative.x = -angle_difference(body.rotation.y, atan2(-delta.x, -delta.y)) / PlayerInputSettings.instance().sensitivity
		Input.parse_input_event(motion)
		_key(KEY_W, true)
		await physics_frame
	_key(KEY_W, false)
	_mouse(false)
	await create_timer(0.35).timeout # Wait for authoritative movement projection.
	var reached: bool = Vector2(target.x - body.position.x, target.z - body.position.z).length() < 0.25
	if not reached: push_error("Injected keyboard route failed to reach " + str(target))
	return reached


func _guide_action(client: FirstPlayableBootstrap) -> bool:
	for _attempt in range(3):
		var revision: int = client._latest["production"]["state_revision"]
		if not await _press(client._production_panel._guide_button, true): return false
		if not await _wait_until(func() -> bool: return client._production_panel._pending.is_empty(), 6.0): return false
		if client._production_panel._feedback.text.begins_with("Rejected"):
			if client._production_panel._feedback.text.contains("revision is stale"):
				print("Visible stale-revision rejection; wait for fresh observation and retry through the same UI.")
				if not await _wait_until(func() -> bool: return client._latest["production"]["state_revision"] > revision): return false
				continue
			push_error("Actual guide rejected: " + client._production_panel._feedback.text)
			return false
		if not await _wait_until(func() -> bool: return client._latest["production"]["state_revision"] > revision and client._production_panel._guide._requested_recipe.is_empty(), 6.0): return false
		return true
	push_error("Guide exhausted bounded stale-revision retries.")
	return false

func _press(button: Button, allow_stale_retry: bool = false) -> bool:
	_last_ui_outcome.clear()
	PlayerInputSettings.instance().release_all()
	if button != null:
		_reveal_task_section(button)
		await process_frame
		await process_frame
	if button != null and button.is_visible_in_tree() and button.disabled:
		if not await _wait_until(func() -> bool: return not button.disabled, 3.0):
			push_error("Button remained disabled: " + button.text)
			return false
	if button == null or not button.is_visible_in_tree() or button.disabled:
		push_error("Visible enabled button required for UI acceptance.")
		return false
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await process_frame
	await process_frame
	button.grab_focus()
	ancestor = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await process_frame
	await process_frame
	if not button.has_focus() or not Rect2(Vector2.ZERO, Vector2(root.size)).intersects(button.get_global_rect()):
		push_error("Button cannot be focused in the viewport: " + button.text + " focus=" + str(button.has_focus()) + " rect=" + str(button.get_global_rect()) + " viewport=" + str(root.size))
		return false
	var transport: WorldRuntime
	ancestor = button.get_parent()
	while ancestor != null:
		if ancestor is LocalProductionPanel or ancestor is MachineryPanel: transport = ancestor._world
		ancestor = ancestor.get_parent()
	var outcome: Dictionary = {}
	var completed: Callable = func(command: SimulationCommand, result: ServiceResult) -> void:
		if command is ProductionDevelopmentCommand:
			outcome["success"] = result.is_success
			outcome["message"] = result.message
			outcome["expected_revision"] = command.payload.get("expected_revision", -1)
			outcome["request_id"] = String(command.command_id)
	if transport != null: transport.command_completed.connect(completed)
	print("UI activate: " + button.text.replace("\n", " "))
	var fired: Array[bool] = [false]
	var callback: Callable = func() -> void: fired[0] = true
	button.pressed.connect(callback, CONNECT_ONE_SHOT)
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await process_frame
	await process_frame
	if button.pressed.is_connected(callback): button.pressed.disconnect(callback)
	button.release_focus()
	await create_timer(0.25).timeout # Allow the next remote observation/layout refresh.
	if transport != null:
		var acknowledged: bool = await _wait_until(func() -> bool: return outcome.has("success"))
		transport.command_completed.disconnect(completed)
		if not acknowledged or not fired[0]: return false
		_last_ui_outcome = outcome.duplicate(true)
		if not outcome["success"]:
			if allow_stale_retry and outcome["message"].contains("revision is stale"): return true
			push_error("Visible UI command rejected at " + button.text + ": " + outcome["message"])
			return false
	if not fired[0]: push_error("GUI input failed to activate " + button.text)
	return fired[0]


func _collect_reprinted_plate(client: FirstPlayableBootstrap) -> bool:
	# Completion events precede periodic observations. A guide flag is not stock.
	if not await _wait_until(func() -> bool: return client._latest["production"]["job"].is_empty() and client._latest["production"]["store"]["plate"] >= 1000000, 6.0): return false
	for attempt in range(3):
		if not await _press_named(client._production_panel, "Collect printed plate into inventory", true): return false
		if _last_ui_outcome.get("success", false):
			print("Collection accepted request %s at submitted revision %d." % [_last_ui_outcome["request_id"], _last_ui_outcome["expected_revision"]])
			return true
		if _last_ui_outcome.get("message", "") != "The production revision is stale or exhausted.":
			push_error("Collection requires a successful matching host receipt.")
			return false
		var revision: int = _last_ui_outcome["expected_revision"]
		if not client._production_panel._feedback.text.begins_with("Rejected") or not client._production_panel._feedback.text.contains(_last_ui_outcome["message"]):
			push_error("Collection stale rejection must remain visible before retry.")
			return false
		print("Collection stale request %s revision %d, attempt %d: visible rejection; awaiting newer observation before same-button retry." % [_last_ui_outcome["request_id"], revision, attempt + 1])
		if not await _wait_until(func() -> bool: return client._latest["production"]["state_revision"] > revision and client._production_panel._record["state_revision"] > revision, 3.0): return false
	push_error("Collection exhausted three explicit stale-revision attempts.")
	return false

func _press_named(parent: Node, title: String, allow_stale_retry: bool = false) -> bool:
	var matches: Array[Button] = []
	for candidate in parent.find_children("*", "Button", true, false):
		if candidate.text == title: matches.append(candidate)
	if matches.size() != 1:
		push_error("Expected one button in intended panel for '%s'; found %d." % [title, matches.size()])
		return false
	return await _press(matches[0], allow_stale_retry)


func _reveal_task_section(control: Control) -> void:
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is LocalProductionPanel:
			for index in range(ancestor._sections.size()):
				if ancestor._sections[index].is_ancestor_of(control):
					ancestor._navigation.select(index)
					ancestor._navigation.item_selected.emit(index)
					return
		ancestor = ancestor.get_parent()

func _select(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	push_error("Missing fixture selection: " + id)


func _wait_until(predicate: Callable, seconds: float = 3.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
		await process_frame
	push_error("Bounded client UI observation wait expired.")
	return false


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = Vector2(1500, 600) # Right-hand habitat viewport, outside controls.
	Input.parse_input_event(event)
