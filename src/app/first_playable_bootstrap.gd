extends Node
class_name FirstPlayableBootstrap

var _world: WorldRuntime
var _store: WorldPersistenceAdapter
var _remote: RemoteWorldRuntime
var _status: Label
var _checkpoint_status: Label
var _checkpoint_request: CheckpointRequest
var _checkpoint_outcome_unknown: bool = false
var _content: VBoxContainer
var _habitat: ProceduralHabitatPreview
var _production_panel: LocalProductionPanel
var _inventory_label: Label
var _body_initialized: bool = false
var _elapsed: float = 0.0
var _movement_pending: bool = false
var _movement_request: InventoryDevelopmentCommand
var _movement_status: Label
var _last_position: Array = []
var _latest: Dictionary = {}
var _avatars: Dictionary = {}
var _scroll: ScrollContainer
var _inventory_panel: PlayerInventoryPanel
var _machinery_panel: MachineryPanel
var _machinery_preview: MachineryPreview
var _tabs: TabContainer
var _hands_hud: Label
var _terrain_panel: TerrainControlsPanel
var _terrain_preview: TerrainCellPreview
var _task_guide: FirstPlayableTaskGuidePanel
var _look_viewport: SubViewport
var _reconnect: Button
var _connection_status: Label
var _host_actions: Array[Button] = []
var _drawer_toggle: Button
var _essential_scroll: ScrollContainer
var _command_feedback: Label
var _feedback_summary: Label
var _checkpoint_scroll: ScrollContainer
var _production_recovery: String = ""
var _world_labels_enabled: bool = false
var _target_feedback: HabitatTargetFeedback


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--host"):
		_start_host()
	else:
		_start_client()


func _start_host() -> void:
	Engine.max_fps = 60
	_world = WorldRuntime.new()
	_world.resource_carriers_enabled = true
	add_child(_world)
	_store = WorldPersistenceAdapter.new()
	add_child(_store)
	var directory: String = OS.get_environment("FRONTIER_SAVE_DIRECTORY")
	if directory.is_empty():
		directory = "user://first-playable-world"
	var history: ServiceResult = CheckpointOperator.history_from_settings(OS.get_environment("FRONTIER_BACKUP_ENTRIES"), OS.get_environment("FRONTIER_BACKUP_BYTES"))
	if not history.is_success:
		push_error(history.message)
		get_tree().quit(CheckpointOperator.EXIT_OPTIONS)
		return
	var configured: ServiceResult = _store.configure(_world, directory, null, history.value)
	if not configured.is_success:
		push_error(configured.message)
		get_tree().quit(1)
		return
	print("Backup history disabled." if history.value == null else "Backup history enabled: %d entries, %d retained bytes." % [history.value.entries, history.value.retained_bytes])
	_store.checkpoint_completed.connect(func(tick: int, result: ServiceResult) -> void:
		print(CheckpointOperator.checkpoint_diagnostic(tick, result, _store.backup_status()))
	)
	var host := FirstPlayableHost.new()
	host.persistence = _store
	add_child(host)
	var keys: Array[String] = [OS.get_environment("FRONTIER_PLAYER_ONE_KEY"), OS.get_environment("FRONTIER_PLAYER_TWO_KEY")]
	var network: ServiceResult = host.configure(_world, keys)
	if not network.is_success or not _world.start_simulation().is_success:
		push_error(network.message)
		get_tree().quit(1)
		return
	print("First playable host listening on loopback port 27840; two invite slots and checkpoint persistence enabled.")


## Presentation fixtures may supply a transport adapter without opening sockets.
func _create_client_remote() -> RemoteWorldRuntime:
	return RemoteWorldRuntime.new()


