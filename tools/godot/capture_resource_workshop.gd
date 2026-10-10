extends "res://tests/godot/machinery_runtime_test.gd"

## Run the complete finite gameplay integration first, then retain its actual world
## and capture the connected graphical client. No raw material or scene-state grants.
func finish() -> void:
	if failures > 0:
		world.free()
		quit(1)
		return
	var workshop: Dictionary = production.capture_snapshot().value["machinery"]
	var printer: String = ""
	var processing_frame: String = ""
	var refinery_head: String = ""
	var refinery_frame: String = ""
	var socket: String = ""
	for id in workshop["mounts"]:
		match workshop["parts"][id]["kind"]:
			"printhead": printer = workshop["mounts"][id]
			"extractor": processing_frame = workshop["mounts"][id]
			"refinery":
				refinery_head = id
				refinery_frame = workshop["mounts"][id]
	for id in workshop["mounts"]:
		if workshop["mounts"][id] == printer and workshop["parts"][id]["kind"] == "socket": socket = id
	move([0, 0, 0])
	var printer_cable: String = craft("cable")
	command("load_cargo", {"carrier_id": "resource-canister-2", "material": "iron", "amount_milligrams": 400000})
	command("machine_insert", {"machine_id": printer, "item_id": "resource-canister-2", "socket_id": socket})
	command("machine_unfit", {"machine_id": refinery_frame, "item_id": refinery_head, "socket_id": ""})
	command("machine_pack", {"machine_id": printer})
	move([-2000, 0, 0])
	command("machine_deploy", {"machine_id": printer, "position": [-2000, 0, 0], "mode": "surface"})
	var generator: String = ""
	for id in workshop["mounts"]:
		if workshop["parts"][id]["kind"] == "solar": generator = workshop["mounts"][id]
	command("machine_wire", {"machine_id": generator, "other_id": printer, "item_id": printer_cable})
	move([-6000, 0, -1000])
	fit(processing_frame, refinery_head)
	command("machine_run", {"machine_id": processing_frame, "recipe": "refine.ice"})
	step(60)
	check(production.capture_snapshot().value["cargo"]["resource-canister-1"]["water"] == 1000000, "powered extracted ice becomes water in the attached canister")
	# Wait for the actual generator to charge the redeployed printer's local buffer.
	step(1800)
	move([-2000, 0, 0])
	var host := FirstPlayableHost.new()
	root.add_child(host)
	var key: String = "workshop-capture-player-one-0000000000"
	check(host.configure(world, [key, "workshop-capture-player-two-0000000000"], 27850).is_success, "capture host opens")
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:27850")
	OS.set_environment("FRONTIER_INVITE_KEY", key)
	runner.set_physics_process(true)
	var client := FirstPlayableBootstrap.new()
	root.add_child(client)
	await create_timer(2.0).timeout
	check(not client._latest.is_empty(), "graphical client receives the verified workshop")
	if client._latest.is_empty():
		quit(1)
		return
	client._habitat.character.read_local_keyboard = false
	client._tabs.current_tab = 3
	var panel: MachineryPanel = client._machinery_panel
	for index in range(panel._machine.item_count):
		if panel._machine.get_item_metadata(index) == printer: panel._machine.select(index)
	panel._kind.select(MachineryWorkshop.KINDS.keys().find("controller"))
	panel._send("machine_print")
	await create_timer(0.75).timeout
	check(panel._feedback.text == "Completed", "graphical controls print a physical controller from attached refined iron")
	client._habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	client._habitat.camera.position = Vector3(-8.8, 5.5, 4.5)
	client._habitat.camera.look_at(Vector3(-8.8, 0.8, 1.6))
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/resource-workshop")
	check(root.get_texture().get_image().save_png("res://reports/resource-workshop/workshop.png") == OK, "actual game screenshot saved")
	print("Graphical resource workshop: %d failures; screenshot reports/resource-workshop/workshop.png" % failures)
	client.free()
	host.free()
	world.free()
	quit(1 if failures else 0)
