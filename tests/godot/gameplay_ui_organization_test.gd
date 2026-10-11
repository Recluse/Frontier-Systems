extends "res://tests/godot/integrated_panel_layout_test.gd"

## Real client shell, domain owners and recording transport; no sockets.
func inspect_station() -> void:
	client._habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	var station := Vector3(-6.0, 0.8, 3.0)
	client._habitat.camera.position = station + Vector3(0.0, 8.0, 5.0)
	client._habitat.camera.look_at(station)


func layout_contract() -> void:
	await settle()
	client._refresh_command_feedback()
	var viewport: SubViewport = client._habitat.get_viewport()
	var surface: Control = viewport.get_parent()
	check(surface.size.x >= root.size.x * 0.55, "scene retains majority of window width")
	check(surface.size.y >= root.size.y * 0.55, "scene retains majority of window height")
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(surface.get_global_rect()), "scene remains within window")
	check(client._hands_hud.is_visible_in_tree(), "hands remain visible when drawer closes")
	check(client._connection_status.is_visible_in_tree(), "connection status stays visible")
	check(client._target_feedback.compact and not client._world_labels_enabled, "expanded target instructions and floating captions start collapsed")
	var camera: Camera3D = viewport.get_camera_3d()
	var station := Vector3(-6.0, 0.8, 3.0)
	check(not camera.is_position_behind(station) and Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(camera.unproject_position(station)), "object of interest remains inside actual scene camera")
	if client._tabs.visible:
		var current: Control = client._tabs.get_current_tab_control()
		check(current.is_visible_in_tree(), "one chosen interaction panel visible")
		for index in range(client._tabs.get_tab_count()):
			check(client._tabs.get_tab_control(index).is_visible_in_tree() == (index == client._tabs.current_tab), "other panels remain hidden")
		bounded(current, client._tabs.size.x)


