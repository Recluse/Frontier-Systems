extends "res://tests/godot/spatial_wall_runtime_test.gd"


func record() -> Dictionary:
	return {"production": production.observation(context).value, "inventory": inventory.own_inventory_observation(context).value, "position": inventory.own_position(context).value}


func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event)
	event.pressed = false
	root.push_input(event)


func finish() -> void:
	move([0, 0, 0])
	command("process", {"recipe_id": "craft.plate"})
	step(120)
	command("materialize_plate", {})
	var plate: String = production.observation(context).value["components"][0]
	var panel := MachineryPanel.new()
	root.add_child(panel)
	panel.configure(world)
	panel.observe(record())
	for index in range(panel._part.item_count):
		if panel._part.get_item_metadata(index) == plate: panel._part.select(index)
	panel._new_wall.pressed.emit()
	await process_frame
	check(panel._coordinate_grid.columns == 2 and panel._coordinate_labels[0].text == "X (m)", "wall target is a labelled vertical metre grid")
	check(panel._axes[0].get_line_edit().has_focus(), "explicit new wall transition focuses X")
	key(KEY_TAB)
	await process_frame
	check(panel._axes[1].get_line_edit().has_focus(), "Tab moves X to Y")
	key(KEY_TAB)
	await process_frame
	check(panel._axes[2].get_line_edit().has_focus(), "Tab moves Y to Z")
	key(KEY_TAB)
	await process_frame
	check(panel._wall_turn.has_focus(), "Tab moves Z to orientation")
	key(KEY_TAB, true)
	await process_frame
	check(panel._axes[2].get_line_edit().has_focus(), "Shift+Tab returns orientation to Z")
	panel._axes[2].get_line_edit().text = "-1.0"
	key(KEY_ENTER)
	await process_frame
	check(is_equal_approx(panel._axes[2].value, -1.0), "Enter applies signed decimal metres")
	panel._axes[0].get_line_edit().grab_focus()
	panel._axes[0].get_line_edit().select_all()
	for character in "0.1":
		var event := InputEventKey.new()
		event.unicode = character.unicode_at(0)
		event.keycode = character.unicode_at(0) as Key
		event.physical_keycode = event.keycode
		event.pressed = true
		root.push_input(event)
	panel._wall_turn.select(1)
	panel._wall_turn.item_selected.emit(1)
	var before: String = JSON.stringify(world.capture_world_snapshot_json().value)
	panel._send("wall_build")
	check(panel._pending_wall.get("position") == [100, 0, -1000], "build applies active unsubmitted coordinate text before freezing target")
	check(panel._pending_wall.get("quarter_turn") == 1, "build freezes dropdown orientation")
	before = JSON.stringify(world.capture_world_snapshot_json().value)
	var held: Dictionary = panel._pending_wall.duplicate(true)
	panel._axes[0].value = 42
	panel._wall_turn.select(0)
	panel._new_wall.pressed.emit()
	check(panel._pending_wall == held and panel._new_wall.disabled and panel._show_placement.disabled, "pending target survives edits and blocks presentation transitions")
	check(JSON.stringify(world.capture_world_snapshot_json().value) == before, "input advice and queued intent do not mutate canonical state")
	step()
	panel.observe(record())
	var id: String = panel._record["production"]["walls"].keys()[0]
	panel._wall.item_selected.emit(panel._wall.selected)
	check(not panel._coordinate_grid.visible and not panel._wall_turn.visible and panel._wall_build_button.disabled, "dropdown inspection hides draft inputs and disables build")
	check(panel._wall_input_hint.text.contains("read-only") and panel._placement_status.text.contains(id), "inspection explains observed pose and explicit new-wall transition")
	var draft: Array = [panel._axes[0].value, panel._axes[1].value, panel._axes[2].value]
	panel._new_wall.pressed.emit()
	check(panel._selected(panel._wall).is_empty() and panel._coordinate_grid.visible and not panel._wall_build_button.disabled, "new wall button clears settled selection and enables draft")
	check([panel._axes[0].value, panel._axes[1].value, panel._axes[2].value] == draft, "inspection-to-placement retains draft coordinates")
	panel.observe(record())
	check(panel._selected(panel._wall).is_empty(), "observation refresh does not undo intentional new-wall transition")
	panel.select_wall(id)
	var lost: Dictionary = record()
	lost["production"]["walls"].erase(id)
	lost["production"]["walls"]["wall.other"] = {"position": [0, 0, 0], "quarter_turn": 0}
	panel.observe(lost)
	panel.observe(lost)
	check(panel._selected(panel._wall).is_empty() and panel._wall_remove_button.disabled, "vanished inspection never silently targets another wall")
	panel.select_wall("wall.other")
	panel.observe({})
	check(panel._new_wall.disabled and panel._wall_turn.disabled and panel._wall.disabled and not panel._axes[0].editable and panel._show_placement.disabled, "unavailable scoped observation disables wall inputs and transitions")
	panel._new_wall.pressed.emit()
	check(panel._record.is_empty() and panel._selected(panel._wall).is_empty(), "stale transition cannot invent an observed target")
	panel.observe(lost)
	check(panel._selected(panel._wall).is_empty() and panel._wall_remove_button.disabled, "fresh observation after an empty record does not silently restore inspection")
	panel.free()
	world.free()
	print("Wall input usability: %d failures" % failures)
	quit(1 if failures else 0)
