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
var _movement_id: String = ""
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
	var row := HSplitContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_top = 12
	row.offset_right = -12
	row.offset_bottom = -12
	row.split_offset = 540
	canvas.add_child(row)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.x = 420
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
	_tabs.add_child(inventory_scroll)
	_inventory_panel = PlayerInventoryPanel.new()
	_inventory_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.add_child(_inventory_panel)
	_inventory_panel.configure(_remote)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.name = "Settings"
	settings_scroll.follow_focus = true
	_tabs.add_child(settings_scroll)
	var settings := PlayerControlsPanel.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings)
	var machinery_scroll := ScrollContainer.new()
	machinery_scroll.name = "Construction"
	_tabs.add_child(machinery_scroll)
	_machinery_panel = MachineryPanel.new()
	_machinery_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	machinery_scroll.add_child(_machinery_panel)
	_machinery_panel.configure(_remote)
	var terrain_scroll := ScrollContainer.new()
	terrain_scroll.name = "Terrain"
	_tabs.add_child(terrain_scroll)
	_terrain_panel = TerrainControlsPanel.new()
	_terrain_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_scroll.add_child(_terrain_panel)
	_terrain_panel.configure(_remote)
	var guide_scroll := ScrollContainer.new()
	guide_scroll.name = "Guide"
	_tabs.add_child(guide_scroll)
	_task_guide = FirstPlayableTaskGuidePanel.new()
	_task_guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_scroll.add_child(_task_guide)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Connecting to the shared host…"
	_content.add_child(_status)
	var theme_selector := OverlayThemeController.new()
	_content.add_child(theme_selector)
	var themed: ServiceResult = theme_selector.configure(row, background)
	if not themed.is_success:
		push_warning(themed.message)
	var views := VBoxContainer.new()
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(views)
	_connection_status = Label.new()
	_connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	views.add_child(_connection_status)
	_reconnect = Button.new()
	_reconnect.text = "Reconnect to shared host"
	_reconnect.pressed.connect(_connect_client)
	views.add_child(_reconnect)
	var help := FirstPlayableControlsHelp.new()
	views.add_child(help)
	help.configure(_tabs)
	var overview := Button.new()
	overview.text = "Overview: locate resources and the refinery"
	overview.pressed.connect(func() -> void: _habitat.activate_inspection(HabitatInspectionCamera.Mode.OVERVIEW))
	views.add_child(overview)
	for mode in [LocalHabitatCharacter.CameraMode.FIRST_PERSON, LocalHabitatCharacter.CameraMode.THIRD_PERSON]:
		var button := Button.new()
		button.text = "First person" if mode == LocalHabitatCharacter.CameraMode.FIRST_PERSON else "Third person"
		button.pressed.connect(func() -> void: _habitat.activate_character(mode))
		views.add_child(button)
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
	_habitat.production.workstation_selected.connect(_navigate_to_workstation)
	_machinery_preview = MachineryPreview.new()
	_habitat.add_child(_machinery_preview)
	_terrain_preview = TerrainCellPreview.new()
	_habitat.add_child(_terrain_preview)
	_machinery_panel.bind_preview(_machinery_preview)
	_machinery_preview.machine_selected.connect(func(id: String) -> void:
		_machinery_panel.select_machine(id)
		_tabs.current_tab = 3
	)
	_habitat.production.wall_selected.connect(func(id: String) -> void:
		_machinery_panel.select_wall(id)
		_tabs.current_tab = 3
	)
	_habitat.world_inventory.skip_machine_roots = true
	_tabs.tab_changed.connect(func(index: int) -> void:
		var show_workstation_labels: bool = index not in [3, 4]
		_habitat.production.set_labels_visible(show_workstation_labels)
		_habitat.world_inventory.labels_visible = show_workstation_labels
		for label in _habitat.world_inventory.find_children("*", "Label3D", true, false): label.visible = show_workstation_labels
	)
	_habitat.focus_production()
	_habitat.world_inventory.player_facing_labels = true
	_habitat.world_inventory.pickup_requested.connect(_pickup_world_item)
	_hands_hud = Label.new()
	_hands_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	views.add_child(_hands_hud)
	_inventory_label = Label.new()
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_inventory_label)
	var pickup := Button.new()
	pickup.text = "Collect canister from nearby tray"
	pickup.pressed.connect(_pickup_canister)
	_content.add_child(pickup)
	var drop := Button.new()
	drop.text = "Drop a carried canister onto the nearby tray"
	drop.pressed.connect(_drop_canister)
	_content.add_child(drop)
	var drop_plate := Button.new()
	drop_plate.text = "Place a carried plate on the nearby tray"
	drop_plate.pressed.connect(_drop_first_definition.bind("item.plate.prototype"))
	_content.add_child(drop_plate)
	var save := Button.new()
	save.text = "Save shared world now"
	save.pressed.connect(_request_checkpoint)
	_content.add_child(save)
	_checkpoint_status = Label.new()
	_checkpoint_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_checkpoint_status.text = "No manual checkpoint requested this session."
	_content.add_child(_checkpoint_status)
	_host_actions.assign([pickup, drop, drop_plate, save])
	for action in _host_actions: action.disabled = true
	_connect_client()


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
	_movement_id = ""
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
		_production_panel.queue_free()
		_production_panel = null


func _navigate_to_workstation() -> void:
	if _latest.is_empty() or not is_instance_valid(_production_panel) or _production_panel.is_queued_for_deletion():
		return
	_tabs.current_tab = 0
	_scroll.ensure_control_visible(_production_panel.refining_focus_control())


func _on_observation(record: Dictionary) -> void:
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
	_hands_hud.text = " · ".join(hand_names) + " · Inventory tab: equip tools and open portable storage"
	_status.text = "Connected to shared colony · Crew %d" % (_remote.server_slot + 1)
	if not record.get("persistence", {}).is_empty():
		_status.text += " · saved tick %d" % record["persistence"]["saved_tick"]
	if _production_panel == null:
		_production_panel = LocalProductionPanel.new()
		_content.add_child(_production_panel)
		_production_panel.configure(_remote)
		_production_panel.observation_changed.connect(_habitat.production.observe)
		_habitat.production.source_selected.connect(_production_panel.select_source)
		_habitat.production.extraction_requested.connect(_production_panel.extract_source)
	if not _body_initialized:
		var position: Array = record["position"]
		_habitat.character.position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(position[0]), maxf(950.0, float(position[1])), float(position[2])) / 1000.0
		_habitat.character.rotation.y = 0.0
		_habitat.activate_character(LocalHabitatCharacter.CameraMode.FIRST_PERSON)
		_last_position = position.duplicate()
		_body_initialized = true
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
		_movement_id = String(command.command_id)
		_movement_pending = true
		_last_position = position


func _on_completed(command: SimulationCommand, result: ServiceResult) -> void:
	if String(command.command_id) == _movement_id:
		_movement_pending = false
		if not result.is_success and not _latest.is_empty():
			var position: Array = _latest["position"]
			_habitat.character.position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(position[0]), float(position[1]), float(position[2])) / 1000.0
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
		_tabs.current_tab = 0 if _tabs.current_tab == 2 else 2
	elif event.is_action_pressed("inventory"):
		PlayerInputSettings.instance().release_all()
		_tabs.current_tab = 0 if _tabs.current_tab == 1 else 1
	elif _tabs.current_tab == 2 or Input.is_action_pressed("ui_cursor"):
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