func _start_client() -> void:
	_remote = _create_client_remote()
	_remote.terrain_retry_directory = "user://terrain-client-intents"
	add_child(_remote)
	_remote.observation_received.connect(_on_observation)
	_remote.connection_closed.connect(_on_connection_closed)
	_remote.command_completed.connect(_on_completed)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	var shell := VBoxContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = 12
	shell.offset_top = 12
	shell.offset_right = -12
	shell.offset_bottom = -12
	canvas.add_child(shell)
	var navigation := HBoxContainer.new()
	shell.add_child(navigation)
	_drawer_toggle = Button.new()
	_drawer_toggle.text = "Open interaction"
	_drawer_toggle.toggle_mode = true
	_drawer_toggle.toggled.connect(_set_drawer_open)
	navigation.add_child(_drawer_toggle)
	var row := HSplitContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.split_offset = 420
	shell.add_child(row)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.x = 420
	_tabs.tabs_visible = false
	row.add_child(_tabs)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.name = "Workstation"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_tabs.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	var inventory_scroll := ScrollContainer.new()
	inventory_scroll.name = "Inventory"
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_scroll.follow_focus = true
	_tabs.add_child(inventory_scroll)
	_inventory_panel = PlayerInventoryPanel.new()
	_inventory_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.add_child(_inventory_panel)
	_inventory_panel.configure(_remote)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.name = "Settings"
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.follow_focus = true
	_checkpoint_scroll = settings_scroll
	_tabs.add_child(settings_scroll)
	var settings := PlayerControlsPanel.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings)
	var machinery_scroll := ScrollContainer.new()
	machinery_scroll.name = "Construction"
	machinery_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	machinery_scroll.follow_focus = true
	_tabs.add_child(machinery_scroll)
	_machinery_panel = MachineryPanel.new()
	_machinery_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	machinery_scroll.add_child(_machinery_panel)
	_machinery_panel.configure(_remote)
	var terrain_scroll := ScrollContainer.new()
	terrain_scroll.name = "Terrain"
	terrain_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	terrain_scroll.follow_focus = true
	_tabs.add_child(terrain_scroll)
	_terrain_panel = TerrainControlsPanel.new()
	_terrain_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_scroll.add_child(_terrain_panel)
	_terrain_panel.configure(_remote)
	var guide_scroll := ScrollContainer.new()
	guide_scroll.name = "Guide"
	guide_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	guide_scroll.follow_focus = true
	_tabs.add_child(guide_scroll)
	_task_guide = FirstPlayableTaskGuidePanel.new()
	_task_guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_scroll.add_child(_task_guide)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Connecting to the shared host…"
	var theme_selector := OverlayThemeController.new()
	settings.add_child(theme_selector)
	var themed: ServiceResult = theme_selector.configure(row, background)
	if not themed.is_success:
		push_warning(themed.message)
	var views := VBoxContainer.new()
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(views)
	_essential_scroll = ScrollContainer.new()
	_essential_scroll.custom_minimum_size.y = 86
	_essential_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_essential_scroll.follow_focus = true
	_essential_scroll.focus_mode = Control.FOCUS_ALL
	_essential_scroll.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
			_essential_scroll.scroll_vertical += 48 if event.is_action_pressed("ui_down") else -48
			_essential_scroll.accept_event()
	)
	views.add_child(_essential_scroll)
	var essential := VBoxContainer.new()
	essential.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_essential_scroll.add_child(essential)
	settings.add_child(_status)
	_connection_status = Label.new()
	_connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	views.add_child(_connection_status)
	views.move_child(_connection_status, 0)
	_feedback_summary = Label.new()
	_feedback_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	views.add_child(_feedback_summary)
	views.move_child(_feedback_summary, 1)
	_movement_status = Label.new()
	_movement_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_movement_status.text = "Movement unavailable until a fresh host observation."
	settings.add_child(_movement_status)
	_reconnect = Button.new()
	_reconnect.text = "Reconnect to shared host"
	_reconnect.pressed.connect(_connect_client)
	navigation.add_child(_reconnect)
	var help := FirstPlayableControlsHelp.new()
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(help)
	help.configure(_tabs)
	help.panel_requested.connect(_open_panel)
	var overview := Button.new()
	overview.text = "Overview: locate resources and the refinery"
	overview.pressed.connect(func() -> void: _habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW))
	settings.add_child(overview)
	for mode in [LocalHabitatCharacter.CameraMode.FIRST_PERSON, LocalHabitatCharacter.CameraMode.THIRD_PERSON]:
		var button := Button.new()
		button.text = "First person" if mode == LocalHabitatCharacter.CameraMode.FIRST_PERSON else "Third person"
		button.pressed.connect(func() -> void: _habitat.activate_character(mode))
		settings.add_child(button)
	var container := SubViewportContainer.new()
	# World clicks must not make this forwarding surface a GUI focus owner.
	container.focus_mode = Control.FOCUS_NONE
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.size = Vector2i(800, 700)
	container.add_child(viewport)
	_habitat = ProceduralHabitatPreview.new()
	viewport.add_child(_habitat)
	for control in _habitat.find_children("*", "Control", true, false):
		if control is HabitatTargetFeedback: _target_feedback = control
	_target_feedback.compact = true
	var captions := CheckButton.new()
	captions.text = "Show world captions"
	captions.toggled.connect(func(enabled: bool) -> void:
		_world_labels_enabled = enabled
		_update_world_labels()
	)
	settings.add_child(captions)
	var target_guidance := CheckButton.new()
	target_guidance.text = "Show expanded target guidance"
	target_guidance.toggled.connect(func(enabled: bool) -> void: _target_feedback.compact = not enabled)
	settings.add_child(target_guidance)
	_habitat.production.workstation_selected.connect(_navigate_to_workstation)
	_machinery_preview = MachineryPreview.new()
	_habitat.add_child(_machinery_preview)
	_terrain_preview = TerrainCellPreview.new()
	_habitat.add_child(_terrain_preview)
	_machinery_panel.bind_preview(_machinery_preview)
	_machinery_preview.machine_selected.connect(func(id: String) -> void:
		_machinery_panel.select_machine(id)
		_open_panel(3)
	)
	_habitat.production.wall_selected.connect(func(id: String) -> void:
		_machinery_panel.select_wall(id)
		_open_panel(3)
	)
	_habitat.world_inventory.skip_machine_roots = true
	_tabs.tab_changed.connect(func(_index: int) -> void: _update_world_labels())
	_update_world_labels()
	_habitat.focus_production()
	_habitat.world_inventory.player_facing_labels = true
	_habitat.world_inventory.pickup_requested.connect(_pickup_world_item)
	_hands_hud = Label.new()
	_hands_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	views.add_child(_hands_hud)
	_command_feedback = Label.new()
	_command_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_command_feedback.focus_mode = Control.FOCUS_ALL
	essential.add_child(_command_feedback)
	essential.move_child(_command_feedback, 0)
	_inventory_label = Label.new()
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_panel.add_child(_inventory_label)
	var pickup := Button.new()
	pickup.text = "Collect canister from nearby tray"
	pickup.pressed.connect(_pickup_canister)
	_inventory_panel.add_child(pickup)
	var drop := Button.new()
	drop.text = "Drop a carried canister onto the nearby tray"
	drop.pressed.connect(_drop_canister)
	_inventory_panel.add_child(drop)
	var drop_plate := Button.new()
	drop_plate.text = "Place a carried plate on the nearby tray"
	drop_plate.pressed.connect(_drop_first_definition.bind("item.plate.prototype"))
	_inventory_panel.add_child(drop_plate)
	var save := Button.new()
	save.text = "Save shared world now"
	save.pressed.connect(_request_checkpoint)
	settings.add_child(save)
	_checkpoint_status = Label.new()
	_checkpoint_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_checkpoint_status.focus_mode = Control.FOCUS_ALL
	_checkpoint_status.text = "No manual checkpoint requested this session."
	settings.add_child(_checkpoint_status)
	_host_actions.assign([pickup, drop, drop_plate, save])
	for action in _host_actions: action.disabled = true
	_set_drawer_open(false)
	_connect_client()


