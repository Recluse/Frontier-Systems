extends SceneTree

var _failures: int = 0
var _world: WorldRuntime
var _panel: LocalProductionPanel
var _runner: SimulationRunner
var _context: AuthenticatedCommandContext
var _head: String
var _sequence: int = 0
var _capture: bool = false

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture-maintenance")
	if _capture:
		root.size = Vector2i(420, 760)
		root.content_scale_size = Vector2i(420, 760)
	_world = WorldRuntime.new()
	_world.resource_carriers_enabled = true
	root.add_child(_world)
	_check(_world.start_simulation().is_success, "fixture starts")
	_runner = _world.get_node("SimulationRunner")
	_runner.set_physics_process(false)
	_context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", _world.world_id, _world.region_id)
	var tools := _world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem
	_head = tools.capture_snapshot().value["ledger"]["assemblies"]["extractor-1"]["slots"]["head"]
	var saved: Dictionary = JSON.parse_string(_world.capture_world_snapshot_json().value)
	_mount_panel()
	_select_head()
	_check(_panel._maintenance_details.text.contains("healthy") and _panel._maintenance_button.disabled, "healthy component blocks unnecessary repair")
	_check(_panel._maintenance_details.text.contains("Energy quote unavailable"), "no fabricated energy quote")
	_check(ToolMaintenanceView.describe(_panel._tool_record, {}, _head).contains("Station reserve unavailable."), "absent workstation observation never invents a zero reserve")
	await _capture_view("healthy")
	_panel.free()
	_world.free()

	# Test-only restored condition; no fault command or UI mutation is introduced.
	saved["systems"]["tools"]["ledger"]["parts"][_head]["integrity_ppm"] = 500000
	_restore(saved)
	_select_head()
	_check(_panel._maintenance_details.text.contains("degraded") and not _panel._maintenance_button.disabled, "degraded owned part offers maintenance")
	await _capture_view("degraded")
	_power(false) # Queued first: makes the panel's subsequent revision stale.
	_panel._maintain_component()
	var request: String = _panel._pending
	_panel._maintain_component()
	_check(not request.is_empty() and request == _panel._pending and _panel._maintenance_feedback.text.begins_with("Queued:"), "queued state and double-click guard")
	await _capture_view("queued")
	_step()
	_check(_panel._maintenance_feedback.text.begins_with("Rejected:") and _integrity() == 500000, "real stale-revision command rejection retains condition")
	_check(_panel._maintenance_button.disabled and _panel._maintenance_details.text.contains("power is off"), "observed power prerequisite blocks maintenance")
	await _capture_view("rejected")
	_power(true)
	_step()
	_panel.refresh()
	var energy: int = _panel._record["energy_joules"]
	_panel._maintain_component()
	_step()
	_check(_panel._maintenance_feedback.text.begins_with("Accepted:") and _integrity() == 1000000 and int(_panel._record["energy_joules"]) < energy, "real maintenance settles condition and energy")
	_check(_panel._selected_part_id == _head and _panel._maintenance_button.disabled, "accepted refresh keeps stable selection")
	await _capture_view("accepted")
	_panel.free()
	_world.free()

	saved["systems"]["tools"]["ledger"]["parts"][_head]["integrity_ppm"] = 0
	_restore(saved)
	_select_head()
	_check(_panel._maintenance_details.text.contains("zero integrity") and _panel._maintenance_details.text.contains("disabled; missing"), "disabled capability shown from observed assembly actions")
	await _capture_view("disabled")
	_panel._maintain_component()
	_step()
	_check(_integrity() == 1000000 and _panel._maintenance_details.text.contains("action.extract: available"), "capability changes only after host maintenance")
	var original: Dictionary = _panel._tool_record.duplicate(true)
	_panel._tool_record["assemblies"].reverse()
	_panel._refresh_maintenance()
	_check(_panel._selected_part_id == _head and _panel._maintenance_parts.get_item_metadata(_panel._maintenance_parts.selected) == _head, "reordered observation keeps stable ID")
	for assembly in _panel._tool_record["assemblies"]:
		if assembly["assembly_id"] == "extractor-1":
			assembly["parts"] = []
	_panel._refresh_maintenance()
	_check(_panel._selected_part_id == _head and _panel._maintenance_parts.selected == 0 and _panel._maintenance_button.disabled, "removed stable ID never retargets")
	await _capture_view("stale-selection")
	_panel._tool_record = original
	_panel._refresh_maintenance()
	_check(_panel._selected_part_id == _head and _panel._maintenance_parts.selected > 0, "returning ID restores original selection")
	_panel.free()
	_world.free()

	# Exercise the real remote signals without opening sockets or reserving ports.
	var remote := RemoteWorldRuntime.new()
	root.add_child(remote)
	_panel = LocalProductionPanel.new()
	root.add_child(_panel)
	_check(_panel.configure(remote).is_success, "remote panel configures")
	remote.observation_received.emit({"tools": original})
	_check(not _panel._tool_record.is_empty(), "remote scoped tools arrive through existing signal")
	remote.connection_closed.emit("test disconnect")
	_check(_panel._tool_record.is_empty() and _panel._record.is_empty() and _panel._maintenance_button.disabled and _panel._maintenance_feedback.text.begins_with("Unavailable:"), "disconnect clears stale observations and disables commands")
	await _capture_view("disconnected")
	_panel.free()
	remote.free()
	if _failures == 0:
		print("Repair usability: healthy/degraded/disabled, paid accepted command, real stale rejection, stable selection, disconnect and quote gap passed.")
	quit(0 if _failures == 0 else 1)


