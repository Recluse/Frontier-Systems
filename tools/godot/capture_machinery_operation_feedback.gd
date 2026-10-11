extends "res://tests/godot/machinery_runtime_test.gd"


## Real finite fixture, authenticated loopback client and unedited viewport PNGs.
func finish() -> void:
	create_timer(35.0).timeout.connect(func() -> void: push_error("Operation capture deadline"); quit(1))
	if failures:
		world.free()
		quit(1)
		return
	var extractor: String = ""
	for module in production.capture_snapshot().value["machinery"]["mounts"]:
		if production.capture_snapshot().value["machinery"]["parts"][module]["kind"] == "extractor": extractor = production.capture_snapshot().value["machinery"]["mounts"][module]
	move([-6000, 0, -1000])
	command("machine_run", {"machine_id": extractor, "recipe": "extract.ice"})
	var host := FirstPlayableHost.new()
	root.add_child(host)
	var key: String = "operation-capture-player-one-000000000"
	check(host.configure(world, [key, "operation-capture-player-two-000000000"], 27853).is_success, "capture listener opens on separate port")
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:27853")
	OS.set_environment("FRONTIER_INVITE_KEY", key)
	var client := FirstPlayableBootstrap.new()
	root.add_child(client)
	await create_timer(0.7).timeout
	check(not client._latest.is_empty(), "authenticated client receives scoped telemetry")
	if client._latest.is_empty():
		client.free()
		host.free()
		world.free()
		quit(1)
		return
	client._habitat.character.read_local_keyboard = false
	client._tabs.current_tab = 3
	client._machinery_panel.select_machine(extractor)
	client._habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	client._habitat.camera.position = Vector3(-14.0, 4.0, 4.0)
	client._habitat.camera.look_at(Vector3(-11.2, 0.7, 0.0))
	DirAccess.make_dir_recursive_absolute("res://reports/machinery-operation-feedback")
	step(8)
	await create_timer(0.3).timeout
	check(client._machinery_panel._status.text.contains("Running · observed progress"), "real advancing batch earns running label")
	await capture("running")
	command("machine_enable", {"machine_id": extractor, "enabled": false})
	step(8)
	await create_timer(0.3).timeout
	check(client._machinery_panel._status.text.contains("Isolated / disabled") and client._machinery_panel._status.text.contains("Not advancing"), "host isolation explains stalled job")
	await capture("isolated")
	command("machine_enable", {"machine_id": extractor, "enabled": true})
	step(180)
	await create_timer(0.3).timeout
	check(not production.capture_snapshot().value["machinery"]["jobs"].has(extractor), "actual host batch completes")
	check(client._machinery_panel._status.text.contains("No active batch observed"), "completed host job no longer shown running")
	await capture("ended")
	host.free()
	await create_timer(0.3).timeout
	check(client._machinery_panel._record.is_empty() and client._machinery_preview._labels.is_empty(), "actual disconnect clears panel and preview telemetry")
	client.free()
	world.free()
	print("Machinery operation graphical capture: %d failures" % failures)
	quit(1 if failures else 0)


func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://reports/machinery-operation-feedback/%s.png" % label) == OK, "unedited viewport saved: " + label)