## Hiding a panel never recreates it or clears its submitted identities.
func _set_drawer_open(open: bool) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	var restore_focus: bool = not open and focus != null and _tabs.is_ancestor_of(focus)
	_tabs.visible = open
	_update_world_labels()
	_drawer_toggle.set_pressed_no_signal(open)
	_drawer_toggle.text = "Close interaction" if open else "Open interaction"
	if restore_focus: _drawer_toggle.grab_focus()
	_refresh_command_feedback()


func _open_panel(index: int) -> void:
	PlayerInputSettings.instance().release_all()
	_tabs.current_tab = index
	_set_drawer_open(true)


func _update_world_labels() -> void:
	var show_labels: bool = _world_labels_enabled and (not _tabs.visible or _tabs.current_tab not in [3, 4])
	_habitat.production.set_labels_visible(show_labels)
	_habitat.world_inventory.labels_visible = show_labels
	for label in _habitat.world_inventory.find_children("*", "Label3D", true, false): label.visible = show_labels


## Mirror full existing receipts in a bounded, keyboard-scrollable persistent area.
## These labels are presentation; command correlation remains in the original panels.
func _refresh_command_feedback() -> void:
	if _command_feedback == null: return
	var receipts: PackedStringArray = []
	for label: Label in [_inventory_panel._result, _machinery_panel._request_identity, _machinery_panel._feedback]:
		if label != null and not label.text.is_empty(): receipts.append(label.text)
	if not _machinery_panel._pending_wall.is_empty(): receipts.append(_machinery_panel._placement_status.text)
	if _checkpoint_request != null or _checkpoint_outcome_unknown or _checkpoint_status.text.begins_with("Checkpoint failed") or _checkpoint_status.text.begins_with("Checkpoint not submitted") or _checkpoint_status.text.contains("confirmed on disk"):
		receipts.append(_checkpoint_status.text)
	if is_instance_valid(_production_panel) and not _production_panel.is_queued_for_deletion():
		if not _production_panel._feedback.text.is_empty(): receipts.append(_production_panel._feedback.text)
		if not _production_panel._pending.is_empty():
			receipts.append("Production request: " + _production_panel._pending)
			var request: SimulationCommand = _remote._requests.get(_production_panel._pending)
			if request != null: receipts.append(_command_identity(request))
	if not _production_recovery.is_empty(): receipts.append(_production_recovery)
	if _movement_pending or _movement_status.text.contains("unknown") or _movement_status.text.contains("rejected") or _movement_status.text.contains("not submitted"):
		receipts.append(_movement_status.text)
	_command_feedback.text = "\n".join(receipts)
	_command_feedback.visible = not receipts.is_empty()
	_essential_scroll.visible = not receipts.is_empty()
	var pending: bool = not _inventory_panel._pending.is_empty() or not _machinery_panel._pending.is_empty() or _checkpoint_request != null
	if is_instance_valid(_production_panel): pending = pending or not _production_panel._pending.is_empty()
	var unknown: bool = _command_feedback.text.to_lower().contains("unknown")
	var rejected: bool = _command_feedback.text.to_lower().contains("reject") or _command_feedback.text.to_lower().contains("failed")
	if unknown and pending:
		_feedback_summary.text = "Action pending · earlier outcome uncertain; review exact targets below"
	elif unknown:
		_feedback_summary.text = "Outcome uncertain · review action feedback below"
	elif pending:
		_feedback_summary.text = "Action pending · waiting for host; review exact targets below"
	elif rejected:
		_feedback_summary.text = "Action rejected or failed · review host feedback below"
	else:
		_feedback_summary.text = "Action feedback · review host outcome below"
	_feedback_summary.visible = not receipts.is_empty()


