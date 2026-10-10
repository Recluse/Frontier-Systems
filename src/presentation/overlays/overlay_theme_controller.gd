extends HBoxContainer
class_name OverlayThemeController

## Local client appearance selector. Never references the world or command queue.
signal theme_selected(definition_id: String)
const DEFAULT_ID: String = "overlay.default"
const BUILTIN_PATHS: Array[String] = ["res://data/overlays/default.v1.json", "res://data/overlays/terminal.v1.json", "res://data/overlays/high-contrast.v1.json"]
const MOD_DIRECTORY: String = "user://overlay-themes"
const SETTINGS_PATH: String = "user://overlay-settings.cfg"
const MAX_THEME_BYTES: int = 16384
const MAX_CUSTOM_THEMES: int = 32
var _definitions: Dictionary = {}
var _target: Control
var _background: ColorRect
var _selector: OptionButton
var _persist_selection: bool = false
var _selected_id: String = ""


func configure(target: Control, background: ColorRect, load_local_mods: bool = true, persist_selection: bool = true) -> ServiceResult:
	if _target != null or target == null or background == null:
		return ServiceResult.failure(&"overlay_theme_configuration", "A theme target and background are required once.")
	for path in BUILTIN_PATHS:
		var loaded: ServiceResult = _read_theme(path)
		if not loaded.is_success:
			return loaded
		var registered: ServiceResult = register_theme(loaded.value)
		if not registered.is_success:
			return registered
	_target = target
	_background = background
	_persist_selection = persist_selection
	if load_local_mods:
		_load_mods()
	var label := Label.new()
	label.text = "Overlay theme"
	add_child(label)
	_selector = OptionButton.new()
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector.item_selected.connect(_on_selected)
	add_child(_selector)
	_refresh_choices()
	var reset := Button.new()
	reset.text = "Default"
	reset.pressed.connect(select_theme.bind(DEFAULT_ID))
	add_child(reset)
	var initial: String = DEFAULT_ID
	if persist_selection:
		var config := ConfigFile.new()
		var settings_file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if settings_file != null and settings_file.get_length() <= 4096 and config.load(SETTINGS_PATH) == OK:
			var saved: Variant = config.get_value("overlay", "theme_id", DEFAULT_ID)
			if typeof(saved) == TYPE_STRING and _definitions.has(saved):
				initial = saved
	return select_theme(initial)


## Accepts JSON-compatible data only; duplicate IDs cannot shadow shipped themes.
func register_theme(record: Dictionary) -> ServiceResult:
	if _definitions.size() >= BUILTIN_PATHS.size() + MAX_CUSTOM_THEMES:
		return ServiceResult.failure(&"overlay_theme_limit", "The theme catalog is full.")
	var parsed: ServiceResult = OverlayThemeDefinition.from_record(record)
	if not parsed.is_success:
		return parsed
	var definition: OverlayThemeDefinition = parsed.value
	var definition_id: String = definition.to_record()["definition_id"]
	if _definitions.has(definition_id):
		return ServiceResult.failure(&"overlay_theme_conflict", "A theme with that ID already exists.")
	_definitions[definition_id] = definition
	if _selector != null:
		_refresh_choices()
	return ServiceResult.success()


func select_theme(definition_id: String) -> ServiceResult:
	if not is_instance_valid(_target) or not is_instance_valid(_background) or not _definitions.has(definition_id):
		return ServiceResult.failure(&"unknown_overlay_theme", "A configured target and registered theme are required.")
	var definition: OverlayThemeDefinition = _definitions[definition_id]
	_target.theme = definition.build_theme()
	_background.color = definition.background_color()
	_selected_id = definition_id
	_refresh_choices()
	if _persist_selection:
		var config := ConfigFile.new()
		config.set_value("overlay", "theme_id", definition_id)
		if config.save(SETTINGS_PATH) != OK:
			push_warning("Overlay theme applied, but the local preference could not be saved.")
	theme_selected.emit(definition_id)
	return ServiceResult.success()


func selected_theme_id() -> String:
	return _selected_id


func _on_selected(index: int) -> void:
	select_theme(String(_selector.get_item_metadata(index)))


func _refresh_choices() -> void:
	if _selector == null:
		return
	_selector.clear()
	for definition_id in _definitions:
		var definition: OverlayThemeDefinition = _definitions[definition_id]
		_selector.add_item(definition.to_record()["display_name"])
		var index: int = _selector.item_count - 1
		_selector.set_item_metadata(index, definition_id)
		if definition_id == _selected_id:
			_selector.select(index)


func _load_mods() -> void:
	for record in OverlayDocumentLoader.load_directory(MOD_DIRECTORY, MAX_CUSTOM_THEMES, MAX_THEME_BYTES):
		var registered: ServiceResult = register_theme(record)
		if not registered.is_success:
			push_warning("An overlay mod was skipped: %s" % registered.error_code)


func _read_theme(path: String) -> ServiceResult:
	return OverlayDocumentLoader.read_object(path, MAX_THEME_BYTES)
