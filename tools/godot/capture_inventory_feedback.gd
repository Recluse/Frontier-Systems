extends SceneTree

## Real loopback host/client; graphical-only. Temporary in-memory world, no services.
const DIRECTORY: String = "res://reports/inventory-feedback"
var failures: int = 0

func _initialize() -> void:
	OS.set_environment("FRONTIER_EVENT_URL", "")
	OS.set_environment("FRONTIER_EVENT_TOKEN", "")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func capture(panel: PlayerInventoryPanel, filename: String) -> void:
	await process_frame
	(panel.get_parent() as ScrollContainer).scroll_vertical = roundi(panel._world_root.position.y) - 45
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY.path_join(filename)) == OK, "capture " + filename)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a graphical runner for inventory captures.")
		quit(1)
		return
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:27861")
	var key: String = "inventory-feedback-one-00000000000000"
	OS.set_environment("FRONTIER_INVITE_KEY", key)
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "world starts")
	var host := FirstPlayableHost.new()
	root.add_child(host)
	if not host.configure(world, [key, "inventory-feedback-two-00000000000000"], 27861).is_success:
		push_error("Reserved port 27861 unavailable; no other process stopped.")
		host.free()
		world.free()
		quit(1)
		return
	var client := FirstPlayableBootstrap.new()
	root.add_child(client)
	await create_timer(1.2).timeout
	check(not client._latest.is_empty(), "invite-authenticated real projection received")
	if client._latest.is_empty():
		client.free()
		host.free()
		world.free()
		quit(1)
		return
	client.set_process(false)
	client._habitat.character.read_local_keyboard = false
	client._habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	client._habitat.camera.position = Vector3(-8.8, 3.5, 4.6)
	client._habitat.camera.look_at(Vector3(-6.0, 0.9, 2.0))
	client._tabs.current_tab = 1
	var panel: PlayerInventoryPanel = client._inventory_panel
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	check(panel._world_items.item_count == 1, "initial world canister is projected")
	panel._world_items.select(0)
	panel._world_items.item_selected.emit(0)
	await capture(panel, "selected.png")
	# Pause only this tool's host to render pending-before-ack, not an invented state.
	host.set_process(false)
	panel._world_action("pickup")
	var pending: String = panel._pending
	check(not pending.is_empty() and panel._pending_world["item_id"] == "resource-canister-2", "real pickup pending target")
	panel._world_action("pickup")
	check(panel._pending == pending, "duplicate suppressed")
	await capture(panel, "pending-pickup.png")
	host.set_process(true)
	await create_timer(0.5).timeout
	check(panel._pending.is_empty() and panel._world_items.item_count == 0, "host pickup accepted and world item removed")
	for index in range(panel._items.item_count):
		if panel._items.get_item_metadata(index)["item_id"] == "resource-canister-2": panel._items.select(index)
	host.set_process(false)
	panel._world_action("drop")
	check(panel._pending_world.get("item_id") == "resource-canister-2", "real drop pending target")
	await capture(panel, "pending-drop.png")
	host.set_process(true)
	await create_timer(0.5).timeout
	check(panel._pending.is_empty() and panel._world_items.item_count == 1, "host drop accepted")
	# Reject from an actual host-owned stale revision; no authority change.
	panel._world_items.select(0)
	panel._record["inventory_revision"] -= 1
	panel._world_action("pickup")
	await create_timer(0.4).timeout
	check(panel._pending.is_empty() and panel._result.text.begins_with("Host rejected"), "host stale-revision rejection shown")
	await capture(panel, "rejected.png")
	# Native viewport ray picking, rather than a direct signal handler call.
	var preview: ProceduralWorldInventoryPreview = client._habitat.world_inventory
	await process_frame
	var entry: Dictionary = preview._visible_items.values()[0]
	var viewport: Viewport = preview.get_viewport()
	var point: Vector2 = client._habitat.camera.unproject_position(entry["mesh"].global_position)
	var from: Vector3 = client._habitat.camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(from, from + client._habitat.camera.project_ray_normal(point) * 50.0)
	query.collide_with_areas = true
	query.collision_mask = 5
	var hit: Dictionary = client._habitat.camera.get_world_3d().direct_space_state.intersect_ray(query)
	check(hit.get("collider") is Area3D, "camera ray hits an inventory pick area")
	var container: SubViewportContainer = viewport.get_parent()
	point = container.global_position + point * container.size / Vector2(viewport.size)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await physics_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	click.global_position = point
	root.push_input(click, true)
	await create_timer(0.2).timeout
	check(not preview.presentation_snapshot()["selected_key"].is_empty(), "native viewport ray selects world proxy")
	await capture(panel, "world-selection.png")
	click.pressed = false
	root.push_input(click, true)
	host.set_process(false)
	panel._world_action("pickup")
	client._remote._socket.close()
	host.set_process(true)
	await create_timer(0.8).timeout
	check(panel._record.is_empty() and panel._pending.is_empty() and panel._world_details.text.is_empty(), "actual socket disconnect clears panel")
	await capture(panel, "disconnected.png")
	client.free()
	host.free()
	world.free()
	print("Graphical inventory feedback route: %d failures" % failures)
	quit(1 if failures else 0)