func _command_identity(command: SimulationCommand) -> String:
	var lines: PackedStringArray = ["Request: " + String(command.command_id)]
	if command is ProductionDevelopmentCommand:
		lines.append("Action: " + command.operation.replace("_", " "))
		for key: String in command.payload:
			lines.append(key.replace("_", " ").capitalize() + ": " + str(command.payload[key]))
	return "\n".join(lines)


## One volatile request reference and one bounded result; observations never confirm I/O.
func _request_checkpoint() -> void:
	var command := CheckpointRequest.new()
	command.command_id = StringName("save-%s" % _remote.next_local_request_id())
	_checkpoint_outcome_unknown = false
	_checkpoint_request = command
	_checkpoint_status.text = "Checkpoint requested; waiting for disk confirmation…"
	var queued: ServiceResult = _remote.enqueue_command(command)
	if not queued.is_success:
		_checkpoint_request = null
		_checkpoint_status.text = "Checkpoint not submitted: " + queued.message.left(512)
	_reveal_checkpoint_status.call_deferred()


## Reveal current feedback after wrapped text settles, without taking keyboard focus.
func _reveal_checkpoint_status() -> void:
	_refresh_command_feedback()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree() and _checkpoint_status.is_visible_in_tree():
		_checkpoint_scroll.ensure_control_visible(_checkpoint_status)

## Reuse operator configuration in memory only; never display or journal credentials.
func _connect_client() -> void:
	if _reconnect.disabled: return
	_reconnect.disabled = true
	_connection_status.text = "Connecting; waiting for authentication and a fresh host observation…"
	var url: String = OS.get_environment("FRONTIER_HOST_URL")
	if url.is_empty(): url = "ws://127.0.0.1:27840"
	var connected: ServiceResult = _remote.connect_host(url, OS.get_environment("FRONTIER_INVITE_KEY"))
	if not connected.is_success:
		_connection_status.text = connected.message + " Reconnect to retry."
		_reconnect.disabled = false


