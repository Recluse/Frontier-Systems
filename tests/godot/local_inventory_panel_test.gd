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
	var panel := LocalInventoryPanel.new()
	root.add_child(panel)
	_check(panel.configure(world).is_success, "client inventory panel must configure")
	var before: String = world.capture_world_snapshot_json().value
	panel.refresh()
	_check(world.capture_world_snapshot_json().value == before, "UI observations must preserve world snapshot")
	_check(panel._own_records.is_empty() and panel._search_records.is_empty(), "actor must start without access to target items")
	panel._start_search("storage.backpack-1")
	panel._start_search("storage.pouch-1")
	_step(runner, 121)
	panel.refresh()
	_check(panel._search_records.size() == 1 and panel._search_records[0]["item_id"] == "pouch-1", "backpack UI must not reveal nested crowbar or lose its view on repeated queued clicks")
	panel._start_search("storage.pouch-1")
	_step(runner, 121)
	panel.refresh()
	_check(panel._search_records.size() == 1 and panel._search_records[0]["item_id"] == "crowbar-1", "separate pouch search must reveal its direct tool")
	_check(not panel._take_button.disabled, "fresh search must enable take for selected item")
	panel._take_selected()
	_step(runner, 181)
	panel.refresh()
	_check(panel._own_records.size() == 1 and panel._own_records[0]["item_id"] == "crowbar-1", "queued take must update actor's own list after completion")
	_check(panel._search_records.is_empty() and panel._take_button.disabled, "transfer must remove revoked search contents from UI")
	panel._self_action("switch_hand")
	_step(runner, 1)
	panel.refresh()
	_check(panel._status.text.contains("hand.right"), "self UI must switch active hand through queued command")
	for index in range(panel._slot_picker.item_count):
		if panel._slot_picker.get_item_metadata(index) == "hand.right":
			panel._slot_picker.select(index)
	panel._self_action("equip")
	_step(runner, 1)
	panel.refresh()
	_check(panel._equipment_label.text.contains("hand.right: crowbar-1"), "self UI must display authoritative fitted item")
	panel._self_action("unequip")
	_step(runner, 1)
	panel.refresh()
	_check(not panel._equipment_label.text.contains("crowbar-1"), "self UI must release binding while preserving item")
	panel._world_action("drop", false)
	_step(runner, 1)
	panel.refresh()
	_check(panel._own_records.is_empty() and panel._world_records.size() == 1, "UI drop must move the same item into reachable world storage")
	panel._world_action("pickup", true)
	_step(runner, 1)
	panel.refresh()
	_check(panel._own_records.size() == 1 and panel._equipment_label.text.contains("hand.right: crowbar-1"), "UI pickup must fit the same item into chosen slot")
	panel._self_action("unequip")
	_step(runner, 1)
	panel.refresh()
	panel._give_selected(false)
	_step(runner, 121)
	panel.refresh()
	_check(panel._own_records.is_empty(), "insertion must return actor's tool to target container")
	panel._start_search("storage.pouch-1")
	_step(runner, 121)
	panel.refresh()
	_check(not panel._view_id.is_empty(), "new search must grant a fresh live view")
	_step(runner, 300)
	panel.refresh()
	_check(panel._view_id.is_empty() and panel._search_records.is_empty() and panel._take_button.disabled, "expired view must clear cached UI entries and action")
	panel._start_search("storage.pouch-1")
	_step(runner, 121)
	panel.refresh()
	panel._submit(LocalInventoryPanel.TARGET, "resist", {})
	_step(runner, 1)
	panel._take_selected()
	_check(panel._search_records.is_empty() and panel._take_button.disabled, "click-time resistance must reject stale visible selection before enqueueing take")
	before = world.capture_world_snapshot_json().value
	panel.refresh()
	_check(world.capture_world_snapshot_json().value == before, "refresh after revocation must remain read-only")
	world.free()
	_check(panel._own_records.is_empty() and panel._search_records.is_empty() and panel._take_button.disabled, "world shutdown must clear data and disable actions")
	panel.queue_free()
	await process_frame
	if _failures == 0:
		print("Local inventory panel and scoped action scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _step(runner: SimulationRunner, count: int) -> void:
	for _index in range(count):
		runner._physics_process(1.0 / 60.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
