extends SceneTree

var failures: int = 0
var helper: FirstPlayableControlsHelp
var tabs: TabContainer


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event)
	event.pressed = false
	root.push_input(event)


func run() -> void:
	# Set fixture defaults in memory only; never save the user's preferences.
	PlayerInputSettings.instance()._reset_map()
	root.size = Vector2i(640, 480)
	tabs = TabContainer.new()
	tabs.position = Vector2(350, 0)
	tabs.size = Vector2(280, 400)
	root.add_child(tabs)
	for title in ["Workstation", "Inventory", "Settings", "Construction", "Terrain", "Guide"]:
		var panel := Label.new()
		panel.name = title
		tabs.add_child(panel)
	helper = FirstPlayableControlsHelp.new()
	helper.size = Vector2(260, 260)
	root.add_child(helper)
	helper.configure(tabs)
	await process_frame
	await process_frame
	check(helper.size.x <= 260 and helper.get_combined_minimum_size().x <= 260, "help fits a narrow 260 pixel column")
	check(not helper._details.visible, "help starts compact")
	helper._toggle.grab_focus()
	key(KEY_ENTER)
	await process_frame
	check(helper._details.visible and helper._close.has_focus(), "keyboard confirm opens help and focuses close")
	key(KEY_TAB)
	await process_frame
	check(not helper._close.has_focus(), "Tab leaves close button")
	key(KEY_TAB, true)
	await process_frame
	check(helper._close.has_focus(), "Shift+Tab returns to close")
	helper._details.grab_focus()
	key(KEY_DOWN)
	await process_frame
	check(helper._details.scroll_vertical > 0, "focused help scrolls by keyboard")
	key(KEY_ESCAPE)
	await process_frame
	check(not helper._details.visible and helper._toggle.has_focus(), "focused UI cancel closes and restores toggle focus")
	helper._toggle.button_pressed = true
	key(KEY_ENTER)
	await process_frame
	check(not helper._details.visible and helper._toggle.has_focus(), "keyboard close button works")
	for index in range(6):
		helper._selector.select(index)
		helper._selector.item_selected.emit(index)
		check(tabs.current_tab == index, "selector retains tab index %d" % index)
	tabs.current_tab = 0
	check(helper._selector.selected == 0, "native tab change synchronizes selector")
	tabs.get_tab_bar().grab_focus()
	key(KEY_RIGHT)
	await process_frame
	check(tabs.current_tab == 1 and helper._selector.selected == 1, "focused native tab bar traverses using UI arrow")
	helper._selector.grab_focus()
	key(KEY_ENTER)
	await process_frame
	check(helper._selector.get_popup().visible, "keyboard confirm opens selector choices")
	key(KEY_ESCAPE)
	await process_frame
	var controls := PlayerInputSettings.instance()
	var original: InputEvent = InputMap.action_get_events("look")[0].duplicate()
	var remap := InputEventKey.new()
	remap.physical_keycode = KEY_K
	PlayerInputSettings._set_binding("look", remap)
	controls.bindings_changed.emit()
	check(helper._summary.text.contains(controls.binding_label("look")) and helper._text.text.contains("hold " + controls.binding_label("look")), "help follows actual in-memory remap")
	PlayerInputSettings._set_binding("look", original)
	controls.bindings_changed.emit()
	helper._toggle.button_pressed = true
	tabs.get_tab_bar().grab_focus()
	key(KEY_ESCAPE)
	await process_frame
	check(helper._details.visible, "cancel outside helper does not close help")
	helper._close.grab_focus()
	controls.rebinding = true
	key(KEY_ESCAPE)
	await process_frame
	check(helper._details.visible, "help does not intercept rebinding cancel")
	controls.rebinding = false
	root.gui_release_focus()
	var movement := InputEventKey.new()
	movement.physical_keycode = KEY_W
	movement.pressed = true
	root.push_input(movement)
	check(not root.is_input_handled(), "help does not consume native movement input")
	var pick := InputEventMouseButton.new()
	pick.button_index = MOUSE_BUTTON_LEFT
	pick.position = Vector2(630, 470)
	pick.pressed = true
	var motion := InputEventMouseMotion.new()
	motion.position = pick.position
	motion.global_position = pick.position
	root.push_input(motion, true)
	pick.global_position = pick.position
	# Isolate GUI handling from the engine queue, which marks mouse picks handled.
	var native_picking: bool = root.physics_object_picking
	root.physics_object_picking = false
	root.push_input(pick, true)
	check(not root.is_input_handled(), "help leaves mouse clicks outside controls unhandled before native picking")
	root.physics_object_picking = native_picking
	var settings := PlayerControlsPanel.new()
	settings.position = Vector2(0, 280)
	settings.size = Vector2(260, 500)
	root.add_child(settings)
	await process_frame
	check(settings.get_combined_minimum_size().x <= 260, "binding settings fit narrow column")
	check(not controls.accepts_gameplay_input(), "visible settings still suspend navigation")
	settings.hide()
	check(controls.accepts_gameplay_input(), "hiding settings restores gameplay availability")
	settings.free()
	helper.free()
	tabs.free()
	print("Desktop controls help: %d failures" % failures)
	quit(0 if failures == 0 else 1)
