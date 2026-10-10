extends Node
class_name FrontierBootstrap

## Starts the shared world runtime in either client or headless-server mode.
## Hosting providers, networking, persistence, and Steam initialization are explicit later steps.

enum RuntimeMode {
	CLIENT,
	HEADLESS_SERVER,
}

var runtime_mode: RuntimeMode = RuntimeMode.CLIENT
var _world_runtime: WorldRuntime
var _pressure_status_label: Label
var _last_action_label: Label
var _control_status_label: Label
var _profiling_status_label: Label
var _profiling_report_label: Label
var _alarm_indicator: AlarmStatusIndicator
var _habitat_preview: ProceduralHabitatPreview
var _overlay_layout_host: OverlayLayoutHost
var _overlay_section_stack: OverlaySectionStack
var _inventory_panel: LocalInventoryPanel
var _inventory_observation_elapsed: float = 0.0
var _inventory_body_adapter: LocalInventoryBodyAdapter
var _xr_client: OptionalXRClient
var _xr_startup_status: String = ""


func _ready() -> void:
	runtime_mode = _resolve_runtime_mode()
	_start_world_runtime()
	if runtime_mode == RuntimeMode.CLIENT:
		var started_xr: bool = false
		if OptionalXRLaunchPolicy.requested(OS.get_cmdline_args(), OS.get_cmdline_user_args(), false):
			_xr_client = OptionalXRClient.new()
			add_child(_xr_client)
			var xr_result: ServiceResult = _xr_client.try_start(_world_runtime)
			started_xr = xr_result.is_success
			if not started_xr:
				_xr_startup_status = "VR unavailable; desktop fallback. " + xr_result.message
				push_warning(_xr_startup_status)
				_xr_client.queue_free()
				_xr_client = null
		if not started_xr:
			_create_client_status_view()

	var mode_label: String = "headless world host" if runtime_mode == RuntimeMode.HEADLESS_SERVER else "client"
	print("Frontier Systems started in %s mode. Networking and persistence are not configured yet." % mode_label)


func _resolve_runtime_mode() -> RuntimeMode:
	if OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless":
		return RuntimeMode.HEADLESS_SERVER
	return RuntimeMode.CLIENT


func _start_world_runtime() -> void:
	_world_runtime = WorldRuntime.new()
	_world_runtime.name = "WorldRuntime"
	_world_runtime.command_completed.connect(_on_command_completed)
	add_child(_world_runtime)
	var start_result: ServiceResult = _world_runtime.start_simulation()
	if not start_result.is_success:
		push_error("World simulation failed to start: %s" % start_result.message)


