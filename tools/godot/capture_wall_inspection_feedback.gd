extends "res://tests/godot/spatial_wall_runtime_test.gd"

const CAPTURE_DIRECTORY: String = "res://var/ci/wall-inspection-feedback/captures"


func _initialize() -> void:
	# This reproduction tool must remain local even in an operator-configured shell.
	OS.set_environment("FRONTIER_EVENT_URL", "")
	OS.set_environment("FRONTIER_EVENT_TOKEN", "")
	super._initialize()


func capture_view(client: FirstPlayableBootstrap, filename: String) -> void:
	var panel: MachineryPanel = client._machinery_panel
	await process_frame
	(panel.get_parent() as ScrollContainer).scroll_vertical = maxi(0, roundi(panel._placement_kind.position.y) - 70)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(CAPTURE_DIRECTORY.path_join(filename)) == OK, filename + " graphical capture saved")


func select_plate(panel: MachineryPanel, id: String) -> void:
	for index in range(panel._part.item_count):
		if panel._part.get_item_metadata(index) == id: panel._part.select(index)
	panel._refresh_placement()


## Finite material fixture, real invite-authenticated transport and native rendering.
func finish() -> void:
	if failures > 0:
		world.free()
		quit(1)
		return
	move([0, 0, 0])
	command("process", {"recipe_id": "craft.plate"})
	step(120)
	command("materialize_plate", {})
	var host := FirstPlayableHost.new()
	root.add_child(host)
	var key: String = "wall-inspection-player-one-0000000000000"
	if not host.configure(world, [key, "wall-inspection-player-two-0000000000000"], 19231).is_success:
		push_error("Port 19231 is unavailable; no other listener will be stopped.")
		world.free()
		host.free()
		quit(1)
		return
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:19231")
	OS.set_environment("FRONTIER_INVITE_KEY", key)
	runner.set_physics_process(true)
	var client := FirstPlayableBootstrap.new()
	root.add_child(client)
	await create_timer(1.0).timeout
	check(not client._latest.is_empty(), "real client authenticates")
	if client._latest.is_empty():
		client.free()
		host.free()
		world.free()
		quit(1)
		return
	client._habitat.character.read_local_keyboard = false
	client._habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	client._habitat.camera.position = Vector3(-8.8, 3.5, 4.6)
	client._habitat.camera.look_at(Vector3(-6.0, 1.0, 1.2))
	client._tabs.current_tab = 3
	var panel: MachineryPanel = client._machinery_panel
	select_plate(panel, client._latest["production"]["components"][0])
	panel._placement_kind.select(1)
	panel._axes[0].value = 0
	panel._axes[1].value = 0
	panel._axes[2].value = -1
	panel._show_placement.button_pressed = true
	panel._refresh_placement()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))

	panel._wall_turn.select(1)
	panel._refresh_placement()

	panel._axes[1].value = 0.1
	panel._send("wall_build")
	await create_timer(0.5).timeout
	check(panel._pending.is_empty() and panel._feedback.text != "Completed" and client._latest["production"]["walls"].is_empty(), "authenticated host rejects floating panel without consuming plate")
	panel._axes[1].value = 0
	# Pause transport for a rendered frame to expose the actual pending UI target.
	host.set_process(false)
	panel._send("wall_build")
	var pending: String = panel._pending
	panel._send("wall_build")
	check(not pending.is_empty() and panel._pending == pending, "authenticated duplicate UI submission suppressed")

	host.set_process(true)
	await create_timer(0.6).timeout
	check(panel._feedback.text == "Completed" and client._latest["production"]["walls"].size() == 1, "authenticated build commits one wall")
	if client._latest["production"]["walls"].is_empty():
		client.free()
		host.free()
		world.free()
		quit(1)
		return
	var id: String = client._latest["production"]["walls"].keys()[0]
	var physical: ProceduralProductionPreview = client._habitat.production
	check(physical._spatial_walls.has(id), "observed physical panel has native static collider")
	var query := PhysicsRayQueryParameters3D.create(Vector3(-7, 1, 1), Vector3(-5, 1, 1))
	var hit: Dictionary = physical.get_world_3d().direct_space_state.intersect_ray(query)
	check(hit.get("collider") == physical._spatial_walls.get(id), "native ray picks settled Z wall through decoration")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	physical._spatial_walls[id].input_event.emit(client._habitat.camera, click, Vector3(-6, 1, 1), Vector3.LEFT, 0)
	check(panel._selected(panel._wall) == id and panel._placement_kind.selected == 1, "native wall input event selects stable wall in construction panel")
	await capture_view(client, "selected.png")
	check(panel._placement_status.text.contains(id) and panel._placement_status.text.contains("Selected X") and panel._placement_status.text.contains("1 × 2 × 0.1 m"), "authenticated selected wall details are readable")
	# Out-of-reach rejection through the authenticated client and actual host.
	runner.set_physics_process(false)
	move([3000, 0, 0])
	host._process(0.1)
	await create_timer(0.3).timeout
	panel._send("wall_remove")
	runner.set_physics_process(true)
	await create_timer(0.6).timeout
	check(panel._feedback.text.contains("Host rejected removal of wall " + id) and physical._spatial_walls.has(id), "authenticated reach rejection names retained wall")
	await capture_view(client, "rejected.png")
	runner.set_physics_process(false)
	move([0, 0, 0])
	host._process(0.1)
	await create_timer(0.3).timeout
	runner.set_physics_process(true)
	host.set_process(false)
	panel._send("wall_remove")
	var submitted: Dictionary = panel._pending_wall.duplicate(true)
	panel._axes[0].value = 42
	panel._wall_turn.select(0)
	panel._refresh_placement()
	check(panel._pending_wall == submitted and panel._placement_status.text.contains(id) and panel._placement_status.text.contains("No plate return confirmed"), "authenticated pending target survives changed controls")
	await capture_view(client, "pending-removal.png")
	host.set_process(true)
	await create_timer(0.6).timeout
	check(panel._feedback.text.contains("Host accepted removal of wall " + id) and client._latest["production"]["walls"].is_empty() and physical._spatial_walls.is_empty(), "authenticated remove clears collider")
	check(client._latest["production"]["components"].size() == 1, "authenticated removal recovers exactly one owned plate")
	await capture_view(client, "accepted.png")
	select_plate(panel, client._latest["production"]["components"][0])
	panel._axes[0].value = 0
	panel._wall_turn.select(1)
	panel._show_placement.button_pressed = true
	panel._send("wall_build")
	await create_timer(0.6).timeout
	check(panel._feedback.text == "Completed" and physical._spatial_walls.size() == 1, "recovered plate rebuilds without grants")
	# A pending second intent gets a real disconnect failure and clears decoration.
	host.set_process(false)
	panel._send("wall_remove")
	check(not panel._pending.is_empty(), "disconnect begins with a genuine pending wall command")
	var disconnect_id: String = panel._pending_wall["wall_id"]
	host.free()
	await create_timer(0.4).timeout
	check(panel._feedback.text.contains(disconnect_id) and panel._feedback.text.contains("outcome unconfirmed"), "actual disconnect retains exact unresolved target outcome")
	await capture_view(client, "disconnected.png")
	check(panel._pending.is_empty() and panel._pending_wall.is_empty() and panel._record.is_empty(), "disconnect fails pending request and clears scoped wall selection")
	check(client._machinery_preview._feedback_root.get_child_count() == 0 and physical._spatial_walls.is_empty() and client._latest.is_empty(), "disconnect clears ghost, selected footprint and stale settled collider")
	client.free()
	world.free()
	print("Wall inspection graphical capture: %d failures" % failures)
	quit(1 if failures else 0)
