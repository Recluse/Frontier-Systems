extends "res://tests/godot/world_pointer_picking_test.gd"

## Dedicated selected guidance checks through the actual socket-free client.
## Inherits the accepted fixture without editing its routes or canonical setup.
func unchanged(label: String) -> void:
	super.unchanged(label)
	feedback._physics_process(0)
	if not WorldSelectionInput.gameplay_allowed(viewport):
		check(not feedback.visible, label + " hides guidance during UI ownership")
		return
	var info: Dictionary = feedback.describe(feedback.selected)
	var guidance: String = feedback._lines[4].text
	if info.is_empty():
		check(guidance.is_empty() and not feedback._lines[4].visible, label + " clears contextual guidance")
		return
	check(guidance.contains(PlayerInputSettings.instance().binding_label("ui_cursor")), label + " names live cursor binding")
	match info["action"]:
		"Request extraction":
			check(guidance.contains("Gather / carry") and guidance.contains("without extracting"), label + " explains source inspection")
		"Request collection":
			check(guidance.contains("Inventory") and guidance.contains("Collect selected") and guidance.contains("does not collect"), label + " explains item inspection")
		"Select recipes":
			check(guidance.contains("Run selected recipe") and guidance.contains("only opens recipes"), label + " explains workstation inspection")
		"Select to inspect":
			check(guidance.contains("Place a new wall") and guidance.contains("does not build"), label + " separates wall inspection from draft")
	check(feedback._lines[3].text.contains("permission") and feedback._lines[3].text.contains("Success not guaranteed"), label + " retains authority uncertainty")
	# In-memory bindings only; do not write player preferences.
	var cursor := InputEventKey.new()
	cursor.physical_keycode = KEY_H
	PlayerInputSettings._set_binding("ui_cursor", cursor)
	feedback._update_card({}, info, Vector2(viewport.size))
	check(feedback._lines[4].text.contains(PlayerInputSettings.instance().binding_label("ui_cursor")) and not feedback._lines[4].text.contains("Alt"), "selected guidance refreshes cursor rebind")
	var select := InputEventJoypadButton.new()
	select.button_index = JOY_BUTTON_A
	PlayerInputSettings._set_binding("world_select", select)
	check(not feedback.selection_hint(info).contains("Single selection"), "controller selection does not claim inspection-only item/source activation")
	PlayerInputSettings._set_binding("world_select", cursor)
	check(not feedback.selection_hint(info).contains("Single selection"), "keyboard selection does not claim inspection-only item/source activation")
	InputMap.action_erase_events("ui_cursor")
	check(feedback.selection_hint(info).contains("UI cursor unbound"), "unbound cursor has actionable guidance")
	InputMap.action_erase_events("world_select")
	check(feedback.hint(info).contains("unbound"), "unbound selection retains existing Controls route")
	PlayerInputSettings.instance()._reset_map()
	feedback._physics_process(0)
	check(feedback.mouse_filter == Control.MOUSE_FILTER_IGNORE and feedback._lines[4].mouse_filter == Control.MOUSE_FILTER_IGNORE, "guidance never owns pointer input")
	super.unchanged(label + " binding advice")


func world_click() -> void:
	await super.world_click()
	if feedback.describe(feedback.selected).is_empty() or not WorldSelectionInput.gameplay_allowed(viewport):
		return
	var original: Vector2i = root.size
	var info: Dictionary = feedback.describe(feedback.selected)
	var target: CollisionObject3D = feedback.selected
	var character: LocalHabitatCharacter = client._habitat.character
	client._habitat.activate_character(LocalHabitatCharacter.CameraMode.FIRST_PERSON)
	character.set_physics_process(false)
	character.position = target.global_position + Vector3(0, 2, 1.2) - Vector3(0, 0.7, 0)
	character._camera.look_at(target.global_position)
	await settle()
	check(viewport.get_camera_3d() == character._camera, "guidance uses actual first-person camera")
	var capture: bool = OS.get_cmdline_user_args().has("--capture-selected")
	var extents: Array[Vector2i] = []
	if capture:
		extents.append(Vector2i(1440, 900))
		extents.append(Vector2i(1000, 700))
	else:
		extents.append(original)
	var directory: String = "res://var/ci/selected-target-controls/captures"
	if capture: DirAccess.make_dir_recursive_absolute(directory)
	for extent in extents:
		root.size = extent
		await settle()
		feedback._physics_process(0)
		await process_frame
		await process_frame
		feedback._physics_process(0)
		check(feedback.visible and feedback._lines[4].visible, "actual-client contextual row visible at %s" % extent)
		for line in feedback._lines:
			if line.visible:
				check(line.get_visible_line_count() == line.get_line_count(), "actual-client wrapped guidance complete")
		check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(Rect2(feedback._card.position, feedback._card.size)), "actual-client card stays bounded")
		if capture:
			await RenderingServer.frame_post_draw
			var name: String = String(info["action"]).to_snake_case()
			check(root.get_texture().get_image().save_png(directory.path_join("%s-%dx%d.png" % [name, extent.x, extent.y])) == OK, "ignored internal first-person capture")
	root.size = original
	await settle()

func run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: check(false, "Pointer fixture deadline"); quit(1))
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
	var item_key: String = JSON.stringify(["world.tray-1", "backpack-1"])
	var item: Area3D
	for child in client._habitat.world_inventory._rendered.get_children():
		if child is Area3D and feedback.describe(child).get("name", "").contains("backpack-1"): item = child
	var source: Area3D = client._habitat.production._source_areas["deposit.iron"]
	var workstation: Area3D
	for child in client._habitat.production.get_children():
		if child is Area3D and child not in client._habitat.production._source_areas.values(): workstation = child
	var wall: StaticBody3D = client._habitat.production._spatial_walls[observation["production"]["walls"].keys()[0]]
	for target in [item, source, workstation, wall]:
		root.gui_release_focus()
		client._habitat.activate_character(LocalHabitatCharacter.CameraMode.FIRST_PERSON)
		var character: LocalHabitatCharacter = client._habitat.character
		character.set_physics_process(false)
		character.position = target.global_position + (Vector3(0, 1.4, 3) if target == item else Vector3(0, 2, 1.2)) - Vector3(0, 0.7, 0)
		character._camera.look_at(target.global_position)
		await settle()
		await world_click()
		check(feedback.selected == target, "ordinary first-person click selects %s, observed %s" % [feedback.describe(target), feedback.describe(feedback.selected)])
		unchanged("first-person " + String(feedback.describe(target).get("action", "")))
		# Retire advice through the real empty-space input ray.
		character._camera.rotation = Vector3(PI / 3.0, 0, 0)
		await settle()
		await super.world_click()
		check(feedback.selected == null, "empty sky clears selected target")
		unchanged("empty sky")
	check(picked_items == [item_key] and picked_sources == ["deposit.iron"] and workstation_picks == 1 and picked_walls.size() == 1, "only intended selections: items %s sources %s stations %s walls %s" % [picked_items, picked_sources, workstation_picks, picked_walls])
	print("Selected target controls: %d failures; injected first-person client, no human acceptance" % failures)
	client.free()
	world.free()
	PlayerInputSettings.instance()._reset_map()
	quit(1 if failures else 0)