func _create_client_status_view() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "BootstrapStatusView"
	add_child(canvas)

	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(screen)

	var background := ColorRect.new()
	background.color = Color("#111820")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(background)
	_overlay_layout_host = OverlayLayoutHost.new()
	_overlay_layout_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_layout_host.offset_left = 16.0
	_overlay_layout_host.offset_top = 16.0
	_overlay_layout_host.offset_right = -16.0
	_overlay_layout_host.offset_bottom = -16.0
	screen.add_child(_overlay_layout_host)
	var view_column := VBoxContainer.new()
	var view_help := Label.new()
	view_help.text = "Right-drag to look; overview wheel to zoom. Walk: WASD, Shift, Space. Free look also uses Q/E. Escape releases mouse."
	if not _xr_startup_status.is_empty():
		view_help.text = _xr_startup_status + "\n" + view_help.text
	view_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view_column.add_child(view_help)
	var camera_actions := HBoxContainer.new()
	view_column.add_child(camera_actions)
	for view_mode in [HabitatInspectionCamera.Mode.OVERVIEW, HabitatInspectionCamera.Mode.FREE_LOOK]:
		var view_button := Button.new()
		view_button.text = "Overview" if view_mode == HabitatInspectionCamera.Mode.OVERVIEW else "Interior free look"
		view_button.pressed.connect(_set_preview_camera_mode.bind(view_mode))
		camera_actions.add_child(view_button)
	for character_mode in [LocalHabitatCharacter.CameraMode.FIRST_PERSON, LocalHabitatCharacter.CameraMode.THIRD_PERSON]:
		var body_button := Button.new()
		body_button.text = "First person" if character_mode == LocalHabitatCharacter.CameraMode.FIRST_PERSON else "Third person"
		body_button.pressed.connect(_set_character_camera_mode.bind(character_mode))
		camera_actions.add_child(body_button)
	var view_container := SubViewportContainer.new()
	view_container.custom_minimum_size.y = 240.0
	view_container.stretch = true
	view_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_column.add_child(view_container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.size = Vector2i(640, 640)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view_container.add_child(viewport)
	_habitat_preview = ProceduralHabitatPreview.new()
	viewport.add_child(_habitat_preview)

	var panel := PanelContainer.new()

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var theme_controller := OverlayThemeController.new()
	content.add_child(theme_controller)
	var theme_result: ServiceResult = theme_controller.configure(screen, background)
	if not theme_result.is_success:
		push_warning("Overlay theme setup failed: %s" % theme_result.error_code)
	var layout_controller := OverlayLayoutController.new()
	content.add_child(layout_controller)
	var section_controller := OverlaySectionController.new()
	content.add_child(section_controller)

	var title := Label.new()
	title.text = "Frontier Systems"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	content.add_child(title)

	var mode := Label.new()
	mode.text = "Client runtime started"
	mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(mode)

	var details := Label.new()
	details.text = "Prototype airlock controls use the fixed-tick command queue. Network authority and persistence are not configured yet."
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(details)

	_pressure_status_label = Label.new()
	_pressure_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pressure_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_pressure_status_label)
	_alarm_indicator = AlarmStatusIndicator.new()
	content.add_child(_alarm_indicator)

	var actions := GridContainer.new()
	actions.columns = 2
	content.add_child(actions)
	_add_airlock_action_button(actions, "Equalize with habitat", AirlockState.Action.OPEN_EQUALIZATION)
	_add_airlock_action_button(actions, "Close equalization", AirlockState.Action.CLOSE_EQUALIZATION)
	_add_airlock_action_button(actions, "Vent to exterior", AirlockState.Action.OPEN_VENT)
	_add_airlock_action_button(actions, "Close vent", AirlockState.Action.CLOSE_VENT)
	_add_airlock_action_button(actions, "Open habitat door", AirlockState.Action.OPEN_INNER)
	_add_airlock_action_button(actions, "Close habitat door", AirlockState.Action.CLOSE_INNER)
	_add_airlock_action_button(actions, "Open exterior door", AirlockState.Action.OPEN_OUTER)
	_add_airlock_action_button(actions, "Close exterior door", AirlockState.Action.CLOSE_OUTER)
	_add_access_test_button(actions, "Open inner (bypass only)", AirlockState.Action.OPEN_INNER)
	_add_access_test_button(actions, "Open outer (bypass only)", AirlockState.Action.OPEN_OUTER)
	_add_manual_action_button(actions, "Crowbar inner open", AirlockState.Action.OPEN_INNER)
	_add_manual_action_button(actions, "Crowbar inner close", AirlockState.Action.CLOSE_INNER)
	_add_manual_action_button(actions, "Crowbar outer open", AirlockState.Action.OPEN_OUTER)
	_add_manual_action_button(actions, "Crowbar outer close", AirlockState.Action.CLOSE_OUTER)

	var bypass_title := Label.new()
	bypass_title.text = "Access bypass work (local development tools)"
	bypass_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(bypass_title)
	var bypass_actions := GridContainer.new()
	bypass_actions.columns = 2
	content.add_child(bypass_actions)
	_add_bypass_button(bypass_actions, "Electrical inner", "inner", "electrical")
	_add_bypass_button(bypass_actions, "Mechanical inner", "inner", "mechanical")
	_add_bypass_button(bypass_actions, "Combined inner", "inner", "combined")
	_add_bypass_button(bypass_actions, "Electrical outer", "outer", "electrical")
	_add_bypass_button(bypass_actions, "Mechanical outer", "outer", "mechanical")
	_add_bypass_button(bypass_actions, "Combined outer", "outer", "combined")

	_last_action_label = Label.new()
	var control_button := Button.new()
	control_button.text = "Debug pulse: trigger receiver output"
	control_button.disabled = not OS.is_debug_build()
	control_button.pressed.connect(_submit_debug_control_pulse)
	content.add_child(control_button)
	_control_status_label = Label.new()
	_control_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_control_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_control_status_label)
	var profiling_toggle := CheckButton.new()
	profiling_toggle.text = "Capture recent tick profiling (120 samples)"
	profiling_toggle.toggled.connect(_toggle_profiling_history)
	content.add_child(profiling_toggle)
	_profiling_status_label = Label.new()
	_profiling_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_profiling_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_profiling_status_label)
	var profiling_report_button := Button.new()
	profiling_report_button.text = "Summarize recent profiling capture"
	profiling_report_button.pressed.connect(_summarize_profiling)
	content.add_child(profiling_report_button)
	_profiling_report_label = Label.new()
	_profiling_report_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_profiling_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_profiling_report_label)
	var maintenance_actions := GridContainer.new()
	maintenance_actions.columns = 2
	content.add_child(maintenance_actions)
	_add_maintenance_button(maintenance_actions, "Isolate controller", "isolate", {})
	_add_maintenance_button(maintenance_actions, "Restore controller power", "restore_power", {})
	_add_maintenance_button(maintenance_actions, "Remove latch to tray", "remove", {"instance_id": MachineControlSystem.LATCH_ID})
	_add_maintenance_button(maintenance_actions, "Install latch from tray", "install", {"instance_id": MachineControlSystem.LATCH_ID, "slot_id": "door.utility.1"})
	_add_maintenance_button(maintenance_actions, "Install alarm from tray", "install", {"instance_id": MachineControlSystem.ALARM_ID, "slot_id": "door.utility.2"})
	_add_maintenance_button(maintenance_actions, "Remove alarm to tray", "remove", {"instance_id": MachineControlSystem.ALARM_ID})
	_add_maintenance_button(maintenance_actions, "Wire receiver to alarm", "attach_wire", {"wire_id": "habitat_airlock-alarm-wire", "first_module": MachineControlSystem.RECEIVER_ID, "first_port": "pulse_out", "second_module": MachineControlSystem.ALARM_ID, "second_port": "raise_alarm"})
	_add_maintenance_button(maintenance_actions, "Disconnect alarm wire", "detach_wire", {"wire_id": "habitat_airlock-alarm-wire"})
	_add_maintenance_button(maintenance_actions, "Fit stock board (timed)", "replace_board", {"target_board_id": "habitat-board-stock"})
	_add_maintenance_button(maintenance_actions, "Fit expanded board (timed)", "replace_board", {"target_board_id": "habitat-board-expanded"})
	_add_maintenance_button(maintenance_actions, "Resume board work", "resume_board_job", {})
	_add_maintenance_button(maintenance_actions, "Cancel board work", "cancel_board_job", {})
	_add_maintenance_button(maintenance_actions, "Disconnect latch wire", "detach_wire", {"wire_id": "habitat_airlock-unlock-wire"})
	_add_maintenance_button(maintenance_actions, "Wire receiver to unlock", "attach_wire", {"wire_id": "habitat_airlock-unlock-wire", "first_module": MachineControlSystem.RECEIVER_ID, "first_port": "pulse_out", "second_module": MachineControlSystem.LATCH_ID, "second_port": "unlock"})
	_add_maintenance_button(maintenance_actions, "Wire receiver to lock", "attach_wire", {"wire_id": "habitat_airlock-unlock-wire", "first_module": MachineControlSystem.RECEIVER_ID, "first_port": "pulse_out", "second_module": MachineControlSystem.LATCH_ID, "second_port": "lock"})
	_last_action_label.text = "Start by equalizing the chamber with the habitat."
	_last_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_last_action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_last_action_label)
	_overlay_section_stack = OverlaySectionStack.new()
	content.add_child(_overlay_section_stack)
	_inventory_panel = LocalInventoryPanel.new()
	var inventory_panel_result: ServiceResult = _inventory_panel.configure(_world_runtime)
	if not inventory_panel_result.is_success:
		push_warning("Inventory panel setup failed: %s" % inventory_panel_result.error_code)
	var health_panel := LocalHealthPanel.new()
	_inventory_panel.add_child(health_panel)
	var health_panel_result: ServiceResult = health_panel.configure(_world_runtime)
	if not health_panel_result.is_success:
		push_warning("Health panel setup failed: %s" % health_panel_result.error_code)
	_register_overlay_section("hud.status", "Pressure and alarms", [_pressure_status_label, _alarm_indicator], false)
	_register_overlay_section("hud.airlock", "Airlock controls", [actions])
	var inventory_section: ServiceResult = _overlay_section_stack.register_section("hud.inventory", "Local inventory demo", _inventory_panel)
	if not inventory_section.is_success:
		push_warning("Inventory section setup failed: %s" % inventory_section.error_code)
	_register_overlay_section("hud.access", "Access bypass", [bypass_title, bypass_actions])
	_register_overlay_section("hud.machine", "Machine maintenance", [control_button, _control_status_label, maintenance_actions])
	_register_overlay_section("hud.profiling", "Profiling", [profiling_toggle, _profiling_status_label, profiling_report_button, _profiling_report_label])
	_register_overlay_section("hud.feedback", "Action feedback", [_last_action_label], false)
	var sections_result: ServiceResult = section_controller.configure(_overlay_section_stack)
	if not sections_result.is_success:
		push_warning("HUD section setup failed: %s" % sections_result.error_code)
	var panel_registry := OverlayPanelRegistry.new()
	var controls_registered: ServiceResult = panel_registry.register_panel("overlay.controls", panel)
	var habitat_registered: ServiceResult = panel_registry.register_panel("overlay.habitat", view_column)
	var host_configured: ServiceResult = _overlay_layout_host.configure(panel_registry)
	if not controls_registered.is_success or not habitat_registered.is_success or not host_configured.is_success:
		push_error("Overlay panel registration failed.")
		return
	var layout_result: ServiceResult = layout_controller.configure(_overlay_layout_host)
	if not layout_result.is_success:
		push_warning("Overlay layout setup failed: %s" % layout_result.error_code)
	elif _habitat_preview.world_inventory != null:
		_habitat_preview.world_inventory.item_selected.connect(_inventory_panel.select_world_item)
		_habitat_preview.world_inventory.pickup_requested.connect(_inventory_panel.collect_world_item)
		_inventory_body_adapter = LocalInventoryBodyAdapter.new()
		add_child(_inventory_body_adapter)
		var adapter_result: ServiceResult = _inventory_body_adapter.configure(_world_runtime, _habitat_preview.character, ProceduralWorldInventoryPreview.DISPLAY_ORIGIN)
		if adapter_result.is_success:
			var link := CheckButton.new()
			link.text = "Link inventory actor to walker (local development)"
			link.tooltip_text = "Opt in to queued logical position updates from this local capsule. This is not network movement authority."
			link.toggled.connect(_inventory_body_adapter.set_enabled)
			_inventory_panel.add_child(link)