func _restore(saved: Dictionary) -> void:
	_world = WorldRuntime.new()
	_world.resource_carriers_enabled = true
	root.add_child(_world)
	_check(_world.restore_world_snapshot_json(JSON.stringify(saved)).is_success and _world.start_simulation().is_success, "condition fixture restores and starts")
	_runner = _world.get_node("SimulationRunner")
	_runner.set_physics_process(false)
	_mount_panel()


func _mount_panel() -> void:
	_panel = LocalProductionPanel.new()
	_panel.position = Vector2(12, 12)
	_panel.size = Vector2(330, 700)
	root.add_child(_panel)
	_check(_panel.configure(_world).is_success, "panel configures")
	_panel.set_process(false)


func _select_head() -> void:
	for index in range(_panel._maintenance_parts.item_count):
		if _panel._maintenance_parts.get_item_metadata(index) == _head:
			_panel._maintenance_parts.select(index)
			_panel._select_maintenance_part(index)
			return
	_check(false, "head present in scoped observation")


func _power(enabled: bool) -> void:
	_sequence += 1
	var command := ProductionDevelopmentCommand.new()
	command.command_id = StringName("repair-ui-power-%d" % _sequence)
	command.authenticated_context = _context
	command.operation = "power"
	command.payload = {"station": "construction", "enabled": enabled, "expected_revision": _panel._record["state_revision"]}
	_check(_world.enqueue_command(command).is_success, "power change queued")


func _step() -> void:
	_runner._physics_process(1.0 / 60.0)


func _integrity() -> int:
	var tools := _world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem
	return tools.capture_snapshot().value["ledger"]["parts"][_head]["integrity_ppm"]


func _capture_view(name: String) -> void:
	if not _capture:
		return
	for child in _panel.get_children():
		if child is Control:
			child.visible = child.get_index() < 5
	_panel.size = Vector2(330, 700)
	await process_frame
	await process_frame
	_check(_panel.size.x <= 340.0, "maintenance layout fits a narrow 330 px panel (%s)" % _panel.size)
	var directory: String = "res://var/ci/repair-usability"
	DirAccess.make_dir_recursive_absolute(directory)
	_check(root.get_texture().get_image().save_png(directory + "/" + name + ".png") == OK, "local capture saved")


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)
