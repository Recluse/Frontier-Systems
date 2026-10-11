extends VBoxContainer
class_name FirstPlayableControlsHelp

## Local navigation and binding descriptions only: no world observations or commands.
var _tabs: TabContainer
var _selector := OptionButton.new()
var _toggle := Button.new()
var _summary := Label.new()
var _details := ScrollContainer.new()
var _body := VBoxContainer.new()
var _text := Label.new()
var _close := Button.new()


func configure(tabs: TabContainer) -> void:
	_tabs = tabs
	_selector.clear()
	for index in range(tabs.get_tab_count()):
		_selector.add_item(tabs.get_tab_title(index), index)
	_selector.select(tabs.current_tab)
	tabs.tab_changed.connect(func(index: int) -> void: _selector.select(index))
	tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var navigation := HBoxContainer.new()
	add_child(navigation)
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector.clip_text = true
	_selector.tooltip_text = "Choose a panel. Use UI confirm and arrows when focused."
	navigation.add_child(_selector)
	_selector.item_selected.connect(func(index: int) -> void:
		PlayerInputSettings.instance().release_all()
		_tabs.current_tab = _selector.get_item_id(index)
	)
	_toggle.text = "Controls help"
	_toggle.toggle_mode = true
	navigation.add_child(_toggle)
	_toggle.toggled.connect(_show_help)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_summary)
	_details.custom_minimum_size.y = 180
	_details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details.follow_focus = true
	_details.focus_mode = Control.FOCUS_ALL
	_details.gui_input.connect(func(event: InputEvent) -> void:
		if PlayerInputSettings.instance().rebinding or not event is InputEventKey:
			return
		if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
			_details.scroll_vertical += 48 if event.is_action_pressed("ui_down") else -48
			_details.accept_event()
	)
	add_child(_details)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_child(_body)
	_close.text = "Close help"
	_close.pressed.connect(func() -> void: _toggle.button_pressed = false)
	_body.add_child(_close)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_text)
	_details.hide()
	PlayerInputSettings.instance().bindings_changed.connect(_refresh)
	_refresh()


func _show_help(open: bool) -> void:
	_details.visible = open
	if open:
		PlayerInputSettings.instance().release_all()
		_close.grab_focus()
	else:
		_toggle.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if not _details.visible or PlayerInputSettings.instance().rebinding or focus == null or not is_ancestor_of(focus):
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_toggle.button_pressed = false
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var controls := PlayerInputSettings.instance()
	_summary.text = "Hold %s: look / move · hold %s: UI cursor · %s: inventory · %s: settings" % [controls.binding_label("look"), controls.binding_label("ui_cursor"), controls.binding_label("inventory"), controls.binding_label("settings")]
	_text.text = "\n".join(PackedStringArray([
		"Look and move: hold %s to capture the camera. Move with %s / %s / %s / %s; %s jumps, %s sprints. Overview uses %s / %s to zoom." % [controls.binding_label("look"), controls.binding_label("move_forward"), controls.binding_label("move_back"), controls.binding_label("move_left"), controls.binding_label("move_right"), controls.binding_label("jump"), controls.binding_label("sprint"), controls.binding_label("zoom_in"), controls.binding_label("zoom_out")],
		"Hold %s to expose the UI cursor and pause movement/look. Releasing it resumes capture only while look stays held. %s releases capture; window focus loss also releases it." % [controls.binding_label("ui_cursor"), controls.binding_label("release_cursor")],
		"World interaction: %s selects. Click a station to open Workstation. With a mouse, double-click deposits/items to use or collect; selecting a machine or wall opens Construction. A keyboard/controller selection activates the pointed object. The host checks reach and permissions." % controls.binding_label("world_select"),
		"Inventory: %s toggles the Inventory tab. %s switches active hand; %s uses the active tool. Inventory buttons manage observed items." % [controls.binding_label("inventory"), controls.binding_label("switch_hand"), controls.binding_label("use_tool")],
		"Guide shows the current finite engineering loop and prerequisites; it does not perform actions or remember completed steps. Construction provides machine and wall controls; select a world machine/wall to inspect it.",
		"Choose any existing panel with the selector above. Focus controls with %s / %s; confirm with %s and navigate choices with %s / %s. Focus the help scroll area and use %s / %s to scroll. Close focused help with %s or Close help. No extra gameplay shortcuts are added." % [controls.binding_label("ui_focus_next"), controls.binding_label("ui_focus_prev"), controls.binding_label("ui_accept"), controls.binding_label("ui_left"), controls.binding_label("ui_right"), controls.binding_label("ui_up"), controls.binding_label("ui_down"), controls.binding_label("ui_cancel")],
		"Settings (%s) edits local bindings and sensitivity. It pauses navigation while visible. Camera shortcuts: %s first person, %s third person, %s overview." % [controls.binding_label("settings"), controls.binding_label("camera_first"), controls.binding_label("camera_third"), controls.binding_label("camera_overview")]
	]))