func _register_overlay_section(section_id: String, title: String, controls: Array[Control], collapsible: bool = true) -> void:
	var group := VBoxContainer.new()
	for control in controls:
		control.get_parent().remove_child(control)
		group.add_child(control)
	var result: ServiceResult = _overlay_section_stack.register_section(section_id, title, group, collapsible)
	if not result.is_success:
		push_error("HUD section registration failed: %s" % result.error_code)


func _process(_delta: float) -> void:
	if runtime_mode != RuntimeMode.CLIENT or _world_runtime == null or _pressure_status_label == null:
		return
	var result := _world_runtime.pressure_snapshot()
	if not result.is_success:
		_pressure_status_label.text = "Pressure state unavailable: %s" % result.message
		return
	var snapshot: Dictionary = result.value
	if _habitat_preview != null:
		_habitat_preview.observe_snapshot(snapshot)
		_inventory_observation_elapsed += _delta
		if _inventory_observation_elapsed >= 0.1:
			_inventory_observation_elapsed = 0.0
			var inventory := _world_runtime.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
			var context := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", _world_runtime.world_id, _world_runtime.region_id)
			var observed: ServiceResult = inventory.world_inventory_observation(context)
			if observed.is_success:
				_habitat_preview.world_inventory.observe(observed.value)
	var inner_state: String = "OPEN" if snapshot["inner_door_open"] else "CLOSED"
	var outer_state: String = "OPEN" if snapshot["outer_door_open"] else "CLOSED"
	var equalization_state: String = "OPEN" if snapshot["equalization_valve_open"] else "CLOSED"
	var vent_state: String = "OPEN" if snapshot["vent_valve_open"] else "CLOSED"
	var sensor_readings: Dictionary = snapshot["pressure_sensors"]
	var access_state: Dictionary = snapshot.get("access_control", {})
	if _alarm_indicator != null:
		var controller_records: Array = access_state.get("security_controllers", [])
		_alarm_indicator.observe_controller(controller_records[0] if not controller_records.is_empty() and controller_records[0] is Dictionary else {})
	var active_job_summary: String = _active_bypass_summary(access_state)
	_pressure_status_label.text = (
		"Pressure sensors: Habitat %0.2f kPa  |  Chamber %0.2f kPa  |  Exterior %0.4f kPa\n"
		+ "Inner door %s  |  Outer door %s  |  Equalization %s  |  Vent %s\n"
		+ "Access work: %s"
	) % [
		sensor_readings["habitat"]["pressure_kpa_absolute"],
		sensor_readings["chamber"]["pressure_kpa_absolute"],
		sensor_readings["exterior"]["pressure_kpa_absolute"],
		inner_state,
		outer_state,
		equalization_state,
		vent_state,
		active_job_summary,
	]
	var controls := _world_runtime.get_simulation_system(MachineControlSystem.SYSTEM_ID) as MachineControlSystem
	if controls != null and _control_status_label != null:
		var stats: Dictionary = controls.diagnostics()
		_control_status_label.text = "Circuit: %s pending | %s delivered | %s dropped | %s salvaged | %s" % [stats.get("pending_deliveries", 0), stats.get("delivered", 0), stats.get("dropped", 0), stats.get("salvage_parts", 0), stats.get("last_error", "")]
		_control_status_label.text += "\nBoard revision: %s" % stats.get("board_revision", 0)
		var job_value: Variant = stats.get("board_job")
		if typeof(job_value) == TYPE_DICTIONARY:
			_control_status_label.text += " | %s: %s/%s ticks" % [job_value["status"], job_value["completed_work_ticks"], BoardReplacementJob.WORK_TICKS]
	if _profiling_status_label != null:
		var profile: Dictionary = _world_runtime.profiling_snapshot()
		_profiling_status_label.text = "Tick: %s us | Commands: %s us | Capture: %s us | Queue: %s | Over budget: %s" % [profile.get("last_tick_usec", 0), profile.get("last_command_usec", 0), profile.get("last_profile_usec", 0), profile.get("queued_external_commands", 0), profile.get("over_budget_ticks", 0)]


