extends SceneTree

var _failures: int = 0
var _selected: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	world.start_simulation()
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var target: AuthenticatedCommandContext = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	var actor: AuthenticatedCommandContext = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	var command := InventoryDevelopmentCommand.new()
	command.command_id = &"preview-drop"
	command.authenticated_context = target
	command.operation = "world"
	command.payload = {"operation": "drop", "item_id": "backpack-1", "world_container_id": "world.tray-1", "destination_container_id": "", "slot_id": "", "expected_revision": 0}
	world.enqueue_command(command)
	runner._physics_process(1.0 / 60.0)
	var record: Dictionary = inventory.world_inventory_observation(actor).value
	_check(WorldStorageObservation.from_record(record).is_success, "actual v2 world projection must validate")
	var before: String = world.capture_world_snapshot_json().value
	var preview := ProceduralWorldInventoryPreview.new()
	root.add_child(preview)
	preview.item_selected.connect(func(_container: String, item: String) -> void: _selected = item)
	_check(preview.observe(record).is_success, "preview must accept scoped v2 data")
	_check(preview.presentation_snapshot()["visible_items"] == 1, "loaded bag preview must not render hidden descendants")
	var rebuilds: int = preview.presentation_snapshot()["rebuilds"]
	preview.observe(record.duplicate(true))
	_check(preview.presentation_snapshot()["rebuilds"] == rebuilds, "identical observations must not recreate geometry")
	var invalid: Dictionary = record.duplicate(true)
	invalid["containers"][0]["position_millimetres"][0] = INF
	_check(not preview.observe(invalid).is_success and preview.presentation_snapshot()["visible_items"] == 1, "invalid world position must preserve display atomically")
	invalid = record.duplicate(true)
	invalid["containers"][0]["items"].append(invalid["containers"][0]["items"][0].duplicate(true))
	_check(not preview.observe(invalid).is_success, "duplicate visible item identities must reject")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	preview._on_item_input(null, click, Vector3.ZERO, Vector3.UP, 0, "world.tray-1", "backpack-1")
	_check(_selected == "backpack-1", "selection must emit stable container/item identities")
	var identity: InventorySelectionLabel = preview._selection_label
	_check(identity.target == preview._visible_items.values()[0]["mesh"] and identity._lines[0].text.contains("backpack-1") and identity._lines[1].text.contains("world.tray-1"), "selected proxy shows stable identity and root")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var proxy: MeshInstance3D = identity.target
	camera.position = proxy.global_position + Vector3(0, 2, 4)
	camera.look_at(proxy.global_position)
	identity._process(0.0)
	_check(identity.visible and identity._anchor.distance_to(camera.unproject_position(proxy.global_position)) < 0.1, "leader tracks the real proxy under the active camera")
	var initial_anchor: Vector2 = identity._anchor
	camera.position.x += 1.0
	identity._process(0.0)
	_check(identity._anchor != initial_anchor, "camera movement refreshes anchor without observation rebuild")
	for extent in [Vector2i(800, 600), Vector2i(240, 180), Vector2i(1440, 900)]:
		root.size = extent
		await process_frame
		identity._process(0.0)
		_check(root.get_visible_rect().encloses(Rect2(identity._card.position, identity._card.size)), "card stays within resized viewport")
	preview.labels_visible = false
	identity._process(0.0)
	_check(not identity.visible, "hidden labels suppress selected card")
	preview.labels_visible = true
	identity._process(0.0)
	_check(identity.visible, "labels can be restored without rebuilding")
	camera.rotation.y += PI
	identity._process(0.0)
	_check(not identity.visible, "behind-camera proxy has no invented screen target")
	camera.look_at(proxy.global_position)
	var refreshed: Dictionary = record.duplicate(true)
	refreshed["containers"][0]["distance_millimetres"] = 1234
	preview.observe(refreshed)
	_check(identity.target != proxy and identity._lines[2].text.contains("1.23") and not preview._selected_key.is_empty(), "stable selection rebinds on rebuild and refreshes observed distance")
	_check(world.capture_world_snapshot_json().value == before, "geometry and selection alone must not mutate world")
	var panel := LocalInventoryPanel.new()
	root.add_child(panel)
	panel.configure(world)
	preview.pickup_requested.connect(panel.collect_world_item)
	click.double_click = true
	preview._on_item_input(null, click, Vector3.ZERO, Vector3.UP, 0, "world.tray-1", "backpack-1")
	runner._physics_process(1.0 / 60.0)
	panel.refresh()
	_check(panel._own_records.size() == 3, "double-click bridge must collect the existing loaded bag through queued commands")
	preview.observe(inventory.world_inventory_observation(actor).value)
	_check(preview.presentation_snapshot()["visible_items"] == 0 and identity.target == null and not identity.visible, "collected item must disappear from observed world display")
	_selected = ""
	preview._on_item_input(null, click, Vector3.ZERO, Vector3.UP, 0, "world.tray-1", "backpack-1")
	_check(_selected == "", "obsolete pick events must not select removed proxies")
	var crowded: Dictionary = record.duplicate(true)
	crowded["containers"][0]["items"].clear()
	for index in range(12):
		crowded["containers"][0]["items"].append({"item_id": "visual-%d" % index, "definition_id": "item.crowbar.prototype", "definition_revision": 1, "condition_permille": 1000, "container_id": "world.tray-1"})
	_check(preview.observe(crowded).is_success and preview.presentation_snapshot()["visible_items"] == 8, "per-container proxy allocation must stay bounded")
	camera.queue_free()
	preview.queue_free()
	panel.queue_free()
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("Procedural world inventory preview and selection scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
