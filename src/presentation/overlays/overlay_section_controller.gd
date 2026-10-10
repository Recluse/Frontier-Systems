extends VBoxContainer
class_name OverlaySectionController

## Local profile picker with independent saved reorder/collapse state.
const DEFAULT_ID: String = "sections.default"
const BUILTIN_PATHS: Array[String] = ["res://data/overlays/sections/default.v1.json", "res://data/overlays/sections/compact.v1.json"]
const MOD_DIRECTORY: String = "user://overlay-sections"
const SETTINGS_PATH: String = "user://overlay-section-settings.json"
var _stack: OverlaySectionStack
var _profiles: Dictionary = {}
var _selector: OptionButton
var _status: Label
var _persist: bool = false
var _selected_id: String = ""
var _settings_path: String = SETTINGS_PATH


func configure(stack: OverlaySectionStack, load_local_mods: bool = true, persist_selection: bool = true, preference_path: String = SETTINGS_PATH) -> ServiceResult:
	if _stack != null or not is_instance_valid(stack) or not preference_path.begins_with("user://") or preference_path.length() > 256:
		return ServiceResult.failure(&"overlay_section_configuration", "Configure with one live section stack.")
	_settings_path = preference_path
	for path in BUILTIN_PATHS:
		var loaded: ServiceResult = OverlayDocumentLoader.read_object(path, 16384)
		if not loaded.is_success:
			return loaded
		var registered: ServiceResult = register_profile(loaded.value)
		if not registered.is_success:
			return registered
	_stack = stack
	_persist = persist_selection
	if load_local_mods:
		for record in OverlayDocumentLoader.load_directory(MOD_DIRECTORY, 32, 16384):
			var registered: ServiceResult = register_profile(record)
			if not registered.is_success:
				push_warning("An overlay section profile was skipped: %s" % registered.error_code)
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = "HUD sections"
	row.add_child(label)
	_selector = OptionButton.new()
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector.item_selected.connect(_on_selected)
	row.add_child(_selector)
	var reset := Button.new()
	reset.text = "Reset sections"
	reset.pressed.connect(select_profile.bind(DEFAULT_ID))
	row.add_child(reset)
	_status = Label.new()
	add_child(_status)
	_refresh_choices()
	var applied: ServiceResult = select_profile(DEFAULT_ID)
	if not applied.is_success:
		return applied
	# Default application must not overwrite saved custom state before reading it.
	_stack.customization_changed.connect(_on_customized)
	restore_local_preference()
	return ServiceResult.success()


func restore_local_preference() -> void:
	if not _persist:
		return
	var saved: ServiceResult = OverlayDocumentLoader.read_object(_settings_path, 16384)
	if saved.is_success:
		var parsed: ServiceResult = OverlaySectionProfile.from_record(_migrate_inventory_section(saved.value))
		if parsed.is_success and _stack.apply_profile(parsed.value).is_success:
			_selected_id = ""
			_selector.select(-1)
			_status.text = "Restored custom sections"


func register_profile(record: Dictionary) -> ServiceResult:
	if _profiles.size() >= 34:
		return ServiceResult.failure(&"overlay_section_profile_limit", "The section profile catalog is full.")
	var parsed: ServiceResult = OverlaySectionProfile.from_record(_migrate_inventory_section(record))
	if not parsed.is_success:
		return parsed
	var id: String = record["definition_id"]
	if _profiles.has(id):
		return ServiceResult.failure(&"overlay_section_profile_conflict", "The section profile ID already exists.")
	_profiles[id] = parsed.value
	_refresh_choices()
	return ServiceResult.success()


## One additive first-party migration; unknown/otherwise incomplete profiles still reject.
func _migrate_inventory_section(record: Dictionary) -> Dictionary:
	if _stack == null or not OverlaySectionProfile.from_record(record).is_success:
		return record
	var current: Array = _stack.capture_profile()["sections"]
	var existing: Dictionary = {}
	for entry in record["sections"]:
		existing[entry["section_id"]] = true
	var missing: Array[String] = []
	for entry in current:
		if not existing.has(entry["section_id"]):
			missing.append(entry["section_id"])
	if missing == ["hud.inventory"] and record["sections"].size() == current.size() - 1:
		var migrated: Dictionary = record.duplicate(true)
		migrated["sections"].append({"section_id": "hud.inventory", "collapsed": false})
		return migrated
	return record


func select_profile(definition_id: String) -> ServiceResult:
	if not is_instance_valid(_stack) or not _profiles.has(definition_id):
		return ServiceResult.failure(&"unknown_overlay_section_profile", "A live stack and registered profile are required.")
	var result: ServiceResult = _stack.apply_profile(_profiles[definition_id])
	if not result.is_success:
		return result
	_selected_id = definition_id
	for index in range(_selector.item_count):
		if _selector.get_item_metadata(index) == definition_id:
			_selector.select(index)
	_status.text = _profiles[definition_id].to_record()["display_name"]
	if _stack.customization_changed.is_connected(_on_customized):
		_save()
	return ServiceResult.success()


func _on_selected(index: int) -> void:
	var result: ServiceResult = select_profile(String(_selector.get_item_metadata(index)))
	if not result.is_success:
		_refresh_choices()
		_status.text = "Profile unavailable; current sections preserved"


func _on_customized() -> void:
	_selected_id = ""
	_selector.select(-1)
	_status.text = "Custom sections"
	_save()


func _refresh_choices() -> void:
	if _selector == null:
		return
	_selector.clear()
	for id in _profiles:
		_selector.add_item(_profiles[id].to_record()["display_name"])
		_selector.set_item_metadata(_selector.item_count - 1, id)
		if id == _selected_id:
			_selector.select(_selector.item_count - 1)
	if _selected_id.is_empty():
		_selector.select(-1)


func _save() -> void:
	if not _persist:
		return
	var file := FileAccess.open(_settings_path, FileAccess.WRITE)
	if file == null:
		push_warning("HUD sections changed, but the local preference could not be saved.")
		return
	file.store_string(JSON.stringify(_stack.capture_profile()))