func _on_connection_closed(message: String) -> void:
	if _checkpoint_request != null:
		_checkpoint_outcome_unknown = true
	if _checkpoint_outcome_unknown:
		_checkpoint_status.text = "Checkpoint outcome unknown after disconnect; no request will be resubmitted."
	else:
		_checkpoint_status.text = "Checkpoint session ended; reconnect before requesting a new save."
	_checkpoint_request = null
	_status.text = message
	_connection_status.text = message + ". Reconnect, then inspect fresh state; unacknowledged actions are not resubmitted."
	_reconnect.disabled = false
	for action in _host_actions: action.disabled = true
	_latest = {}
	_task_guide.observe({})
	_body_initialized = false
	_movement_pending = false
	_movement_request = null
	_elapsed = 0.0
	_movement_status.text = "Movement session ended; local view is not host acceptance. Reconnect for fresh state."
	_last_position = []
	_hands_hud.text = "Hands unavailable until a fresh host observation."
	_inventory_label.text = "Inventory unavailable until a fresh host observation."
	_habitat.production.observe({})
	_habitat.world_inventory.observe({})
	_machinery_preview.observe({})
	_terrain_preview.observe({})
	for avatar in _avatars.values(): avatar.queue_free()
	_avatars.clear()
	# Production's disconnect contract releases its transport; rebuild on fresh data.
	if _production_panel != null:
		if _production_recovery.is_empty() and (not _production_panel._pending.is_empty() or _production_panel._feedback.text.to_lower().contains("disconnect") or _production_panel._feedback.text.to_lower().contains("unknown")):
			_production_recovery = "Production connection ended · outcome unknown"
			if not _production_panel._pending.is_empty(): _production_recovery += " · request " + _production_panel._pending
			_production_recovery += "\n" + _production_panel._feedback.text
			if not _production_panel._cargo_pending.is_empty():
				_production_recovery += "\n" + JSON.stringify(_production_panel._cargo_pending)
			_production_recovery += "\nFresh observations do not confirm this request; no automatic retry."
		_production_panel.queue_free()
		_production_panel = null
	_refresh_command_feedback.call_deferred()


func _navigate_to_workstation() -> void:
	if _latest.is_empty() or not is_instance_valid(_production_panel) or _production_panel.is_queued_for_deletion():
		return
	_open_panel(0)
	var target: Control = _production_panel.refining_focus_control()
	# World selection must retain gameplay input for target feedback and sky clearing.
	# Keyboard focus follows the visible GUI controls when the player enters the pane.
	_reveal_interaction.call_deferred(target)