func _set_preview_camera_mode(view_mode: int) -> void:
	if _habitat_preview != null and _habitat_preview.camera != null:
		_habitat_preview.activate_inspection(view_mode)


func _set_character_camera_mode(view_mode: int) -> void:
	if _habitat_preview != null:
		_habitat_preview.activate_character(view_mode)


func _toggle_profiling_history(enabled: bool) -> void:
	var configured: ServiceResult = _world_runtime.configure_profile_history(enabled, 120)
	if not configured.is_success:
		_last_action_label.text = configured.message


func _summarize_profiling() -> void:
	var captured: ServiceResult = _world_runtime.capture_profiling(120)
	if not captured.is_success:
		_profiling_report_label.text = captured.message
		return
	var report: Dictionary = captured.value["report"]
	if report["sample_count"] == 0:
		_profiling_report_label.text = "No samples captured. Enable tick profiling before requesting a summary."
		return
	var timing: Dictionary = report["tick_timing_usec"]
	_profiling_report_label.text = "%s ticks | Mean %.1f us | p95 %s us | p99 %s us | Queue peak %s | Over budget %s" % [report["sample_count"], timing["mean"], timing["p95"], timing["p99"], report["queue_peak"], report["over_budget_samples"]]


func _add_maintenance_button(parent: GridContainer, label: String, operation: String, parameters: Dictionary) -> void:
	var button := Button.new()
	button.text = label
	button.disabled = not OS.is_debug_build()
	button.pressed.connect(_submit_maintenance.bind(operation, parameters.duplicate(true)))
	parent.add_child(button)


