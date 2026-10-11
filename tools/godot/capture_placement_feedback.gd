extends "res://tests/godot/machinery_runtime_test.gd"


## Captures only presentation over the real finite-material workshop fixture.
func finish() -> void:
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
	var habitat := ProceduralHabitatPreview.new()
	root.add_child(habitat)
	habitat.character.read_local_keyboard = false
	var preview := MachineryPreview.new()
	habitat.add_child(preview)
	preview.observe(production.observation(context).value)
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var panel := MachineryPanel.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size.x = 510
	canvas.add_child(panel)
	panel.configure(world)
	panel.bind_preview(preview)
	panel.observe({"production": production.observation(context).value, "inventory": inventory.own_inventory_observation(context).value, "position": inventory.own_position(context).value})
	panel.select_machine(printer)
	panel._axes[0].value = 0.9
	panel._axes[2].value = 0.4
	panel._show_placement.button_pressed = true
	habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	habitat.camera.position = Vector3(-2.5, 4, 7)
	habitat.camera.look_at(Vector3(-5.1, 0.6, 2.4))
	DirAccess.make_dir_recursive_absolute("res://reports/placement-feedback")
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://reports/placement-feedback/ghost.png") == OK, "graphical ghost capture saved")
	panel._send("machine_deploy")
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://reports/placement-feedback/pending.png") == OK, "pending command capture saved before simulation validation")
	step()
	panel.observe({"production": production.observation(context).value, "inventory": inventory.own_inventory_observation(context).value, "position": inventory.own_position(context).value})
	preview.observe(panel._record["production"])
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://reports/placement-feedback/selected.png") == OK, "selected settled frame capture saved")
	panel.free()
	canvas.free()
	habitat.free()
	world.free()
	print("Placement graphical capture: %d failures" % failures)
	quit(1 if failures else 0)
