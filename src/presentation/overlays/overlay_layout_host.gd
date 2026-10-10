extends Control
class_name OverlayLayoutHost

## Reusable panel host; layout switches preserve the existing controls and callbacks.
const NARROW_WIDTH: float = 1000.0
var _registry: OverlayPanelRegistry
var _definition: OverlayLayoutDefinition
var _container: BoxContainer
var _weight: float = 0.5
var _effective_orientation: String = ""
var _minimum_refresh_pending: bool = false


func configure(registry: OverlayPanelRegistry) -> ServiceResult:
	if _registry != null or registry == null:
		return ServiceResult.failure(&"overlay_layout_configuration", "Configure the host with one trusted registry.")
	_registry = registry
	resized.connect(_on_resized)
	return ServiceResult.success()


func apply_layout(definition: OverlayLayoutDefinition, leading_weight: float = -1.0) -> ServiceResult:
	if _registry == null:
		return ServiceResult.failure(&"overlay_layout_configuration", "The layout host is not configured.")
	var resolved: ServiceResult = _registry.resolve_layout(definition)
	if not resolved.is_success:
		return resolved
	var record: Dictionary = definition.to_record()
	var weight: float = float(record["leading_weight"]) if leading_weight == -1.0 else leading_weight
	if not is_finite(weight) or weight < 0.25 or weight > 0.75:
		return ServiceResult.failure(&"invalid_overlay_layout_weight", "Panel weight must be between 0.25 and 0.75.")
	for panel in resolved.value:
		if panel == self or panel.is_ancestor_of(self) or (panel.get_parent() != null and panel.get_parent() != _container):
			return ServiceResult.failure(&"overlay_panel_parent_conflict", "A panel belongs to a different host or is an ancestor.")
	for panel in resolved.value:
		if not panel.minimum_size_changed.is_connected(_on_panel_minimum_changed):
			panel.minimum_size_changed.connect(_on_panel_minimum_changed)
	_definition = definition
	_weight = weight
	_rebuild(resolved.value)
	return ServiceResult.success()


func presentation_snapshot() -> Dictionary:
	return {"definition_id": "" if _definition == null else _definition.to_record()["definition_id"],
		"orientation": _effective_orientation, "leading_weight": _weight,
		"panel_ids": [] if _definition == null else _definition.to_record()["panel_ids"]}


func _on_resized() -> void:
	if _definition == null:
		return
	if _orientation() != _effective_orientation:
		var resolved: ServiceResult = _registry.resolve_layout(_definition)
		if resolved.is_success:
			_rebuild(resolved.value)


func _on_panel_minimum_changed() -> void:
	if _minimum_refresh_pending:
		return
	_minimum_refresh_pending = true
	call_deferred("_refresh_after_minimum_change")


func _refresh_after_minimum_change() -> void:
	_minimum_refresh_pending = false
	_on_resized()


func _orientation() -> String:
	var requested: String = _definition.to_record()["orientation"]
	var minimum_width: float = NARROW_WIDTH
	var resolved: ServiceResult = _registry.resolve_layout(_definition)
	if resolved.is_success:
		var panel_width: float = float(_definition.to_record()["spacing"])
		for panel in resolved.value:
			panel_width += panel.get_combined_minimum_size().x
		minimum_width = maxf(minimum_width, panel_width)
	return "vertical" if requested == "horizontal" and size.x < minimum_width else requested


func _rebuild(panels: Array) -> void:
	var orientation: String = _orientation()
	if _container != null and _effective_orientation == orientation and _container.get_child_count() == panels.size() and _container.get_child(0) == panels[0] and _container.get_child(1) == panels[1]:
		_container.add_theme_constant_override("separation", int(_definition.to_record()["spacing"]))
		panels[0].size_flags_stretch_ratio = _weight
		panels[1].size_flags_stretch_ratio = 1.0 - _weight
		return
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for panel in panels:
		if panel.get_parent() == _container and _container != null:
			_container.remove_child(panel)
	if _container != null:
		remove_child(_container)
		_container.queue_free()
	_effective_orientation = orientation
	_container = HBoxContainer.new() if _effective_orientation == "horizontal" else VBoxContainer.new()
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.add_theme_constant_override("separation", int(_definition.to_record()["spacing"]))
	add_child(_container)
	for index in range(panels.size()):
		var panel: Control = panels[index]
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = _weight if index == 0 else 1.0 - _weight
		_container.add_child(panel)
	if is_instance_valid(focus) and focus.is_inside_tree() and is_ancestor_of(focus):
		focus.grab_focus()