func run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: check(false, "organization fixture deadline"); quit(1))
	PlayerInputSettings.instance()._reset_map()
	capture = OS.get_cmdline_user_args().has("--capture-integrated")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "real domain owner starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	move([0, 0, 0])
	client = FixtureClient.new()
	root.add_child(client)
	client.set_process(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	observe_shell()
	panel = client._inventory_panel
	var before: String = world.capture_world_snapshot_json().value
	var workstation: CollisionObject3D
	for node in client._habitat.production.get_children():
		if node is Area3D and node.position == Vector3(-6.0, 0.8, 3.0): workstation = node
	var feedback: HabitatTargetFeedback = client._habitat.find_children("*", "HabitatTargetFeedback", true, false)[0]
	for extent: Vector2i in [Vector2i(1920, 1080), Vector2i(1100, 700)]:
		root.size = extent
		client._set_drawer_open(false)
		inspect_station()
		await layout_contract()
		check(not client._tabs.visible, "drawer starts closed")
		await snap("organization-%d-closed" % extent.x)
		# The same native workstation route used by world picking opens its panel.
		root.gui_release_focus()
		feedback.selected = workstation
		client._habitat.production.workstation_selected.emit()
		await layout_contract()
		check(client._tabs.visible and client._tabs.current_tab == 0 and feedback.selected == workstation, "selection opens contextual recipes without losing selected object")
		check(visible(client._production_panel._recipe, client._scroll), "opening drawer reveals recipe controls after layout without taking focus")
		await snap("organization-%d-workstation" % extent.x)
		root.gui_release_focus()
		await key(KEY_I)
		await layout_contract()
		check(client._tabs.visible and client._tabs.current_tab == 1, "inventory hotkey opens equipment on demand")
		panel._items.grab_focus()
		client._set_drawer_open(false)
		check(client._drawer_toggle.has_focus(), "closing focused drawer restores visible keyboard control")
		root.gui_release_focus()
		await key(KEY_I)
		choose(panel._source, "storage.pouch-1")
		panel._fill_items()
		select_tool("crowbar-1")
		choose(panel._slot, "hand.right")
		choose(panel._destination, frame()["inventory"]["body_container_id"])
		panel._update_buttons()
		panel._self_action("move")
		if remote.sent.is_empty():
			check(false, "transfer queued: " + panel._result.text)
			quit(1)
			return
		var request: SimulationCommand = remote.sent[-1]
		var pinned: Dictionary = panel._pending_inventory.duplicate(true)
		client._set_drawer_open(false)
		await layout_contract()
		check(panel._pending_inventory == pinned and client._command_feedback.text.contains("crowbar-1") and client._feedback_summary.text.contains("pending"), "closed drawer preserves and displays exact pending transfer identity")
		await snap("organization-%d-pending" % extent.x)
		var long_error: String = "Host rejected transfer of crowbar-1 from storage.pouch-1; record " + String(world.world_id).repeat(4) + ": " + "Observed destination or revision changed; refresh the exact target before retrying. ".repeat(5)
		remote.command_completed.emit(request, ServiceResult.failure(&"fixture_rejection", long_error))
		client._refresh_command_feedback()
		await layout_contract()
		check(client._command_feedback.text.contains(long_error) and panel._pending_inventory.is_empty(), "long rejection survives closed drawer with full receipt text")
		client._command_feedback.grab_focus()
		await settle()
		client._essential_scroll.grab_focus()
		client._essential_scroll.scroll_vertical = 0
		await settle()
		var old_scroll: int = client._essential_scroll.scroll_vertical
		await key(KEY_DOWN)
		check(client._essential_scroll.scroll_vertical > old_scroll, "bounded persistent receipt scrolls with keyboard")
		await snap("organization-%d-rejected" % extent.x)
		client._open_panel(3)
		await layout_contract()
		await snap("organization-%d-construction" % extent.x)
		check(world.capture_world_snapshot_json().value == before, "navigation and rejected intents preserve canonical snapshot")
		client._open_panel(1)
		panel._self_action("move")
		request = remote.sent[-1]
		client._set_drawer_open(false)
		remote.connection_closed.emit("Fixture disconnect; outcome unknown")
		await settle()
		client._refresh_command_feedback()
		check(client._command_feedback.text.contains("unknown") and client._command_feedback.text.contains("crowbar-1") and client._feedback_summary.text.contains("uncertain"), "disconnect recovery identity persists outside inventory drawer")
		var sends: int = remote.sent.size()
		client._connect_client()
		observe_shell()
		inspect_station()
		await layout_contract()
		check(remote.sent.size() == sends and panel._result.text.contains("crowbar-1"), "reconnect does not replay or erase recovery targets")
		remote.command_completed.emit(request, ServiceResult.success())
		check(panel._result.text.contains("unknown"), "late receipt cannot confirm disconnected transfer")
		await snap("organization-%d-reconnect" % extent.x)
	# Preserve a real queued production command through the transport's failure path.
	var sent_before: int = remote.sent.size()
	client._production_panel._send("process", {"recipe_id": "refine.iron"})
	check(remote.sent.size() == sent_before + 1, "actual production panel queues processing intent")
	if remote.sent.size() == sent_before:
		quit(1)
		return
	var process_request: ProductionDevelopmentCommand = remote.sent[-1]
	remote._requests[String(process_request.command_id)] = process_request
	client._set_drawer_open(false)
	check(client._command_feedback.text.contains(String(process_request.command_id)) and client._command_feedback.text.contains("refine.iron"), "closed drawer displays production request and exact recipe/revision")
	remote.command_completed.emit(process_request, ServiceResult.failure(&"remote_disconnected", "Host connection closed"))
	remote.connection_closed.emit("Host connection closed")
	await settle()
	client._refresh_command_feedback()
	check(client._command_feedback.text.contains(String(process_request.command_id)) and client._command_feedback.text.contains("refine.iron") and client._feedback_summary.text.contains("uncertain"), "production panel recreation cannot erase disconnected submitted identity")
	client._connect_client()
	observe_shell()
	inspect_station()
	await layout_contract()
	check(remote.sent.size() == sent_before + 1 and client._command_feedback.text.contains(String(process_request.command_id)), "fresh observation neither replays nor confirms disconnected production intent")
	check(world.capture_world_snapshot_json().value == before, "all presentation and abandoned intents preserve canonical state")
	await snap("organization-production-recovery")
	client.free()
	world.free()
	if failures == 0: print("PASS gameplay UI organization: actual desktop/narrow shell, contextual selection, on-demand inventory, visible pending/rejection/recovery and keyboard scroll; no sockets, human usability unverified")
	quit(0 if failures == 0 else 1)