func _reveal_interaction(target: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(target) and target.is_visible_in_tree():
		_scroll.ensure_control_visible(target)


func _navigate_to_source(id: String) -> void:
	if _latest.is_empty() or not is_instance_valid(_production_panel) or _production_panel.is_queued_for_deletion(): return
	_open_panel(0)
	_production_panel.select_source(id)
	_reveal_interaction.call_deferred(_production_panel._deposit)


func _on_observation(record: Dictionary) -> void:
	_refresh_command_feedback.call_deferred()
	_connection_status.text = "Connected to shared colony · Crew %d" % (_remote.server_slot + 1)
	_reconnect.disabled = true
	for action in _host_actions: action.disabled = false
	_latest = record
	_task_guide.observe(record)
	_inventory_panel.observe(record)
	_machinery_panel.observe(record)
	_machinery_preview.observe(record["production"])
	_terrain_panel.observe(record)
	_terrain_preview.observe(record["terrain"])
	var hand_names: PackedStringArray = []
	for hand in record["inventory"]["hand_slot_ids"]:
		var held: String = "Empty"
		for binding in record["inventory"]["equipped"]:
			if binding["slot_id"] == hand:
				for item in record["inventory"]["items"]:
					if item["item_id"] == binding["item_id"]:
						held = PlayerInventoryPanel.NAMES.get(item["definition_id"], "Equipment")
		hand_names.append("%s%s: %s" % ["● " if record["inventory"]["active_hand_slot_id"] == hand else "", hand.replace("hand.", "").capitalize(), held])
	_hands_hud.text = " · ".join(hand_names) + " · Inventory: equipment and storage"
	_status.text = "Connected to shared colony · Crew %d" % (_remote.server_slot + 1)
	if not record.get("persistence", {}).is_empty():
		_status.text += " · saved tick %d" % record["persistence"]["saved_tick"]
	if _production_panel == null:
		_production_panel = LocalProductionPanel.new()
		_content.add_child(_production_panel)
		_production_panel.configure(_remote)
		_production_panel.observation_changed.connect(_habitat.production.observe)
		if not _habitat.production.source_selected.is_connected(_navigate_to_source):
			_habitat.production.source_selected.connect(_navigate_to_source)
		_habitat.production.extraction_requested.connect(_production_panel.extract_source)
	if not _body_initialized:
		var position: Array = record["position"]
		_habitat.character.position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(position[0]), maxf(950.0, float(position[1])), float(position[2])) / 1000.0
		_habitat.character.rotation.y = 0.0
		_habitat.activate_character(LocalHabitatCharacter.CameraMode.FIRST_PERSON)
		_last_position = position.duplicate()
		_body_initialized = true
		_movement_status.text = "Host position observed. Walking updates the local view; submitted movement waits for host acceptance."
		print("Shared host authenticated this client as crew %d." % (_remote.server_slot + 1))
	_habitat.production.observe(record["production"])
	if not record["world_items"].is_empty():
		_habitat.world_inventory.observe(record["world_items"])
	_inventory_label.text = "Carried mass: %.2f kg · items: %d" % [float(record["inventory"]["mass_milligrams"]) / 1000000.0, record["inventory"]["items"].size()]
	var visible: Dictionary = {}
	for player in record.get("players", []):
		if int(player["slot"]) == _remote.server_slot:
			continue
		visible[player["slot"]] = true
		if not _avatars.has(player["slot"]):
			var avatar := MeshInstance3D.new()
			var mesh := CapsuleMesh.new()
			mesh.radius = 0.3
			mesh.height = 1.8
			avatar.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("#5dba87")
			avatar.material_override = material
			_habitat.add_child(avatar)
			_avatars[player["slot"]] = avatar
		var coords: Array = player["position"]
		_avatars[player["slot"]].position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(coords[0]), maxf(950.0, float(coords[1])), float(coords[2])) / 1000.0
	for slot in _avatars.keys():
		if not visible.has(slot):
			_avatars[slot].queue_free()
			_avatars.erase(slot)


func _process(delta: float) -> void:
	_refresh_command_feedback()
	if _remote == null or not _body_initialized or _movement_pending:
		return
	_elapsed += delta
	if _elapsed < 0.15:
		return
	_elapsed = 0.0
	var point: Vector3 = (_habitat.character.position - ProceduralWorldInventoryPreview.DISPLAY_ORIGIN) * 1000.0
	var position: Array = [roundi(point.x), roundi(point.y), roundi(point.z)]
	if position == _last_position:
		return
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName("move-%s" % _remote.next_local_request_id())
	command.operation = "move_to"
	command.payload = {"position_millimetres": position}
	var sent: ServiceResult = _remote.enqueue_command(command)
	if sent.is_success:
		_movement_request = command
		_movement_status.text = "Movement submitted; waiting for host acceptance. Local view may differ from host position."
		_movement_pending = true
		_last_position = position
	else:
		_movement_status.text = "Movement not submitted: " + sent.message.left(512) + " Local view is not host acceptance."


func _on_completed(command: SimulationCommand, result: ServiceResult) -> void:
	_refresh_command_feedback.call_deferred()
	if command is ProductionDevelopmentCommand and result.error_code == &"remote_disconnected":
		_production_recovery = "Production outcome unknown after disconnect\n" + _command_identity(command) + "\nFresh observations do not confirm this request; no automatic retry."
	if command == _movement_request and _movement_request != null:
		_movement_pending = false
		_movement_request = null
		if result.error_code == &"remote_disconnected":
			_movement_status.text = "Movement outcome unknown after disconnect; local view is not host acceptance."
		elif result.is_success:
			_movement_status.text = "Host accepted the submitted movement. Further local motion needs its own acceptance."
		elif not _latest.is_empty():
			var position: Array = _latest["position"]
			_habitat.character.position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(position[0]), float(position[1]), float(position[2])) / 1000.0
			_last_position = position.duplicate()
			_movement_status.text = "Host rejected movement: " + result.message.left(512) + " Local view returned to the latest observed host position."
	_status.text = result.message if not result.is_success else _status.text
	if command is CheckpointRequest and command == _checkpoint_request:
		_checkpoint_request = null
		if result.error_code == &"remote_disconnected":
			_checkpoint_outcome_unknown = true
			_checkpoint_status.text = "Checkpoint outcome unknown after disconnect; no request will be resubmitted."
		elif result.is_success:
			_checkpoint_status.text = "Shared world checkpoint confirmed on disk."
		else:
			_checkpoint_status.text = "Checkpoint failed: " + result.message.left(512)
		_reveal_checkpoint_status.call_deferred()


