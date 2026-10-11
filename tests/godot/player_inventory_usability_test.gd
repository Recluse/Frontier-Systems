extends "res://tests/godot/player_inventory_components_test.gd"

## Same real domain commands as component contract tests; no listeners or grants.
var scroll: ScrollContainer
var capture: bool = false

func settle() -> void:
	for _frame in range(4): await process_frame

func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	root.push_input(event)
	await settle()

func capture_panel(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://var/ci/inventory-usability-render")
	check(image.save_png("res://var/ci/inventory-usability-render/" + name + ".png") == OK, "ordinary engine capture saved locally")

func check_width(control: Control) -> void:
	check(control.size.x <= scroll.size.x + 1.0, "bounded control width: " + control.get_class())
	for child in control.get_children():
		if child is Control and not child is Popup: check_width(child)

func visible(control: Control) -> bool:
	var rect: Rect2 = control.get_global_rect()
	var viewport: Rect2 = scroll.get_global_rect()
	return rect.position.y >= viewport.position.y and rect.end.y <= viewport.end.y

func run() -> void:
	PlayerInputSettings.instance()._reset_map()
	capture = OS.get_cmdline_user_args().has("--capture-inventory")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(440, 900)
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "presentation fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	remote = RecordingRemote.new()
	root.add_child(remote)
	var background := ColorRect.new()
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll = ScrollContainer.new()
	root.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PlayerInventoryPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	panel.configure(remote)
	var theme_controller := OverlayThemeController.new()
	check(theme_controller.configure(scroll, background, false, false).is_success, "actual built-in default overlay theme")
	theme_controller.free()
	panel.observe(frame())
	for _batch in range(6):
		move(ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"])
		command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		move([0, 0, 0])
		command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		command("process", {"recipe_id": "refine.iron"})
		for _tick in range(120): step()
	command("fabricate_equipment", {"blueprint_id": "equipment.extractor"})
	command("fabricate_tool_part", {"blueprint_id": "part.head.basic", "expected_tool_revision": frame()["tools"]["state_revision"]})
	panel.observe(frame())
	var tool: String = frame()["production"]["structures"].keys()[0]
	var loose: String = frame()["tools"]["loose_parts"][0]["part_id"]
	select_tool(tool)
	choose(panel._part_blueprints, "part.head.basic")
	choose(panel._loose_parts, loose)
	choose(panel._tool_mounts, "head")
	panel._update_buttons()
	for viewport_size: Vector2i in [Vector2i(440, 900), Vector2i(280, 640)]:
		root.size = viewport_size
		await settle()
		check(scroll.follow_focus and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "panel owns bounded focus-following presentation")
		check_width(panel)
		panel._tool_mounts.grab_focus()
		await settle()
		check(visible(panel._tool_mounts), "keyboard focus reveals offscreen mount picker")
		await key(KEY_TAB)
		check(root.gui_get_focus_owner() == panel._component_buttons["fit_tool_part"], "Tab reaches fit action in component order")
		check(visible(panel._component_buttons["fit_tool_part"]), "Tab scrolls action fully into view")
		await capture_panel("%d-selection" % viewport_size.x)
		await key(KEY_TAB, true)
		check(root.gui_get_focus_owner() == panel._tool_mounts and visible(panel._tool_mounts), "Shift+Tab returns to the selected mount and reveals it")
		scroll.grab_focus()
		scroll.scroll_vertical = int(panel._component_details.position.y)
		await settle()
		var before_scroll: int = scroll.scroll_vertical
		await key(KEY_DOWN)
		check(scroll.scroll_vertical > before_scroll, "focused pane keyboard scrolling reaches long prerequisite text")
		await capture_panel("%d-prerequisites-start" % viewport_size.x)
		scroll.ensure_control_visible(panel._component_details)
		await settle()
		check(panel._component_details.get_line_count() > 8 and panel._component_details.get_visible_line_count() == panel._component_details.get_line_count(), "all observed prerequisites wrap without line truncation")
		await capture_panel("%d-prerequisites" % viewport_size.x)
	# Stable unavailable selection uses a real formerly observed blueprint ID.
	var missing: Dictionary = frame()
	missing["tools"]["part_blueprints"].erase("part.head.basic")
	panel.observe(missing)
	var selection: Label = panel._component_selections[panel._part_blueprints]
	check(selection.text.contains("part.head.basic") and selection.text.contains("unavailable"), "unavailable ID explained outside clipped picker")
	scroll.ensure_control_visible(selection)
	await settle()
	await capture_panel("280-unavailable")
	panel.observe(frame())
	panel._part_action("fit_tool_part")
	var pinned: Dictionary = panel._pending_component.duplicate(true)
	var request: SimulationCommand = remote.sent[-1]
	panel.observe(frame())
	check(panel._pending_component == pinned and panel._tool_mounts.disabled and panel._items.focus_mode == Control.FOCUS_NONE, "pending exact IDs/revisions and keyboard selection freeze")
	await settle()
	check(visible(panel._result), "pending feedback automatically revealed")
	panel._result.grab_focus()
	await settle()
	check(panel._result.text.contains(loose) and panel._result.text.contains(tool) and panel._result.text.contains("Production revision: %d" % pinned["expected_revision"]) and panel._result.text.contains("Tool revision: %d" % pinned["expected_tool_revision"]), "pending feedback exposes exact target")
	await capture_panel("280-pending")
	apply(request)
	check(last.is_success, "real paid fit succeeds")
	remote.command_completed.emit(request, last)
	panel.observe(frame())
	check(panel._items.focus_mode == Control.FOCUS_ALL and panel._result.text.contains("Host accepted"), "matching paid receipt restores navigation")
	panel.free()
	scroll.free()
	remote.free()
	world.free()
	if failures == 0: print("Inventory presentation: real paid fixture, desktop/narrow wrapping, injected Tab/focus, unavailable IDs and pending feedback passed.")
	quit(0 if failures == 0 else 1)
