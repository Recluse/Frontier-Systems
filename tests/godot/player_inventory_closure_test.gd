extends SceneTree

class RecordingRemote extends RemoteWorldRuntime:
	var sent: Array[SimulationCommand] = []
	var reject_queue: bool = false
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		if reject_queue: return ServiceResult.failure(&"offline", "Queue unavailable")
		sent.append(command)
		return ServiceResult.success()

var failures: int = 0
var last: ServiceResult
var world: WorldRuntime
var inventory: InventorySimulationSystem
var actor: AuthenticatedCommandContext
var remote: RecordingRemote
var panel: PlayerInventoryPanel

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frame() -> Dictionary:
	return {"inventory": inventory.own_inventory_observation(actor, true).value}

func select_container(id: String) -> void:
	for index in range(panel._closure_target.item_count):
		if panel._closure_target.get_item_metadata(index) == id:
			panel._closure_target.select(index)
			panel._closure_target.item_selected.emit(index)
			return
	check(false, "fixture target exists: " + id)

func apply(request: SimulationCommand) -> void:
	request.authenticated_context = actor
	check(world.enqueue_command(request).is_success, "real world queues intent")
	world.get_node("SimulationRunner")._physics_process(1.0 / 60.0)

func key(code: Key, shift: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = down
		root.push_input(event)
		await process_frame

func run() -> void:
	PlayerInputSettings.instance()._reset_map()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(440, 900)
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "actual world fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	actor = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	remote = RecordingRemote.new()
	root.add_child(remote)
	var scroll := ScrollContainer.new()
	root.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PlayerInventoryPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	panel.configure(remote)
	panel.observe(frame())
	select_container("storage.backpack-1")
	check(panel._closure_status.text.contains("closure: unavailable"), "legacy v3 never invents open state")
	check(not panel._closure_buttons["close_container"].disabled, "explicit legacy request leaves closure decision to host")
	var before: Dictionary = inventory.capture_snapshot().value["owner"]["ledger"]
	var initial_revision: int = frame()["inventory"]["inventory_revision"]
	# Keyboard activation exercises the actual connected Button.
	var button: Button = panel._closure_buttons["close_container"]
	panel._closure_target.grab_focus()
	await process_frame
	for expected in [panel._closure_status, panel._closure_feedback, panel._closure_buttons["open_container"], button]:
		await key(KEY_TAB)
		check(expected.has_focus(), "Tab reaches closure guidance/actions")
	check(button.has_focus() and scroll.follow_focus, "keyboard closure button focus and reveal")
	await key(KEY_TAB, true)
	check(panel._closure_buttons["open_container"].has_focus(), "Shift Tab returns to open control")
	await key(KEY_TAB)
	await key(KEY_ENTER)
	check(remote.sent.size() == 1, "Enter submits one closure intent")
	if remote.sent.is_empty(): quit(1); return
	var request: SimulationCommand = remote.sent[-1]
	check(request.operation == "close_container" and request.payload == {"container_id": "storage.backpack-1", "expected_revision": initial_revision}, "exact merged closure payload: %s %s expected %s" % [request.operation, JSON.stringify(request.payload), initial_revision])
	check(panel._closure_status.text.contains("unavailable") and panel._closure_feedback.text.contains(str(request.command_id)), "pending request ID shown without optimistic closure")
	var mismatch := InventoryDevelopmentCommand.new()
	mismatch.command_id = request.command_id
	mismatch.operation = "open_container"
	mismatch.payload = request.payload.duplicate(true)
	remote.command_completed.emit(mismatch, ServiceResult.success())
	check(not panel._pending_closure.is_empty(), "same ID wrong operation does not resolve exact intent")
	mismatch.operation = request.operation
	mismatch.payload["container_id"] = "storage.pouch-1"
	remote.command_completed.emit(mismatch, ServiceResult.success())
	check(not panel._pending_closure.is_empty(), "same ID wrong payload does not resolve exact intent")
	panel._closure_action("open_container")
	check(remote.sent.size() == 1 and panel._closure_target.disabled, "pending cannot retarget or retry")
	apply(request)
	check(last.is_success, "host actually closes selected container")
	remote.command_completed.emit(request, last)
	check(panel._pending.is_empty() and panel._closure_status.text.contains("unavailable") and panel._closure_feedback.text.contains("revision " + str(initial_revision)), "receipt retains exact targets without predicting observed state")
	panel.observe(frame())
	check(panel._closure_status.text.contains("closure: closed"), "v4 fresh observation establishes closed state")
	var after: Dictionary = inventory.capture_snapshot().value["owner"]["ledger"]
	check(after["items"] == before["items"], "closure conserves exact items and provenance")
	var move := InventoryDevelopmentCommand.new()
	move.command_id = &"closure.transfer"
	move.operation = "self"
	move.payload = {"operation": "move", "item_id": "crowbar-1", "source_container_id": "storage.pouch-1", "destination_container_id": "body.human-1", "slot_id": "", "expected_revision": after["state_revision"]}
	apply(move)
	check(not last.is_success, "real transfer through closed ancestor is refused")
	select_container("storage.pouch-1")
	panel._closure_action("open_container")
	apply(remote.sent[-1])
	check(not last.is_success, "nested opening through closed ancestor refused by host")
	remote.command_completed.emit(remote.sent[-1], last)
	select_container("storage.backpack-1")
	panel._closure_action("open_container")
	var stale_request: SimulationCommand = remote.sent[-1]
	# A separate actor intent advances authority after panel intent creation.
	var reopen := InventoryDevelopmentCommand.new()
	reopen.command_id = &"closure.external-open"
	reopen.operation = "open_container"
	reopen.payload = stale_request.payload.duplicate(true)
	apply(reopen)
	check(last.is_success, "independent authoritative reopen")
	apply(stale_request)
	check(not last.is_success, "stale closure revision refused")
	remote.command_completed.emit(stale_request, last)
	check(panel._closure_feedback.text.contains("Host rejected") and panel._closure_feedback.text.contains(str(stale_request.command_id)), "stale rejection exact receipt shown")
	panel.observe(frame())
	move.command_id = &"closure.transfer-open"
	move.payload["expected_revision"] = frame()["inventory"]["inventory_revision"]
	apply(move)
	check(last.is_success, "real transfer allowed after open observation")
	panel.observe(frame())
	var reordered: Dictionary = frame()
	reordered["inventory"]["container_records"].reverse()
	panel.observe(reordered)
	check(panel._closure_selected_id == "storage.backpack-1", "reordering preserves stable selection")
	var missing: Dictionary = frame()
	missing["inventory"]["container_records"].clear()
	panel.observe(missing)
	check(panel._closure_target.get_item_text(panel._closure_target.selected).contains("storage.backpack-1") and panel._closure_buttons["open_container"].disabled, "vanished target retained unavailable without retargeting")
	panel.observe(frame())
	check(panel._closure_selected_id == "storage.backpack-1", "returning same target remains selected")
	var partial: Dictionary = frame()
	for container in partial["inventory"]["container_records"]: container.erase("is_open")
	panel.observe(partial)
	check(panel._closure_status.text.contains("unavailable") and panel._closure_buttons["close_container"].disabled, "missing v4 closure unavailable and action disabled")
	panel.observe(frame())
	var older: Dictionary = frame()
	older["inventory"]["inventory_revision"] = 0
	panel.observe(older)
	check(panel._closure_status.text.contains("unavailable") and panel._closure_buttons["close_container"].disabled, "older revision removes closure claim")
	panel.observe(frame())
	await create_timer(5.1).timeout
	check(panel._closure_status.text.contains("unavailable") and panel._closure_buttons["close_container"].disabled, "aged closure unavailable")
	panel.observe({})
	panel.observe(frame())
	remote.reject_queue = true
	panel._closure_action("close_container")
	check(panel._pending_closure.is_empty() and panel._closure_feedback.text.contains("Queue unavailable"), "queue failure creates no pending claim")
	remote.reject_queue = false
	panel._closure_action("close_container")
	var late: SimulationCommand = remote.sent[-1]
	remote.command_completed.emit(late, ServiceResult.failure(&"remote_disconnected", "Host connection closed"))
	remote.connection_closed.emit("Disconnected")
	remote.command_completed.emit(late, ServiceResult.success())
	check(panel._closure_feedback.text.contains("outcome unknown") and panel._closure_feedback.text.contains(str(late.command_id)) and panel._closure_selected_id == "storage.backpack-1", "disconnect preserves exact uncertainty and selection; late receipt ignored")
	panel.observe(frame())
	check(panel._closure_status.text.contains("closure: open"), "reconnect consumes host state without retry")
	for width in [440, 280]:
		root.size = Vector2i(width, 640)
		await process_frame
		await process_frame
		check(panel._closure_status.size.x <= width and panel._closure_feedback.size.x <= width and button.size.x <= width, "closure controls bounded at width %s: panel %s status %s feedback %s button %s" % [width, panel.size.x, panel._closure_status.size.x, panel._closure_feedback.size.x, button.size.x])
		panel._closure_feedback.grab_focus()
		await process_frame
		check(panel._closure_feedback.has_focus(), "exact closure feedback keyboard review")
	panel.free()
	scroll.free()
	remote.free()
	world.free()
	quit(0 if failures == 0 else 1)
