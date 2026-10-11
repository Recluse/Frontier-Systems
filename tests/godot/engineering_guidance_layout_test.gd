extends "res://tests/godot/client_inventory_shell_test.gd"

## Socket-free actual shell. Long receipts are deliberately larger than one line.
func run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: push_error("Layout fixture deadline"); quit(1))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "canonical fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	client = InventoryClient.new()
	root.add_child(client)
	client.set_process(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	observe_shell()
	# Detached host observation permits requesting work; no owner command is applied.
	remote._observation["production"]["can_operate"] = true
	check(remote._projection.accept_record(remote._observation["production"]).is_success, "detached production view accepted")
	remote.observation_received.emit(remote._observation)
	panel = client._inventory_panel
	await settle()
	var before: String = world.capture_world_snapshot_json().value
	var observation_before: String = JSON.stringify(remote._observation)
	var reason: String = "Original host rejection: " + "the selected resource and component prerequisites must be reviewed in the current observation. ".repeat(8)
	var production: LocalProductionPanel = client._production_panel
	var machinery: MachineryPanel = client._machinery_panel
	for extent: Vector2i in [Vector2i(1920, 1080), Vector2i(1100, 720)]:
		root.size = extent
		(client._tabs.get_parent() as HSplitContainer).split_offset = 420 if extent.x == 1100 else 540
		await settle()
		check(client._tabs.size.x <= (420 if extent.x == 1100 else 540), "requested sidebar width remains supported")
		for tab_index: int in [0, 1, 3]:
			client._tabs.current_tab = tab_index
			await settle()
			var feedback: Label
			var scroll: ScrollContainer
			if tab_index == 0:
				production._send("process", {"recipe_id": "refine.iron"})
				feedback = production._feedback
				scroll = client._scroll
			elif tab_index == 1:
				panel._submit("move", {})
				feedback = panel._result
				scroll = panel.get_parent()
			else:
				machinery._send("machine_craft")
				feedback = machinery._feedback
				scroll = machinery.get_parent()
			var request: SimulationCommand = remote.sent[-1]
			var waiting: String = feedback.text
			var unrelated := ProductionDevelopmentCommand.new()
			unrelated.command_id = &"unrelated-layout-receipt"
			remote.command_completed.emit(unrelated, ServiceResult.failure(&"production_rejected", reason))
			check(feedback.text == waiting, "unrelated receipt cannot replace own pending feedback")
			var code: StringName = &"inventory_revision_conflict" if tab_index == 1 else (&"invalid_machinery_intent" if tab_index == 3 else &"production_rejected")
			remote.command_completed.emit(request, ServiceResult.failure(code, reason))
			await settle()
			check(production._pending.is_empty() if tab_index == 0 else (panel._pending.is_empty() if tab_index == 1 else machinery._pending.is_empty()), "matching failure clears only its pending request")
			check(feedback.text.contains(reason) and feedback.text.contains("Code: " + String(code)) and feedback.text.contains("Next:"), "complete original reason, code and advice retained")
			check(feedback.size.x <= scroll.size.x and feedback.get_line_count() > 3, "long advice wraps within actual shell viewport")
			check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "engineering panel needs no horizontal scrolling")
			check(scroll.follow_focus, "outer scroll follows retry control focus")
			var buttons: Array[Button] = production._buttons if tab_index == 0 else (panel._buttons if tab_index == 1 else machinery._action_buttons)
			for button: Button in buttons:
				if not button.is_visible_in_tree(): continue
				check(button.size.x <= scroll.size.x, "retry control fits narrow shell")
				if button.disabled: continue
				button.grab_focus()
				await settle()
				check(scroll.get_global_rect().encloses(button.get_global_rect()), "focused retry control reachable through existing scroll")
			if OS.get_cmdline_user_args().has("--capture-guidance-layout"):
				scroll.ensure_control_visible(feedback)
				await settle()
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("res://var/ci/guidance-layout")
				check(root.get_texture().get_image().save_png("res://var/ci/guidance-layout/%dx%d-tab%d.png" % [extent.x, extent.y, tab_index]) == OK, "ordinary native internal capture")
		client._tabs.current_tab = 0
		production._show_section(3)
		production._send("repair_tool_component", {})
		remote.command_completed.emit(remote.sent[-1], ServiceResult.failure(&"production_rejected", reason))
		await settle()
		check(production._maintenance_feedback.text.contains(reason) and production._maintenance_feedback.text.contains("Code: production_rejected") and production._maintenance_feedback.text.contains("Next:"), "nested maintenance preserves complete failure advice")
		check(production._maintenance_feedback.size.x <= production._section_scroll.size.x and production._maintenance_feedback.get_line_count() > 3, "maintenance advice wraps within nested viewport")
		production._section_scroll.ensure_control_visible(production._maintenance_feedback)
		client._scroll.ensure_control_visible(production._section_scroll)
		await settle()
		check(production._section_scroll.get_global_rect().intersects(production._maintenance_feedback.get_global_rect()), "maintenance advice reachable in existing nested scroll")
		production._show_section(0)
	check(remote.sent.size() == 8, "only eight explicitly invoked actions; focus and rendering never retry")
	check(world.capture_world_snapshot_json().value == before and JSON.stringify(remote._observation) == observation_before, "layout and receipts preserve canonical state and observation")
	client.queue_free()
	world.queue_free()
	await settle()
	PlayerInputSettings.instance().release_all()
	print("Engineering guidance actual-shell layout: %d failures" % failures)
	quit(1 if failures else 0)
