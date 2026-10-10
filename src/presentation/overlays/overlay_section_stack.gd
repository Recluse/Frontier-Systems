extends VBoxContainer
class_name OverlaySectionStack

## Trusted existing controls grouped in a bounded, reorderable presentation stack.
signal customization_changed
const MAX_SECTIONS: int = 16
var _sections: Dictionary = {}
var _order: Array[String] = []


func register_section(section_id: String, title: String, content: Control, collapsible: bool = true) -> ServiceResult:
	if not ControlContractValidation.is_id(section_id) or not ControlContractValidation.is_id(title) or not is_instance_valid(content) or content == self or content.is_ancestor_of(self) or content.get_parent() != null or _sections.has(section_id) or _sections.size() >= MAX_SECTIONS:
		return ServiceResult.failure(&"invalid_overlay_section_registration", "Register a unique section with unparented content within capacity.")
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	wrapper.add_child(header)
	var toggle := Button.new()
	toggle.text = title
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.toggle_mode = true
	toggle.disabled = not collapsible
	toggle.tooltip_text = "Collapse or expand this section." if collapsible else "This status section stays expanded."
	toggle.toggled.connect(_on_toggle.bind(section_id))
	header.add_child(toggle)
	var up := Button.new()
	up.text = "Up"
	up.pressed.connect(move_section.bind(section_id, -1))
	header.add_child(up)
	var down := Button.new()
	down.text = "Down"
	down.pressed.connect(move_section.bind(section_id, 1))
	header.add_child(down)
	wrapper.add_child(content)
	_sections[section_id] = {"wrapper": wrapper, "content": content, "toggle": toggle, "up": up, "down": down, "collapsible": collapsible}
	_order.append(section_id)
	add_child(wrapper)
	_refresh_buttons()
	return ServiceResult.success()


func apply_profile(profile: OverlaySectionProfile) -> ServiceResult:
	if profile == null:
		return ServiceResult.failure(&"invalid_overlay_sections", "A validated profile is required.")
	var entries: Array = profile.to_record()["sections"]
	if entries.size() != _sections.size():
		return ServiceResult.failure(&"overlay_sections_incomplete", "The profile must include every registered section.")
	for entry in entries:
		if not _sections.has(entry["section_id"]):
			return ServiceResult.failure(&"unknown_overlay_section", "The profile references an unregistered section.")
		var section: Dictionary = _sections[entry["section_id"]]
		if not is_instance_valid(section["wrapper"]) or not is_instance_valid(section["content"]) or section["wrapper"].get_parent() != self or section["content"].get_parent() != section["wrapper"] or (entry["collapsed"] and not section["collapsible"]):
			return ServiceResult.failure(&"overlay_section_state_conflict", "A required section cannot collapse or its controls are unavailable.")
	_order.clear()
	for entry in entries:
		var id: String = entry["section_id"]
		_order.append(id)
		move_child(_sections[id]["wrapper"], _order.size() - 1)
		_set_collapsed(id, entry["collapsed"])
	_refresh_buttons()
	return ServiceResult.success()


func capture_profile(definition_id: String = "sections.user", display_name: String = "Saved customization") -> Dictionary:
	var entries: Array = []
	for id in _order:
		entries.append({"section_id": id, "collapsed": not _sections[id]["content"].visible})
	return {"schema_version": 1, "definition_id": definition_id, "display_name": display_name, "sections": entries}


func move_section(section_id: String, direction: int) -> ServiceResult:
	var index: int = _order.find(section_id)
	var destination: int = index + direction
	if index < 0 or direction not in [-1, 1] or destination < 0 or destination >= _order.size():
		return ServiceResult.failure(&"overlay_section_move_limit", "Move a registered section up or down within the stack.")
	var displaced: String = _order[destination]
	_order[destination] = section_id
	_order[index] = displaced
	move_child(_sections[section_id]["wrapper"], destination)
	_refresh_buttons()
	customization_changed.emit()
	return ServiceResult.success()


func set_collapsed(section_id: String, collapsed: bool) -> ServiceResult:
	if not _sections.has(section_id) or (collapsed and not _sections[section_id]["collapsible"]):
		return ServiceResult.failure(&"overlay_section_collapse_limit", "This section is unavailable or must remain expanded.")
	_set_collapsed(section_id, collapsed)
	customization_changed.emit()
	return ServiceResult.success()


func _set_collapsed(section_id: String, collapsed: bool) -> void:
	var section: Dictionary = _sections[section_id]
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if collapsed and is_instance_valid(focus) and (focus == section["content"] or section["content"].is_ancestor_of(focus)):
		section["toggle"].grab_focus()
	section["content"].visible = not collapsed
	section["toggle"].set_pressed_no_signal(collapsed)


func _on_toggle(collapsed: bool, section_id: String) -> void:
	set_collapsed(section_id, collapsed)


func _refresh_buttons() -> void:
	for index in range(_order.size()):
		var section: Dictionary = _sections[_order[index]]
		section["up"].disabled = index == 0
		section["down"].disabled = index == _order.size() - 1
