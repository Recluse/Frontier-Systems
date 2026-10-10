extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	_check(world.start_simulation().is_success, "demo world must start")
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var inventory_panel := LocalInventoryPanel.new()
	root.add_child(inventory_panel)
	_check(inventory_panel.configure(world).is_success, "inventory section must compose grip panel")
	var panel: LocalGripPanel = inventory_panel._grip_panel
	var before: String = world.capture_world_snapshot_json().value
	panel.refresh()
	_check(world.capture_world_snapshot_json().value == before, "grip presentation must not mutate canonical state")
	_check(panel._observation["schema_version"] == 2 and not panel._observation.has("items"), "v2 grip observations must exclude inventory contents")
	_check(not panel._join_button.disabled and panel._hand_picker.item_count == 2, "free actor hands must permit an initial grip")
	panel._join_button.pressed.emit()
	var pending: String = panel._pending
	panel._action("grip_join")
	_check(not pending.is_empty() and panel._pending == pending and panel._join_button.disabled, "repeated clicks must retain one pending intent")
	runner._physics_process(1.0 / 60.0)
	panel.refresh()
	_check(panel._pending.is_empty() and panel._observation["sessions"].size() == 1 and panel._status.text.contains("waiting"), "first grip must show authoritative waiting state")
	_check(panel._hands_label.text.contains("hand.left: reserved") and panel._join_button.disabled, "reserved hand and existing membership must be visible")
	panel._principal_picker.select(1)
	panel._principal_picker.item_selected.emit(1)
	_check(panel._observation["sessions"].is_empty() and not panel._join_button.disabled, "target body must not inherit actor's private session list")
	panel._action("grip_join")
	runner._physics_process(1.0 / 60.0)
	panel.refresh()
	_check(panel._observation["sessions"][0]["participant_count"] == 2 and panel._status.text.contains("capability ready"), "second body's join must use the existing shared target session")
	panel._action("grip_release")
	runner._physics_process(1.0 / 60.0)
	panel.refresh()
	_check(panel._observation["sessions"].is_empty() and panel._release_button.disabled, "release must clear only the selected body's membership")
	var equip := InventoryDevelopmentCommand.new()
	equip.command_id = &"grip-panel-equip"
	equip.authenticated_context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	equip.operation = "self"
	equip.payload = {"operation": "equip", "item_id": "crowbar-1", "source_container_id": "storage.pouch-1", "destination_container_id": "", "slot_id": "hand.left", "expected_revision": 0}
	_check(world.enqueue_command(equip).is_success, "fixture equipment command must enqueue")
	runner._physics_process(1.0 / 60.0)
	panel.refresh()
	_check(panel._hands_label.text.contains("hand.left: occupied") and panel._hand_picker.item_count == 1 and panel._hand_picker.get_item_metadata(0) == "hand.right", "occupied hands must be reported and excluded from grip choices")
	panel._principal_picker.select(0)
	panel.refresh()
	_check(panel._observation["sessions"].size() == 1 and panel._status.text.contains("waiting"), "remaining actor must observe lost cooperative strength")
	panel._action("grip_release")
	runner._physics_process(1.0 / 60.0)
	panel.refresh()
	_select(panel._target_picker, "fixture.ladder")
	panel.refresh()
	_check(panel._action_picker.get_item_metadata(panel._action_picker.selected) == "pull_along", "ladder should default to supported traversal")
	panel._action("grip_join")
	runner._physics_process(1.0 / 60.0)
	panel.refresh()
	_check(panel._status.text.contains("capability ready"), "solo ladder grip must show current capability")
	var restored := WorldRuntime.new()
	root.add_child(restored)
	_check(restored.restore_world_snapshot_json(world.capture_world_snapshot_json().value).is_success and restored.start_simulation().is_success, "ladder world must restore paused")
	var restored_runner: SimulationRunner = restored.get_node("SimulationRunner")
	restored_runner.set_physics_process(false)
	var restored_panel := LocalGripPanel.new()
	root.add_child(restored_panel)
	_check(restored_panel.configure(restored).is_success and not restored_panel._resume_button.disabled, "UI must offer explicit solo recovery")
	restored_panel._resume_button.pressed.emit()
	restored_runner._physics_process(1.0 / 60.0)
	restored_panel.refresh()
	_check(not restored_panel._observation["sessions"][0]["paused"] and restored_panel._resume_button.disabled, "resume button must apply queued fresh recovery exactly once")
	var move := InventoryDevelopmentCommand.new()
	move.command_id = &"grip-panel-move"
	move.authenticated_context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	move.operation = "move_to"
	move.payload = {"position_millimetres": [3000, 0, 0]}
	_check(world.enqueue_command(move).is_success, "movement must enqueue")
	runner._physics_process(1.0 / 60.0)
	# The display still has old data: the click must re-read reach and membership.
	panel._action("grip_join")
	_check(panel._pending.is_empty() and panel._join_button.disabled and panel._observation["sessions"].is_empty(), "click-time refresh must reject lost contact")
	before = world.capture_world_snapshot_json().value
	panel.refresh()
	_check(world.capture_world_snapshot_json().value == before, "refresh after contact loss must remain read-only")
	world.free()
	_check(panel._observation.is_empty() and panel._join_button.disabled and panel._release_button.disabled and panel._hand_picker.item_count == 0, "world shutdown must clear and disable grip UI")
	restored.free()
	_check(restored_panel._observation.is_empty() and restored_panel._resume_button.disabled, "recovered UI must clear on shutdown too")
	inventory_panel.free()
	restored_panel.free()
	if _failures == 0:
		print("Local grip panel commands, cooperation, recovery and presentation isolation scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _select(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == id:
			picker.select(index)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
