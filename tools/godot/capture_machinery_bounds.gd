extends "res://tests/godot/machinery_runtime_test.gd"


## Retains the real finite-material workshop and renders authenticated client UI.
func finish() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("Graphical bounds capture deadline"); quit(1))
	if failures > 0:
		world.free()
		quit(1)
		return
	move([0, 0, 0])
	var printer: String = ""
	for id in production.capture_snapshot().value["machinery"]["mounts"]:
		if production.capture_snapshot().value["machinery"]["parts"][id]["kind"] == "printhead":
			printer = production.capture_snapshot().value["machinery"]["mounts"][id]
	command("machine_pack", {"machine_id": printer})
	var host := FirstPlayableHost.new()
	root.add_child(host)
	var key: String = "placement-capture-player-one-000000000"
	check(host.configure(world, [key, "placement-capture-player-two-000000000"], 27851).is_success, "local capture host opens")
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:27851")
	OS.set_environment("FRONTIER_INVITE_KEY", key)
	runner.set_physics_process(true)
	var client := FirstPlayableBootstrap.new()
	root.add_child(client)
	await create_timer(1.0).timeout
	check(not client._latest.is_empty(), "client receives actual scoped workshop")
	if client._latest.is_empty():
		client.free()
		host.free()
		world.free()
		quit(1)
		return
	client._habitat.character.read_local_keyboard = false
	client._tabs.current_tab = 3
	var panel: MachineryPanel = client._machinery_panel
	panel.select_machine(printer)
	panel._axes[0].value = 0.0
	panel._axes[2].value = -1.0
	panel._show_placement.button_pressed = true
	client._habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	client._habitat.camera.position = Vector3(-8.8, 4.0, 4.5)
	client._habitat.camera.look_at(Vector3(-6.9, 0.6, 1.6))
	await process_frame
	var ghost: MeshInstance3D = client._machinery_preview._feedback_root.get_child(0)
	check((ghost.mesh as BoxMesh).size == Vector3(2.5, 1.5, 1.3), "actual expander observation displays conservative envelope")
	check(panel._placement_status.text.contains("Advisory only"), "actual client separates advice from authorization")
	var scroll: ScrollContainer = panel.get_parent()
	scroll.scroll_vertical = maxi(0, roundi(panel._mode.position.y) - 180)
	DirAccess.make_dir_recursive_absolute("res://reports/machinery-bounds")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://reports/machinery-bounds/ghost.png") == OK, "authenticated graphical ghost capture saved")
	# Submit a genuine invalid floor target; the host keeps the ghost for correction.
	panel._axes[1].value = 0.1
	panel._send("machine_deploy")
	await create_timer(0.5).timeout
	check(panel._pending.is_empty() and panel._feedback.text != "Completed" and panel._show_placement.button_pressed, "host rejection preserves editable ghost")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://reports/machinery-bounds/rejected.png") == OK, "actual rejected target capture saved")
	panel._axes[1].value = 0.0
	# Hold transport polling for one rendered frame to capture genuine queued state.
	host.set_process(false)
	panel._send("machine_deploy")
	await process_frame
	await RenderingServer.frame_post_draw
	check(not panel._pending.is_empty(), "client is waiting for actual host result")
	check(root.get_texture().get_image().save_png("res://reports/machinery-bounds/pending.png") == OK, "pending command capture saved")
	host.set_process(true)
	await create_timer(0.5).timeout
	check(client._machinery_preview._feedback_root.get_child_count() == 13, "actual selected machine shows all twelve envelope edges")
	check(panel._feedback.text == "Completed", "authenticated host accepts UI placement")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://reports/machinery-bounds/selected.png") == OK, "selected settled frame capture saved")
	host.free()
	await create_timer(0.2).timeout
	check(panel._record.is_empty() and client._machinery_preview._feedback_root.get_child_count() == 0, "disconnect clears stale client ghost and selection")
	client.free()
	world.free()
	print("Machinery bounds graphical capture: %d failures" % failures)
	quit(1 if failures else 0)