func _submit_maintenance(operation: String, parameters: Dictionary) -> void:
	var parsed: ServiceResult = MachineMaintenanceIntent.from_record({"schema_version": 2, "operation": operation, "parameters": parameters})
	if not parsed.is_success:
		_last_action_label.text = parsed.message
		return
	var command := MachineMaintenanceCommand.new()
	command.command_id = _world_runtime.next_local_request_id()
	command.source = &"local-maintenance"
	command.intent = parsed.value
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(&"local-player", _world_runtime.world_id, _world_runtime.region_id)
	var queued: ServiceResult = _world_runtime.enqueue_command(command)
	_last_action_label.text = "Maintenance queued: %s" % operation if queued.is_success else "Maintenance refused: %s" % queued.message


func _submit_debug_control_pulse() -> void:
	var command := DebugControlPulseCommand.new()
	command.command_id = _world_runtime.next_local_request_id()
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(&"local-player", _world_runtime.world_id, _world_runtime.region_id)
	command.source = &"local-control-probe"
	var result: ServiceResult = _world_runtime.enqueue_command(command)
	_last_action_label.text = "Control pulse queued; delivery follows emission on the next tick." if result.is_success else "Control probe refused: %s" % result.message


func _add_airlock_action_button(parent: GridContainer, label: String, action: int) -> void:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_submit_airlock_action.bind(action))
	parent.add_child(button)


