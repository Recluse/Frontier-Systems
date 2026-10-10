extends VBoxContainer
class_name OverlayLayoutController

## Local layout picker and per-selection panel space override.
const DEFAULT_ID: String = "layout.default"
const BUILTIN_PATHS: Array[String] = ["res://data/overlays/layouts/default.v1.json", "res://data/overlays/layouts/mirrored.v1.json", "res://data/overlays/layouts/stacked.v1.json"]
const MOD_DIRECTORY: String = "user://overlay-layouts"
const SETTINGS_PATH: String = "user://overlay-layout-settings.json"
const MAX_DOCUMENT_BYTES: int = 16384
const MAX_CUSTOM_LAYOUTS: int = 32
var _host: OverlayLayoutHost
var _definitions: Dictionary = {}
var _selector: OptionButton
var _weight_slider: HSlider
var _weight_label: Label
var _selected_id: String = ""
var _persist: bool = false
var _dragging: bool = false


func configure(host: OverlayLayoutHost, load_local_mods: bool = true, persist_selection: bool = true) -> ServiceResult:
	if _host != null or not is_instance_valid(host):
		return ServiceResult.failure(&"overlay_layout_configuration", "Configure the picker with one live host.")
	for path in BUILTIN_PATHS:
		var loaded: ServiceResult = OverlayDocumentLoader.read_object(path, MAX_DOCUMENT_BYTES)
		if not loaded.is_success:
			return loaded
		var registered: ServiceResult = register_layout(loaded.value)
		if not registered.is_success:
			return registered
	_host = host
	_persist = persist_selection
	if load_local_mods:
		for record in OverlayDocumentLoader.load_directory(MOD_DIRECTORY, MAX_CUSTOM_LAYOUTS, MAX_DOCUMENT_BYTES):
			var registered: ServiceResult = register_layout(record)
			if not registered.is_success:
				push_warning("An overlay layout was skipped: %s" % registered.error_code)
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = "Overlay layout"
	row.add_child(label)
	_selector = OptionButton.new()
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector.item_selected.connect(_on_selected)
	row.add_child(_selector)
	var reset := Button.new()
	reset.text = "Reset layout"
	reset.pressed.connect(select_layout.bind(DEFAULT_ID))
	row.add_child(reset)
	_weight_label = Label.new()
	add_child(_weight_label)
	_weight_slider = HSlider.new()
	_weight_slider.min_value = 25
	_weight_slider.max_value = 75
	_weight_slider.step = 1
	_weight_slider.value_changed.connect(_on_weight_changed)
	_weight_slider.drag_started.connect(_on_drag_started)
	_weight_slider.drag_ended.connect(_on_drag_ended)
	_weight_slider.tooltip_text = "Relative share of space for the leading panel, subject to each panel's minimum size."
	add_child(_weight_slider)
	var initial: String = DEFAULT_ID
	var initial_weight: float = -1.0
	if _persist:
		var saved: ServiceResult = OverlayDocumentLoader.read_object(SETTINGS_PATH, 4096)
		if saved.is_success and _valid_preference(saved.value):
			initial = saved.value["layout_id"]
			initial_weight = float(saved.value["leading_weight"])
	var applied: ServiceResult = select_layout(initial, initial_weight)
	if not applied.is_success and initial != DEFAULT_ID:
		return select_layout(DEFAULT_ID)
	return applied


func register_layout(record: Dictionary) -> ServiceResult:
	if _definitions.size() >= BUILTIN_PATHS.size() + MAX_CUSTOM_LAYOUTS:
		return ServiceResult.failure(&"overlay_layout_limit", "The layout catalog is full.")
	var parsed: ServiceResult = OverlayLayoutDefinition.from_record(record)
	if not parsed.is_success:
		return parsed
	var definition: OverlayLayoutDefinition = parsed.value
	var definition_id: String = definition.to_record()["definition_id"]
	if _definitions.has(definition_id):
		return ServiceResult.failure(&"overlay_layout_conflict", "This layout ID is already registered.")
	_definitions[definition_id] = definition
	_refresh_choices()
	return ServiceResult.success()


func select_layout(definition_id: String, leading_weight: float = -1.0) -> ServiceResult:
	if not is_instance_valid(_host) or not _definitions.has(definition_id):
		return ServiceResult.failure(&"unknown_overlay_layout", "A live host and registered layout are required.")
	var result: ServiceResult = _host.apply_layout(_definitions[definition_id], leading_weight)
	if not result.is_success:
		_refresh_choices()
		return result
	_selected_id = definition_id
	_refresh_choices()
	var weight: float = _host.presentation_snapshot()["leading_weight"]
	_weight_slider.set_value_no_signal(weight * 100.0)
	_weight_label.text = "Leading panel space weight: %d%%" % roundi(weight * 100.0)
	_save_preference()
	return ServiceResult.success()


func _on_selected(index: int) -> void:
	select_layout(String(_selector.get_item_metadata(index)))


func _on_weight_changed(value: float) -> void:
	if _selected_id.is_empty():
		return
	var result: ServiceResult = _host.apply_layout(_definitions[_selected_id], value / 100.0)
	if result.is_success:
		_weight_label.text = "Leading panel space weight: %d%%" % roundi(value)
	# Pointer drags write once on release; keyboard changes save immediately.
	if not _dragging:
		_save_preference()


func _on_drag_started() -> void:
	_dragging = true


func _on_drag_ended(_changed: bool) -> void:
	_dragging = false
	_save_preference()


func _refresh_choices() -> void:
	if _selector == null:
		return
	_selector.clear()
	for definition_id in _definitions:
		_selector.add_item(_definitions[definition_id].to_record()["display_name"])
		var index: int = _selector.item_count - 1
		_selector.set_item_metadata(index, definition_id)
		if definition_id == _selected_id:
			_selector.select(index)


func _valid_preference(record: Dictionary) -> bool:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "layout_id", "leading_weight"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1):
		return false
	var weight: Variant = record["leading_weight"]
	return typeof(record["layout_id"]) == TYPE_STRING and _definitions.has(record["layout_id"]) and (typeof(weight) == TYPE_FLOAT or typeof(weight) == TYPE_INT) and is_finite(float(weight)) and float(weight) >= 0.25 and float(weight) <= 0.75


func _save_preference() -> void:
	if not _persist or _selected_id.is_empty():
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Overlay layout applied, but its local preference could not be saved.")
		return
	file.store_string(JSON.stringify({"schema_version": 1, "layout_id": _selected_id, "leading_weight": _host.presentation_snapshot()["leading_weight"]}))
