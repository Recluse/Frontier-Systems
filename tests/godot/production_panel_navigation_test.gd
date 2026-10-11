extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	root.size = Vector2i(900, 1000)
	root.content_scale_size = Vector2i(900, 1000)
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "Detached fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	var outer := ScrollContainer.new()
	outer.position = Vector2(20, 20)
	outer.size = Vector2(420, 920)
	outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(outer)
	var panel := LocalProductionPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(panel)
	check(panel.configure(world).is_success, "Panel configures")
	var before: String = world.capture_world_snapshot_json().value
	await process_frame
	await process_frame
	check(panel._navigation.item_count == 7, "Every task has a visible named navigation choice")
	check(panel._extract_button.is_visible_in_tree(), "Gather action is visible initially")
	check(not panel._fabricate_button.is_visible_in_tree(), "Other tasks do not extend the initial column")
	check(panel._feedback.get_parent() == panel and panel._guide_button.get_parent() == panel, "Guide and result remain above task contents")
	check(panel._amount.get_parent() == panel, "Transfer mass remains available across tasks")
	check(panel._gather_details.text.contains("%d mg remaining" % panel._record["deposits"]["deposit.iron"]), "Gather shows exact finite observed source mass")
	for index in range(panel._sections.size()):
		panel._navigation.select(index)
		panel._show_section(index)
		if index == 2:
			for choice in range(panel._blueprint.item_count):
				if panel._record["blueprints"].has(str(panel._blueprint.get_item_metadata(choice))):
					panel._blueprint.select(choice)
					break
			panel.refresh()
		await process_frame
		await process_frame
		check(panel._sections[index].is_visible_in_tree(), "Chosen task is visible")
		check(panel._section_scroll.size.x <= 420, "Task viewport fits narrow workstation")
		for button in panel._buttons:
			if button.is_visible_in_tree():
				check(button.size.x <= panel._section_scroll.size.x, "Wrapped action fits without horizontal scrolling")
		if OS.get_cmdline_user_args().has("--capture-production-navigation") and index in [0, 1, 2]:
			await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			DirAccess.make_dir_recursive_absolute("res://var/ci/production-navigation/capture")
			check(image.save_png("res://var/ci/production-navigation/capture/task-%d.png" % index) == OK, "Native internal capture saved")
	var recipe: Control = panel.refining_focus_control()
	await process_frame
	check(recipe.is_visible_in_tree() and panel._navigation.selected == 1, "Existing refining focus route exposes its task")
	recipe.grab_focus()
	await process_frame
	check(root.gui_get_focus_owner() == recipe and panel._section_scroll.follow_focus, "Keyboard focus can follow selected controls into view")
	check(panel._recipe_details.text == WorkstationResourceView.recipe_text(panel._record, str(panel._recipe.get_item_metadata(panel._recipe.selected))), "Exact observed recipe quote remains intact")
	var blueprint: String = panel._record["blueprints"].keys()[0]
	for index in range(panel._blueprint.item_count):
		if panel._blueprint.get_item_metadata(index) == blueprint:
			panel._blueprint.select(index)
	panel.refresh()
	var selected_id: String = EquipmentPrerequisiteView.selected(panel._blueprint)
	panel._show_section(2)
	await process_frame
	await process_frame
	panel._salvage_button.grab_focus()
	await process_frame
	await process_frame
	check(panel._section_scroll.scroll_vertical > 0, "Focus reveals the lower equipment action in the bounded task viewport")
	panel._show_section(0)
	check(EquipmentPrerequisiteView.selected(panel._blueprint) == selected_id, "Navigation preserves selected stable blueprint")
	check(panel._fabrication_details.text.contains("required") and panel._fabrication_details.text.contains("reserve:"), "Equipment retains observed material and energy prerequisites")
	check(world.capture_world_snapshot_json().value == before, "Navigation and quotes do not change canonical state")
	panel._send("process", {"recipe_id": "refine.iron"})
	check(not panel._pending.is_empty() and panel._feedback.text == "Queued process", "Pending receipt remains visible above every task")
	check(panel._activity.text.contains("no output confirmed"), "Pending work uncertainty remains visible across tasks")
	panel._show_section(2)
	check(panel._fabrication_details.text.contains("no output confirmed"), "Switching tasks preserves pending uncertainty")
	panel._on_closed()
	check(panel._fabrication_details.text.contains("fresh observation") and panel._recipe_details.text.contains("fresh observation"), "Disconnect preserves outcome uncertainty across tasks")
	panel.queue_free()
	outer.queue_free()
	world.queue_free()
	await process_frame
	if failures == 0:
		print("PASS production task navigation, narrow layout, focus and authority preservation")
	quit(0 if failures == 0 else 1)
