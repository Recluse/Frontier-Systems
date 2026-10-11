extends SceneTree

var failures: int = 0
var requests: int = 0
var selections: int = 0
var viewport: SubViewport
var habitat: ProceduralHabitatPreview
var feedback: HabitatTargetFeedback


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func press(event: InputEvent) -> void:
	viewport.push_input(event, true)


func run() -> void:
	PlayerInputSettings.instance()._reset_map() # In memory only, no saved preferences.
	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	root.add_child(viewport)
	habitat = ProceduralHabitatPreview.new()
	viewport.add_child(habitat)
	feedback = habitat.get_child(habitat.get_child_count() - 1).get_child(0)
	var source: Area3D = habitat.production._source_areas["deposit.iron"]
	habitat.production.source_selected.connect(func(_id: String) -> void: selections += 1)
	habitat.production.extraction_requested.connect(func(_id: String) -> void: requests += 1)
	habitat.camera.position = source.global_position + Vector3(0, 0, 3)
	habitat.camera.look_at(source.global_position)
	habitat.camera.set_process(false)
	habitat.camera.set_physics_process(false)
	await physics_frame
	await physics_frame
	feedback._physics_process(0)
	var info: Dictionary = feedback.describe(source)
	check(info.get("name") == "deposit.iron" and feedback.hint(info).contains("double-click"), "source mouse hint names actual extraction request route")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	PlayerInputSettings._set_binding("world_select", key)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Dummy/headless rendering keeps the cursor visible; establish viewport aim.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(400, 300)
	press(motion)
	press(key)
	await physics_frame
	check(selections == 1 and requests == 1 and feedback.selected == source, "rebound keyboard input traverses real viewport ray and native source handler")
	check(feedback.hint(info).contains("select and request extraction") and not feedback.hint(info).contains("double-click"), "keyboard advice describes single-press request")
	key.echo = true
	press(key)
	check(requests == 1, "key echo cannot repeat action")
	key.echo = false
	PlayerInputSettings.instance().rebinding = true
	press(key)
	feedback._physics_process(0)
	check(requests == 1 and not feedback.visible, "rebinding suppresses route and feedback")
	PlayerInputSettings.instance().rebinding = false
	# GUI routing occurs after _input: focusing one control must not swallow
	# the default selection binding when it is used to activate another control.
	PlayerInputSettings.instance()._reset_map()
	var focused := LineEdit.new()
	viewport.add_child(focused)
	focused.grab_focus()
	var button := Button.new()
	button.position = Vector2(350, 250)
	button.size = Vector2(100, 100)
	button.text = "Close"
	viewport.add_child(button)
	var activations: Array[bool] = []
	button.pressed.connect(func() -> void: activations.append(true))
	var ui_click := InputEventMouseButton.new()
	ui_click.position = Vector2(400, 300)
	ui_click.button_index = MOUSE_BUTTON_LEFT
	ui_click.pressed = true
	press(ui_click)
	ui_click.pressed = false
	press(ui_click)
	await physics_frame
	check(activations.size() == 1 and button.has_focus() and requests == 1 and selections == 1, "focused UI permits another button's mouse activation without world interaction")
	button.free()
	focused.free()
	PlayerInputSettings._set_binding("world_select", key)
	var edit := LineEdit.new()
	root.add_child(edit)
	edit.grab_focus()
	press(key)
	check(requests == 1, "focused UI prevents gameplay route")
	edit.release_focus()
	edit.free()
	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_A
	joy.pressed = true
	PlayerInputSettings._set_binding("world_select", joy)
	press(joy)
	check(requests == 2 and selections == 2, "rebound controller event traverses native source handler")
	# Closest physical body must occlude the area, regardless of its pickability.
	var barrier := StaticBody3D.new()
	barrier.position = source.global_position + Vector3(0, 0, 1)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	barrier.add_child(shape)
	viewport.add_child(barrier)
	await physics_frame
	await physics_frame
	press(joy)
	feedback._physics_process(0)
	check(requests == 2 and feedback.hovered == null, "occluder blocks both keyboard/controller selection and hover")
	barrier.free()
	# Mouse handler semantics are deliberately tested through its actual signal.
	PlayerInputSettings.instance()._reset_map()
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	source.input_event.emit(habitat.camera, mouse, source.global_position, Vector3.UP, 0)
	check(selections == 3 and requests == 2, "mouse single click selects without extraction")
	mouse.double_click = true
	source.input_event.emit(habitat.camera, mouse, source.global_position, Vector3.UP, 0)
	check(requests == 3, "mouse double click requests extraction")
	var pickups: Array[String] = []
	habitat.world_inventory.pickup_requested.connect(func(_root: String, item: String) -> void: pickups.append(item))
	var storage: Dictionary = {"schema_version": 2, "inventory_revision": 0, "containers": [{"container_id": "world.tray-1", "distance_millimetres": 100, "position_millimetres": [0, 0, 0], "items": [{"item_id": "item.test", "definition_id": "item.crowbar.prototype", "definition_revision": 1, "condition_permille": 1000, "container_id": "world.tray-1"}]}]}
	check(habitat.world_inventory.observe(storage).is_success, "scoped item observation fixture validates")
	var item_area: Area3D
	for child in habitat.world_inventory._rendered.get_children():
		if child is Area3D: item_area = child
	feedback._register(item_area)
	mouse.double_click = false
	item_area.input_event.emit(habitat.camera, mouse, item_area.global_position, Vector3.UP, 0)
	check(pickups.is_empty() and feedback.selected == item_area and feedback.describe(item_area).get("name") == "item.test in world.tray-1", "item click gives stable identity without collection")
	mouse.double_click = true
	item_area.input_event.emit(habitat.camera, mouse, item_area.global_position, Vector3.UP, 0)
	check(pickups == ["item.test"] and feedback.hint(feedback.describe(item_area)).contains("request collection"), "item double click requests collection without promising success")
	habitat.world_inventory.observe({"schema_version": 2, "inventory_revision": 1, "containers": []})
	feedback._physics_process(0)
	check(feedback.selected == null and feedback.describe(item_area).is_empty(), "item removal clears advice immediately after detached rebuild")
	habitat.production._update_spatial_walls({"wall.test": {"position": [0, 0, 0], "quarter_turn": 0}})
	var wall: StaticBody3D = habitat.production._spatial_walls["wall.test"]
	feedback._register(wall)
	wall.input_event.emit(habitat.camera, mouse, wall.global_position, Vector3.UP, 0)
	check(feedback.selected == wall and feedback.describe(wall).get("action") == "Select to inspect", "wall native route offers read-only inspection")
	PlayerInputSettings._set_binding("world_select", joy)
	check(feedback.hint(feedback.describe(wall)).contains("requires a mouse"), "wall hint exposes current keyboard/controller route limitation")
	PlayerInputSettings.instance()._reset_map()
	for connection in wall.input_event.get_connections():
		if connection["callable"].get_object() == habitat.production: wall.input_event.disconnect(connection["callable"])
	feedback._physics_process(0)
	check(feedback.selected == null and feedback.describe(wall).is_empty(), "disconnected wall handler clears inspection feedback")
	habitat.production._update_spatial_walls({})
	feedback._physics_process(0)
	check(feedback.selected == null, "removed wall clears inspection feedback")
	for extent in [Vector2i(240, 180), Vector2i(800, 600)]:
		viewport.size = extent
		feedback._physics_process(0)
		check(Rect2(Vector2.ZERO, Vector2(extent)).encloses(Rect2(feedback._card.position, feedback._card.size)), "target advice remains bounded at narrow viewport size")
	viewport.size = Vector2i(100, 100)
	feedback._physics_process(0)
	check(not feedback.visible, "tiny viewport suppresses advice")
	source.input_ray_pickable = false
	feedback._physics_process(0)
	check(feedback.selected == null and feedback.describe(source).is_empty(), "unavailable target clears selection")
	source.input_ray_pickable = true
	feedback._register(source)
	feedback.selected = source
	for connection in source.input_event.get_connections():
		if connection["callable"].get_method() == "_on_source_input": source.input_event.disconnect(connection["callable"])
	feedback._physics_process(0)
	check(feedback.selected == null, "disconnected native action clears advice")
	var workstation: CollisionObject3D
	for child in habitat.production.get_children():
		if child is Area3D and not feedback.describe(child).is_empty(): workstation = child
	check(workstation != null and feedback.describe(workstation).get("action") == "Select recipes", "workstation advice offers selection only")
	feedback.selected = workstation
	habitat.world_inventory.observe(storage)
	for child in habitat.world_inventory._rendered.get_children():
		if child is Area3D: item_area = child
	habitat.production.observe({})
	feedback._physics_process(0)
	check(feedback.selected == null and feedback.describe(workstation).is_empty(), "unavailable production clears workstation feedback")
	feedback.selected = item_area
	feedback._physics_process(0)
	check(feedback.selected == null and feedback.describe(item_area).is_empty(), "client disconnect's unavailable preview also suppresses retained inventory proxies")
	feedback.selected = source
	source.queue_free()
	feedback._physics_process(0)
	check(feedback.selected == null, "queued deletion clears feedback before tree removal")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	PlayerInputSettings.instance()._reset_map()
	viewport.free()
	print("Habitat target feedback: %d failures" % failures)
	quit(1 if failures else 0)
