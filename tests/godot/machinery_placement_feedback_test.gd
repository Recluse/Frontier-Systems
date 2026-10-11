extends "res://tests/godot/machinery_runtime_test.gd"


func view_record() -> Dictionary:
	return {"production": production.observation(context).value, "inventory": inventory.own_inventory_observation(context).value, "position": inventory.own_position(context).value}


func finish() -> void:
	move([0, 0, 0])
	var printer: String = ""
	for id in production.capture_snapshot().value["machinery"]["mounts"]:
		if production.capture_snapshot().value["machinery"]["parts"][id]["kind"] == "printhead":
			printer = production.capture_snapshot().value["machinery"]["mounts"][id]
	command("machine_pack", {"machine_id": printer})
	var panel := MachineryPanel.new()
	root.add_child(panel)
	panel.configure(world)
	var preview := MachineryPreview.new()
	root.add_child(preview)
	panel.bind_preview(preview)
	panel.observe(view_record())
	preview.observe(panel._record["production"])
	preview.machine_selected.connect(panel.select_machine)
	preview.machine_selected.emit(printer)
	panel._show_placement.button_pressed = true
	panel._axes[0].value = 0.8
	panel._axes[1].value = 0.1
	panel._axes[2].value = -0.4
	var before: String = JSON.stringify(world.capture_world_snapshot_json().value)
	var observation: String = JSON.stringify(panel._record)
	check(panel._placement_status.text.contains("Floor placement requires Y=0"), "floor feedback explains current host adapter")
	var ghost: MeshInstance3D = preview._feedback_root.get_child(0)
	check(ghost.position.is_equal_approx(ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(0.8, 0.85, -0.4)), "XYZ target uses millimetres and DISPLAY_ORIGIN, with height above base")
	check(preview._feedback_root.find_children("*", "CollisionObject3D", true, false).is_empty(), "ghost has no physics or picking authority")
	var target: Vector3 = MachineryPlacementFeedback.display_position([800, 100, -400])
	var directions: Dictionary = {"+X": Vector3.RIGHT, "+Y": Vector3.UP, "+Z": Vector3.BACK}
	for label in preview._feedback_root.find_children("*", "Label3D", true, false):
		if directions.has(label.text):
			check(label.position.is_equal_approx(target + Vector3(0, 0.1, 0) + directions[label.text]), "axis " + label.text + " matches positive world direction")
	check(JSON.stringify(world.capture_world_snapshot_json().value) == before and JSON.stringify(panel._record) == observation, "ghost and intent never enter world snapshots or observations")
	panel._send("machine_deploy")
	check(not panel._pending.is_empty() and panel._placement_status.text.contains("Waiting for host"), "queued deployment has explicit pending feedback")
	check(panel._action_buttons[0].disabled and not panel._axes[0].editable, "pending command suppresses duplicate actions and editing")
	panel._axes[0].value = 12
	var held: MeshInstance3D = preview._feedback_root.get_child(0)
	check(is_equal_approx(held.position.x, ProceduralWorldInventoryPreview.DISPLAY_ORIGIN.x + 0.8), "submitted ghost stays frozen even if controls change")
	step()
	check(not last.is_success and panel._pending.is_empty(), "actual host rejects floor Y rather than trusting client preview")
	check(not production.capture_snapshot().value["machinery"]["placements"].has(printer), "rejection creates no physical placement")
	check(panel._show_placement.button_pressed and not panel._feedback.text.is_empty(), "rejected ghost stays available for correction")
	panel._axes[0].value = 0.8
	panel._axes[0].value = 0.0
	panel._axes[2].value = -1.0
	panel._mode.select(1)
	panel._refresh_placement()
	panel._send("machine_deploy")
	step()
	check(last.is_success and not panel._show_placement.button_pressed, "host accepts freeform placement and retires ghost on completion")
	panel.observe(view_record())
	preview.observe(panel._record["production"])
	check(preview._feedback_root.get_child_count() == 13, "settled selected machine shows full reserved envelope and selection label")
	var selected_label: Label3D = preview._feedback_root.get_child(12)
	check(selected_label.text.contains(printer.right(8)), "world selection and picker share stable selected identity")
	panel.hide()
	check(preview._feedback_root.get_child_count() == 0, "hidden panel clears placement and selection decorations")
	panel.show()
	check(preview._feedback_root.get_child_count() == 13, "returning to panel restores selection")
	var missing: Dictionary = view_record()
	missing["production"]["machinery"]["parts"].erase(printer)
	panel.observe(missing)
	check(not panel._placement_status.text.contains(printer), "removed selected frame falls back to an observed frame")
	panel.free()
	check(preview._feedback_root.get_child_count() == 0, "retiring panel clears its presentation")
	preview.free()
	command("machine_pack", {"machine_id": printer})
	var sample: Dictionary = view_record()
	var other: String = printer
	var far: Dictionary = MachineryPlacementFeedback.describe(sample, other, [2000, 0, 0], "surface", true, false)
	check(not far["advisory_ok"] and far["text"].contains("Outside estimated"), "out-of-reach target feedback uses observed logical body")
	print("Placement feedback integration: %d failures" % failures)
	world.free()
	quit(1 if failures else 0)