# A look gesture belongs to the preview, not to the root GUI mouse latch.
# Dispatch it before GUI hit-testing so held RMB cannot pin later UI clicks
# to the SubViewportContainer. Ordinary world selection keeps native routing.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_action_pressed("look"):
		if _habitat == null or not is_instance_valid(_habitat):
			return
		var viewport: SubViewport = _habitat.get_viewport()
		var surface: SubViewportContainer = viewport.get_parent()
		if not surface.is_visible_in_tree() or not surface.get_global_rect().has_point(event.position) or not WorldSelectionInput.gameplay_allowed(viewport):
			return
		_look_viewport = viewport
	elif not (event.is_action_released("look") or event.is_action_pressed("release_cursor")) or not is_instance_valid(_look_viewport):
		return
	var forwarded: InputEvent = event
	if event is InputEventMouse:
		var surface: SubViewportContainer = _look_viewport.get_parent()
		forwarded = event.xformed_by(surface.get_global_transform_with_canvas().affine_inverse())
		if surface.stretch:
			forwarded = forwarded.xformed_by(Transform2D().scaled(Vector2.ONE / surface.stretch_shrink))
	_look_viewport.push_input(forwarded, true)
	if event.is_action_released("look") or event.is_action_pressed("release_cursor"):
		_look_viewport = null
	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _remote == null or PlayerInputSettings.instance().rebinding or event.is_echo():
		return
	if event.is_action_pressed("settings"):
		if _tabs.visible and _tabs.current_tab == 2: _set_drawer_open(false)
		else: _open_panel(2)
	elif event.is_action_pressed("inventory"):
		if _tabs.visible and _tabs.current_tab == 1: _set_drawer_open(false)
		else: _open_panel(1)
	elif event.is_action_pressed("ui_cancel") and _tabs.visible:
		_set_drawer_open(false)
	elif (_tabs.visible and _tabs.current_tab == 2) or Input.is_action_pressed("ui_cursor"):
		return
	elif event.is_action_pressed("switch_hand"):
		_inventory_panel.switch_active_hand()
	elif event.is_action_pressed("use_tool"):
		_inventory_panel.use_active_tool()
	elif event.is_action_pressed("camera_first"):
		_habitat.activate_character(LocalHabitatCharacter.CameraMode.FIRST_PERSON)
	elif event.is_action_pressed("camera_third"):
		_habitat.activate_character(LocalHabitatCharacter.CameraMode.THIRD_PERSON)
	elif event.is_action_pressed("camera_overview"):
		_habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW)
	else:
		return
	get_viewport().set_input_as_handled()


func _pickup_canister() -> void:
	if _latest.is_empty() or _latest["world_items"].is_empty():
		return
	for container in _latest["world_items"]["containers"]:
		for item in container["items"]:
			if item["definition_id"] == "item.resource-canister.prototype":
				_pickup_world_item(container["container_id"], item["item_id"])
				return


func _pickup_world_item(container_id: String, item_id: String) -> void:
	if _latest.is_empty() or _latest["world_items"].is_empty():
		return
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName("pickup-%s" % _remote.next_local_request_id())
	command.operation = "world"
	command.payload = {"operation": "pickup", "item_id": item_id, "world_container_id": container_id, "destination_container_id": _latest["inventory"]["body_container_id"], "slot_id": "", "expected_revision": _latest["world_items"]["inventory_revision"]}
	_remote.enqueue_command(command)


func _drop_canister() -> void:
	_drop_first_definition("item.resource-canister.prototype")


func _drop_first_definition(definition_id: String) -> void:
	if _latest.is_empty():
		return
	for item in _latest["inventory"]["items"]:
		if item["definition_id"] == definition_id:
			var command := InventoryDevelopmentCommand.new()
			command.command_id = StringName("drop-%s" % _remote.next_local_request_id())
			command.operation = "world"
			command.payload = {"operation": "drop", "item_id": item["item_id"], "world_container_id": "world.tray-1", "destination_container_id": "", "slot_id": "", "expected_revision": _latest["world_items"].get("inventory_revision", 0)}
			_remote.enqueue_command(command)
			return
