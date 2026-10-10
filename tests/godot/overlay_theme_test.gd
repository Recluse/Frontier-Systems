extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in OverlayThemeController.BUILTIN_PATHS:
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var parsed: ServiceResult = OverlayThemeDefinition.from_record(record)
		_check(parsed.is_success, "shipped theme must parse")
		if not parsed.is_success:
			continue
		var definition: OverlayThemeDefinition = parsed.value
		var theme: Theme = definition.build_theme()
		_check(theme.default_font_size == int(record["font_size"]), "theme must apply font size")
		_check(theme.get_color("font_color", "Label") == Color(record["colors"]["text"]), "theme must apply text color")
		_check(theme.get_color("font_color", "ItemList") == Color(record["colors"]["text"]), "inventory lists must inherit semantic palette")
		_check(theme.get_constant("separation", "VBoxContainer") == int(record["spacing"]), "theme must apply spacing")
		_check(theme.get_stylebox("panel", "PanelContainer") is StyleBoxFlat, "theme must build native panel assets")
		var detached: Dictionary = definition.to_record()
		detached["colors"]["text"] = "#000000"
		_check(definition.to_record()["colors"]["text"] == record["colors"]["text"], "theme definition reads must be detached")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OverlayThemeController.BUILTIN_PATHS[0]))
	var invalid: Dictionary = record.duplicate(true)
	invalid["script"] = "res://untrusted.gd"
	_check(not OverlayThemeDefinition.from_record(invalid).is_success, "executable fields must reject")
	invalid = record.duplicate(true)
	invalid["colors"]["text"] = "#FFFFFF00"
	_check(not OverlayThemeDefinition.from_record(invalid).is_success, "transparent colors must reject")
	invalid = record.duplicate(true)
	invalid["font_size"] = 16.5
	_check(not OverlayThemeDefinition.from_record(invalid).is_success, "fractional dimensions must reject")
	invalid = record.duplicate(true)
	invalid["spacing"] = 100000
	_check(not OverlayThemeDefinition.from_record(invalid).is_success, "excessive spacing must reject")
	var world := WorldRuntime.new()
	root.add_child(world)
	var before: String = world.capture_world_snapshot_json().value
	var screen := Control.new()
	root.add_child(screen)
	var background := ColorRect.new()
	screen.add_child(background)
	var label := Label.new()
	label.text = "Read-only overlay"
	screen.add_child(label)
	var controller := OverlayThemeController.new()
	screen.add_child(controller)
	_check(controller.configure(screen, background, false, false).is_success, "selector must configure without user settings")
	_check(controller.selected_theme_id() == OverlayThemeController.DEFAULT_ID, "default must select initially")
	_check(controller.select_theme("overlay.terminal").is_success, "optional theme must select")
	_check(background.color == Color("#07120B"), "selection must update client background")
	_check(label.get_theme_color("font_color") == Color("#C5F7D3"), "child widgets must inherit selected theme")
	var custom: Dictionary = record.duplicate(true)
	custom["definition_id"] = "overlay.custom-test"
	custom["display_name"] = "Custom test"
	custom["colors"]["accent"] = "#FF8800"
	_check(controller.register_theme(custom).is_success, "declarative mod must register")
	_check(controller.select_theme("overlay.custom-test").is_success, "custom theme must select")
	_check(not controller.register_theme(custom).is_success, "duplicate theme IDs must reject")
	var selected_theme: Theme = screen.theme
	_check(not controller.select_theme("unknown").is_success and screen.theme == selected_theme, "missing selection must preserve current theme")
	controller.select_theme(OverlayThemeController.DEFAULT_ID)
	_check(controller.selected_theme_id() == OverlayThemeController.DEFAULT_ID, "default reset must restore selected ID")
	_check(world.capture_world_snapshot_json().value == before, "theme changes must preserve canonical world state")
	screen.queue_free()
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("Overlay theme validation and client isolation scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