func _add_bypass_button(parent: GridContainer, label: String, door: String, route: String) -> void:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_submit_bypass_job.bind(door, route))
	parent.add_child(button)


func _add_access_test_button(parent: GridContainer, label: String, action: int) -> void:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_submit_airlock_action_without_normal_access.bind(action))
	parent.add_child(button)


func _add_manual_action_button(parent: GridContainer, label: String, action: int) -> void:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_submit_manual_airlock_action.bind(action))
	parent.add_child(button)


func _submit_airlock_action(action: int) -> void:
	_submit_airlock_action_with_access(action, true)


func _submit_airlock_action_without_normal_access(action: int) -> void:
	_submit_airlock_action_with_access(action, false)


func _submit_manual_airlock_action(action: int) -> void:
	_submit_airlock_action_with_access(action, false, true)


func _submit_airlock_action_with_access(action: int, has_normal_access: bool, manual: bool = false) -> void:
	if _world_runtime == null:
		return
	var command := AirlockCommand.new()
	command.command_id = _world_runtime.next_local_request_id()
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(
		&"local-player",
		_world_runtime.world_id,
		_world_runtime.region_id,
		has_normal_access
	)
	command.source = &"local-ui"
	command.airlock_id = WorldRuntime.PROTOTYPE_AIRLOCK_ID
	command.action = action
	command.manual_operation = manual
	var result := _world_runtime.enqueue_command(command)
	if result.is_success:
		_last_action_label.text = "Queued command %s for the next simulation tick." % command.command_id
	else:
		_last_action_label.text = "Command rejected: %s" % result.message


func _submit_bypass_job(door: String, route: String) -> void:
	if _world_runtime == null:
		return
	var command := StartBypassJobCommand.new()
	command.command_id = _world_runtime.next_local_request_id()
	command.authenticated_context = AuthenticatedCommandContext.for_local_development(
		&"local-player",
		_world_runtime.world_id,
		_world_runtime.region_id
	)
	command.source = &"local-ui"
	command.device_id = WorldRuntime.PROTOTYPE_AIRLOCK_ID
	command.target_id = StringName("%s-%s-door" % [WorldRuntime.PROTOTYPE_AIRLOCK_ID, door])
	command.route = StringName(route)
	var result := _world_runtime.enqueue_command(command)
	if result.is_success:
		_last_action_label.text = "Queued %s bypass work for the %s door." % [route, door]
	else:
		_last_action_label.text = "Bypass rejected: %s" % result.message


func _active_bypass_summary(access_state: Dictionary) -> String:
	if access_state.is_empty():
		return "unavailable"
	var status_parts: PackedStringArray = PackedStringArray()
	var jobs: Array = access_state.get("bypass_jobs", [])
	for job_value in jobs:
		if typeof(job_value) != TYPE_DICTIONARY:
			continue
		if job_value.get("status") == "active":
			status_parts.append("%s %s: %s%% (%s)" % [
				job_value.get("route", "unknown"),
				job_value.get("target_id", "device"),
				roundi(float(job_value.get("progress", 0.0)) * 100.0),
				job_value.get("stage", "work"),
			])
			break
	for controller_value in access_state.get("security_controllers", []):
		if typeof(controller_value) == TYPE_DICTIONARY and (controller_value.get("alarm_state", "quiet") != "quiet" or not controller_value.get("bypassed_channels", []).is_empty()):
			status_parts.append("controller %s" % controller_value.get("alarm_state", "unknown"))
	for actuator_value in access_state.get("actuators", []):
		if typeof(actuator_value) != TYPE_DICTIONARY:
			continue
		if actuator_value.get("latch_state") == "released":
			status_parts.append("%s latch released" % actuator_value.get("actuator_id", "actuator"))
	return " | ".join(status_parts) if not status_parts.is_empty() else "idle"


func _on_command_completed(command: SimulationCommand, result: ServiceResult) -> void:
	if _last_action_label == null:
		return
	if result.is_success:
		_last_action_label.text = "Applied %s on %s." % [command.source, command.command_id]
	else:
		_last_action_label.text = "Action refused: %s" % result.message
