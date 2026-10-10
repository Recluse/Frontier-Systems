extends SceneTree

var _failures: int = 0
var _clicks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var definitions: Dictionary = {}
	for path in OverlayLayoutController.BUILTIN_PATHS:
		var loaded: ServiceResult = OverlayDocumentLoader.read_object(path, 16384)
		_check(loaded.is_success, "built-in layout file must load")
		var parsed: ServiceResult = OverlayLayoutDefinition.from_record(loaded.value)
		_check(parsed.is_success, "built-in layout must validate")
		if parsed.is_success:
			definitions[loaded.value["definition_id"]] = parsed.value
	if definitions.size() != 3:
		quit(1)
		return
	var default_record: Dictionary = definitions["layout.default"].to_record()
	var invalid: Dictionary = default_record.duplicate(true)
	invalid["panel_ids"] = ["overlay.controls", "overlay.controls"]
	_check(not OverlayLayoutDefinition.from_record(invalid).is_success, "duplicate panels must reject")
	invalid = default_record.duplicate(true)
	invalid["scene_path"] = "res://arbitrary.tscn"
	_check(not OverlayLayoutDefinition.from_record(invalid).is_success, "scene paths must reject")
	invalid = default_record.duplicate(true)
	invalid["leading_weight"] = INF
	_check(not OverlayLayoutDefinition.from_record(invalid).is_success, "nonfinite space allocation must reject")
	invalid = default_record.duplicate(true)
	invalid["leading_weight"] = 0.1
	_check(not OverlayLayoutDefinition.from_record(invalid).is_success, "extreme space allocation must reject")
	var world := WorldRuntime.new()
	root.add_child(world)
	var before: String = world.capture_world_snapshot_json().value
	var registry := OverlayPanelRegistry.new()
	var controls := PanelContainer.new()
	controls.custom_minimum_size = Vector2(300, 150)
	var button := Button.new()
	button.text = "Existing command adapter"
	button.pressed.connect(_on_click)
	controls.add_child(button)
	var habitat := Control.new()
	habitat.custom_minimum_size = Vector2(300, 200)
	_check(registry.register_panel("overlay.controls", controls).is_success, "controls panel must register")
	_check(not registry.register_panel("alias", controls).is_success, "panel alias must reject")
	_check(registry.register_panel("overlay.habitat", habitat).is_success, "habitat panel must register")
	var host := OverlayLayoutHost.new()
	root.add_child(host)
	host.size = Vector2(1280, 800)
	_check(host.configure(registry).is_success, "host must configure once")
	var picker := OverlayLayoutController.new()
	root.add_child(picker)
	_check(picker.configure(host, false, false).is_success, "picker must load default without user preferences")
	await process_frame
	_check(host.presentation_snapshot()["orientation"] == "horizontal", "wide host must use horizontal default")
	button.grab_focus()
	_check(picker.select_layout("layout.mirrored").is_success, "mirrored layout must apply")
	_check(habitat.get_parent().get_child(0) == habitat, "mirrored layout must reorder existing panel")
	_check(root.gui_get_focus_owner() == button, "layout switch must preserve keyboard focus")
	button.pressed.emit()
	_check(_clicks == 1, "existing button callback must survive reparenting")
	var container: Node = controls.get_parent()
	_check(picker.select_layout("layout.mirrored", 0.7).is_success, "bounded local weight override must apply")
	_check(controls.get_parent() == container, "weight edits must not recreate panel host")
	_check(is_equal_approx(habitat.size_flags_stretch_ratio, 0.7), "leading panel must receive override weight")
	var snapshot: Dictionary = host.presentation_snapshot()
	_check(not host.apply_layout(definitions["layout.default"], NAN).is_success, "invalid override must reject")
	_check(host.presentation_snapshot() == snapshot, "invalid override must preserve current layout")
	var custom: Dictionary = default_record.duplicate(true)
	custom["definition_id"] = "layout.custom-test"
	custom["display_name"] = "Custom test"
	custom["panel_ids"] = ["overlay.controls", "missing"]
	_check(picker.register_layout(custom).is_success, "well-shaped custom layout must register")
	_check(not picker.select_layout("layout.custom-test").is_success, "unknown registered widget reference must reject activation")
	_check(host.presentation_snapshot() == snapshot, "unknown widget activation must not move existing panels")
	_check(not picker.register_layout(custom).is_success, "duplicate custom layout must reject")
	host.size.x = 800
	await process_frame
	_check(host.presentation_snapshot()["orientation"] == "vertical", "narrow window must stack panels")
	host.size.x = 1280
	await process_frame
	_check(host.presentation_snapshot()["orientation"] == "horizontal", "wide window must restore requested orientation")
	_check(picker.select_layout("layout.stacked").is_success and host.presentation_snapshot()["orientation"] == "vertical", "explicit stacked preset must stay vertical")
	picker.select_layout(OverlayLayoutController.DEFAULT_ID)
	_check(is_equal_approx(host.presentation_snapshot()["leading_weight"], 0.44), "reset must restore default panel weight")
	_check(world.capture_world_snapshot_json().value == before, "layout changes must preserve world state")
	_check(not picker._valid_preference({"schema_version": 1, "layout_id": "removed", "leading_weight": 0.5}), "missing saved preset must reject")
	_check(not picker._valid_preference({"schema_version": 1, "layout_id": "layout.default", "leading_weight": 9.0}), "invalid saved weight must reject")
	_check(picker._valid_preference({"schema_version": 1, "layout_id": "layout.default", "leading_weight": 0.5}), "valid saved preference must validate")
	_check(not OverlayDocumentLoader.read_object(OverlayLayoutController.BUILTIN_PATHS[0], 10).is_success, "oversized local document must reject")
	picker.queue_free()
	host.queue_free()
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("Overlay layout and registered panel scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _on_click() -> void:
	_clicks += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
