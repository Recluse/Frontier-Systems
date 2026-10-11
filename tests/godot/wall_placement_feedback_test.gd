extends "res://tests/godot/spatial_wall_runtime_test.gd"


func view_record() -> Dictionary:
	return {"production": production.observation(context).value, "inventory": inventory.own_inventory_observation(context).value, "position": inventory.own_position(context).value}


func select_plate(panel: MachineryPanel, id: String) -> void:
	for index in range(panel._part.item_count):
		if panel._part.get_item_metadata(index) == id: panel._part.select(index)
	panel._refresh_placement()


func finish() -> void:
	move([0, 0, 0])
	command("process", {"recipe_id": "craft.plate"})
	step(120)
	command("materialize_plate", {})
	var plate: String = production.observation(context).value["components"][0]
	var panel := MachineryPanel.new()
	root.add_child(panel)
	panel.configure(world)
	var preview := MachineryPreview.new()
	root.add_child(preview)
	panel.bind_preview(preview)
	panel.observe(view_record())
	select_plate(panel, plate)
	panel._placement_kind.select(1)
	panel._axes[2].value = -1
	panel._show_placement.button_pressed = true
	panel._refresh_placement()
	var before: String = JSON.stringify(world.capture_world_snapshot_json().value)
	var observed: String = JSON.stringify(panel._record)
	var ghost: MeshInstance3D = preview._feedback_root.get_child(0)
	check((ghost.mesh as BoxMesh).size == Vector3(1, 2, 0.1), "X wall ghost has physical panel dimensions")
	check(ghost.position.is_equal_approx(ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(0, 1, -1)), "wall ghost uses workbench origin and floor-anchor height")
	check(preview._feedback_root.find_children("*", "CollisionObject3D", true, false).is_empty(), "wall ghost has no collision or pick objects")
	check(ghost.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ghost never casts a physical-looking shadow")
	var footprint: MeshInstance3D = preview._feedback_root.get_child(1)
	check((footprint.mesh as BoxMesh).size.x == 1, "X footprint follows panel width")
	panel._wall_turn.select(1)
	panel._refresh_placement()
	ghost = preview._feedback_root.get_child(0)
	check((ghost.mesh as BoxMesh).size == Vector3(0.1, 2, 1), "Z orientation rotates footprint and mesh")
	check(panel._placement_status.text.contains("Wall along Z"), "orientation advice names Z")
	panel._axes[1].value = 0.1
	check(panel._placement_status.text.contains("Floor placement requires Y=0"), "walls explain floor restriction")
	panel._mode.select(1)
	panel._refresh_placement()
	check(panel._placement_status.text.contains("no Freeform"), "machine Freeform does not authorize floating walls")
	check(JSON.stringify(world.capture_world_snapshot_json().value) == before and JSON.stringify(panel._record) == observed, "ghost edits never persist or mutate observations")
	panel._send("wall_build")
	before = JSON.stringify(world.capture_world_snapshot_json().value)
	check(not panel._pending.is_empty() and panel._wall_turn.disabled and panel._part.disabled and panel._placement_kind.disabled, "pending wall freezes plate, orientation and preview controls")
	var held: Dictionary = panel._pending_wall.duplicate(true)
	var request: String = panel._pending
	panel._send("wall_build")
	panel._send("wall_remove")
	check(panel._pending == request and panel._pending_wall == held, "duplicate build and competing remove are suppressed")
	panel._axes[0].value = 12
	panel._wall_turn.select(0)
	panel._part.select(0)
	panel._placement_kind.select(0)
	panel._refresh_placement()
	ghost = preview._feedback_root.get_child(0)
	check(ghost.position.is_equal_approx(ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(0, 1.1, -1)) and (ghost.mesh as BoxMesh).size == Vector3(0.1, 2, 1), "queued target holds submitted pose despite programmatic UI edits")
	check(JSON.stringify(world.capture_world_snapshot_json().value) == before and JSON.stringify(panel._record) == observed, "presentation and queued intent do not persist or mutate observations")
	step()
	check(not last.is_success and panel._pending.is_empty() and production.observation(context).value["components"].has(plate), "host rejects invalid floor and preserves plate")
	panel._placement_kind.select(1)
	panel._axes[0].value = 0
	panel._axes[1].value = 0
	panel._wall_turn.select(1)
	select_plate(panel, plate)
	panel._send("wall_build")
	step()
	check(last.is_success and not panel._show_placement.button_pressed, "host accepts actual Z build and retires ghost")
	panel.observe(view_record())
	var wall: String = production.capture_snapshot().value["walls"].keys()[0]
	var physical := ProceduralProductionPreview.new()
	root.add_child(physical)
	physical.observe(panel._record["production"])
	physical.wall_selected.connect(panel.select_wall)
	physical.wall_selected.emit(wall)
	check(panel._selected(panel._wall) == wall and panel._placement_kind.selected == 1, "clicked wall selects its observed stable identity and wall feedback")
	check(preview._feedback_root.get_child_count() == 5, "selected wall has only a footprint and label")
	footprint = preview._feedback_root.get_child(0)
	check(is_equal_approx((footprint.mesh as BoxMesh).size.x, 0.1), "selected wall uses observed Z pose even if build orientation changes")
	panel._wall_turn.select(0)
	panel._refresh_placement()
	check(is_equal_approx((preview._feedback_root.get_child(0).mesh as BoxMesh).size.x, 0.1), "selected orientation remains independent from target orientation")
	panel.hide()
	check(preview._feedback_root.get_child_count() == 0, "hidden wall panel clears decorations")
	panel.show()
	check(preview._feedback_root.get_child_count() == 5, "visible panel restores observed wall selection")
	panel._send("wall_remove")
	held = panel._pending_wall.duplicate(true)
	panel.select_wall("missing-wall")
	panel._send("wall_build")
	check(panel._pending_wall == held and panel._placement_status.text.contains("Waiting for host"), "remove target is frozen and duplicate actions suppressed")
	step()
	check(last.is_success and production.capture_snapshot().value["walls"].is_empty(), "real remove returns physical plate")
	panel.observe(view_record())
	physical.observe(panel._record["production"])
	check(preview._feedback_root.get_child_count() == 0 and physical._spatial_walls.is_empty(), "removed selection and canonical collider retire")
	plate = production.observation(context).value["components"][0]
	select_plate(panel, plate)
	panel._show_placement.button_pressed = true
	var missing: Dictionary = view_record()
	missing["inventory"]["items"] = []
	panel.observe(missing)
	check(preview._feedback_root.get_child_count() == 0, "lost owned plate retires stale ghost")
	panel.observe(view_record())
	panel.observe({})
	check(preview._feedback_root.get_child_count() == 0 and panel._action_buttons[0].disabled and panel._wall.item_count == 0, "unavailable observations clear selection and block actions")
	panel.observe(view_record())
	select_plate(panel, plate)
	panel._show_placement.button_pressed = true
	panel.free()
	check(preview._feedback_root.get_child_count() == 0, "retiring wall panel clears presentation")
	physical.free()
	preview.free()
	var sample: Dictionary = view_record()
	var selected_sample: Dictionary = sample.duplicate(true)
	selected_sample["production"]["walls"]["wall.advice"] = {"position": [0, 0, -2000], "quarter_turn": 1}
	var selection_advice: Dictionary = WallPlacementFeedback.describe(selected_sample, "", "wall.advice", [0, 0, 0], 0, false, {})
	check(selection_advice["text"].contains("Wall along Z") and selection_advice["text"].contains("Outside estimated") and selection_advice["text"].contains("Selected X 0.00 / Y 0.00 / Z -2.00"), "clicked wall reach and orientation use its observed pose instead of unrelated target controls")
	check(not WallPlacementFeedback.describe(sample, plate, "", [2000, 0, 0], 0, true, {})["advisory_ok"], "out of reach is advisory")
	check(WallPlacementFeedback.describe(sample, plate, "", [1, 0, -1000], 0, true, {})["text"].contains("0.1 m grid"), "off grid input has explicit advice")
	check(WallPlacementFeedback.describe(sample, "resource-canister-1", "", [0, 0, -1000], 0, true, {})["text"].contains("owned physical plate"), "nonplate selection has useful advice")
	print("Wall placement feedback integration: %d failures" % failures)
	world.free()
	quit(1 if failures else 0)
