extends SceneTree

var _failures: int = 0
var _clicks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: ServiceResult = OverlayDocumentLoader.read_object(OverlaySectionController.BUILTIN_PATHS[0], 16384)
	_check(loaded.is_success, "default section profile must load")
	var record: Dictionary = loaded.value
	var invalid: Dictionary = record.duplicate(true)
	invalid["sections"][1]["section_id"] = "hud.status"
	_check(not OverlaySectionProfile.from_record(invalid).is_success, "duplicate section IDs must reject")
	invalid = record.duplicate(true)
	invalid["sections"][1]["collapsed"] = 1
	_check(not OverlaySectionProfile.from_record(invalid).is_success, "nonboolean collapse flags must reject")
	invalid = record.duplicate(true)
	invalid["script"] = "res://untrusted.gd"
	_check(not OverlaySectionProfile.from_record(invalid).is_success, "executable fields must reject")
	var world := WorldRuntime.new()
	root.add_child(world)
	var world_before: String = world.capture_world_snapshot_json().value
	var stack := OverlaySectionStack.new()
	root.add_child(stack)
	stack.size = Vector2(600, 800)
	var contents: Dictionary = {}
	for entry in record["sections"]:
		var id: String = entry["section_id"]
		var content := VBoxContainer.new()
		var button := Button.new()
		button.text = id
		button.pressed.connect(_on_click)
		content.add_child(button)
		contents[id] = content
		_check(stack.register_section(id, id, content, id not in ["hud.status", "hud.feedback"]).is_success, "trusted HUD content must register")
	var picker := OverlaySectionController.new()
	root.add_child(picker)
	_check(picker.configure(stack, false, false).is_success, "section selector must configure from shipped profiles")
	_check(stack.capture_profile()["sections"] == record["sections"], "default profile must preserve order and expansion")
	_check(picker.select_profile("sections.compact").is_success, "compact preset must apply")
	_check(not contents["hud.profiling"].visible and contents["hud.status"].visible, "compact preset must collapse diagnostics but preserve status")
	var before: Dictionary = stack.capture_profile()
	invalid = record.duplicate(true)
	invalid["sections"][0]["collapsed"] = true
	var required: OverlaySectionProfile = OverlaySectionProfile.from_record(invalid).value
	_check(not stack.apply_profile(required).is_success and stack.capture_profile() == before, "required collapse must reject atomically")
	invalid = record.duplicate(true)
	invalid["sections"][5]["section_id"] = "unknown"
	_check(not stack.apply_profile(OverlaySectionProfile.from_record(invalid).value).is_success and stack.capture_profile() == before, "unknown section must not partially reorder earlier entries")
	_check(not stack.set_collapsed("hud.status", true).is_success, "direct required collapse must reject")
	picker.select_profile(OverlaySectionController.DEFAULT_ID)
	var airlock_button: Button = contents["hud.airlock"].get_child(0)
	airlock_button.grab_focus()
	_check(stack.move_section("hud.airlock", 1).is_success, "section must move down")
	_check(root.gui_get_focus_owner() == airlock_button, "reordering must preserve keyboard focus")
	airlock_button.pressed.emit()
	_check(_clicks == 1, "reordering must preserve command callback")
	_check(stack.set_collapsed("hud.airlock", true).is_success, "optional section must collapse")
	_check(root.gui_get_focus_owner() != airlock_button and root.gui_get_focus_owner() != null, "collapsing focused content must move focus to header")
	_check(not contents["hud.airlock"].visible, "collapse must hide existing content")
	_check(stack.set_collapsed("hud.airlock", false).is_success, "optional section must expand")
	_check(contents["hud.airlock"].visible, "expand must restore existing content")
	var saved: Dictionary = stack.capture_profile()
	var parsed_saved: ServiceResult = OverlaySectionProfile.from_record(JSON.parse_string(JSON.stringify(saved)))
	_check(parsed_saved.is_success, "customized state must round-trip through JSON")
	picker.select_profile(OverlaySectionController.DEFAULT_ID)
	_check(stack.apply_profile(parsed_saved.value).is_success and stack.capture_profile() == saved, "saved order and collapse flags must restore")
	before = stack.capture_profile()
	_check(not stack.move_section("missing", 1).is_success and stack.capture_profile() == before, "unknown section moves must reject")
	_check(not stack.move_section("hud.status", -1).is_success, "first section must not move outside stack")
	_check(not stack.move_section("hud.airlock", 2).is_success, "move steps must be bounded")
	var custom: Dictionary = record.duplicate(true)
	custom["definition_id"] = "sections.custom-test"
	custom["display_name"] = "Custom test"
	_check(picker.register_profile(custom).is_success and picker.select_profile("sections.custom-test").is_success, "custom declarative profile must select")
	_check(not picker.register_profile(custom).is_success, "duplicate profile must reject")
	_check(not picker.select_profile("removed").is_success, "missing profile must reject")
	var legacy_profile: Dictionary = record.duplicate(true)
	legacy_profile["definition_id"] = "sections.legacy-test"
	var legacy_entries: Array = []
	for entry in legacy_profile["sections"]:
		if entry["section_id"] != "hud.inventory":
			legacy_entries.push_front(entry)
	legacy_profile["sections"] = legacy_entries
	_check(picker.register_profile(legacy_profile).is_success and picker.select_profile("sections.legacy-test").is_success, "six-section mod must migrate the additive inventory section")
	var migrated: Array = stack.capture_profile()["sections"]
	_check(migrated[migrated.size() - 1]["section_id"] == "hud.inventory" and migrated[0]["section_id"] == legacy_entries[0]["section_id"], "migration must append inventory while preserving existing order")
	var test_path: String = "user://overlay-section-test-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	_check(file != null, "isolated preference fixture must open")
	if file != null:
		file.store_string(JSON.stringify(saved))
		file.close()
		var disk_stack: OverlaySectionStack = _registered_stack(record)
		var disk_picker := OverlaySectionController.new()
		root.add_child(disk_picker)
		_check(disk_picker.configure(disk_stack, false, true, test_path).is_success, "isolated disk preference must configure")
		_check(disk_stack.capture_profile() == saved, "startup must restore saved order before overwriting preferences")
		_check(disk_stack.set_collapsed("hud.profiling", true).is_success, "disk-backed local edit must apply")
		var disk_saved: ServiceResult = OverlayDocumentLoader.read_object(test_path, 16384)
		_check(disk_saved.is_success and disk_saved.value["sections"] == disk_stack.capture_profile()["sections"] and disk_saved.value["definition_id"] == "sections.user", "local edits must persist actual section state")
		disk_picker.select_profile(OverlaySectionController.DEFAULT_ID)
		disk_saved = OverlayDocumentLoader.read_object(test_path, 16384)
		_check(disk_saved.value["sections"] == record["sections"], "reset must persist default order and expansion")
		file = FileAccess.open(test_path, FileAccess.WRITE)
		invalid = record.duplicate(true)
		invalid["sections"][0]["collapsed"] = true
		file.store_string(JSON.stringify(invalid))
		file.close()
		var recovery_stack: OverlaySectionStack = _registered_stack(record)
		var recovery_picker := OverlaySectionController.new()
		root.add_child(recovery_picker)
		_check(recovery_picker.configure(recovery_stack, false, true, test_path).is_success, "invalid saved profile must retain default successfully")
		_check(recovery_stack.capture_profile()["sections"] == record["sections"], "invalid saved required collapse must leave defaults intact")
		disk_picker.queue_free()
		disk_stack.queue_free()
		recovery_picker.queue_free()
		recovery_stack.queue_free()
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path)) == OK, "isolated preference fixture must clean up")
	_check(world.capture_world_snapshot_json().value == world_before, "HUD customization must not mutate world state")
	picker.queue_free()
	stack.queue_free()
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("HUD section customization and isolation scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _registered_stack(record: Dictionary) -> OverlaySectionStack:
	var stack := OverlaySectionStack.new()
	root.add_child(stack)
	for entry in record["sections"]:
		var label := Label.new()
		label.text = entry["section_id"]
		_check(stack.register_section(entry["section_id"], entry["section_id"], label, entry["section_id"] not in ["hud.status", "hud.feedback"]).is_success, "recovery fixture section must register")
	return stack


func _on_click() -> void:
	_clicks += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
