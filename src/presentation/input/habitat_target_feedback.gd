extends Control
class_name HabitatTargetFeedback

## Disposable local targeting advice. Never queues commands or asserts reach.
var habitat: ProceduralHabitatPreview
var hovered: CollisionObject3D
var selected: CollisionObject3D
var _connections: Dictionary = {}
var _card: PanelContainer
var _lines: Array[Label] = []
var _markers: Array[Vector2] = []
var _marker_colors: Array[Color] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#18232f")
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(rows)
	for index in range(3):
		var line := Label.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_font_size_override("font_size", 16)
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.clip_text = true
		rows.add_child(line)
		_lines.append(line)
	visible = false


## Reads existing native routes, including their stable bound item/source IDs.
func describe(target: CollisionObject3D) -> Dictionary:
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion() or not target.input_ray_pickable:
		return {}
	var production: ProceduralProductionPreview = habitat.production
	# Existing client disconnect handling marks this preview unavailable even when
	# an older inventory proxy tree remains. Never present those proxies as targets.
	if production._label == null or production._label.text == "Production unavailable":
		return {}
	if target.get_parent() == production:
		for id in production._spatial_walls:
			if production._spatial_walls[id] == target:
				for connection in target.input_event.get_connections():
					if connection["callable"].get_object() == production:
						return {"name": "Wall " + id, "action": "Select to inspect", "mouse_only": true}
				return {}
	for connection in target.input_event.get_connections():
		var route: Callable = connection["callable"]
		var args: Array = route.get_bound_arguments()
		if route.get_object() == habitat.world_inventory and route.get_method() == "_on_item_input" and args.size() == 2:
			var key: String = JSON.stringify(args)
			if habitat.world_inventory._visible_items.has(key):
				return {"name": "%s in %s" % [args[1], args[0]], "action": "Request collection", "mouse_only": false}
		if route.get_object() == production and route.get_method() == "_on_source_input" and args.size() == 1:
			return {"name": String(args[0]), "action": "Request extraction", "mouse_only": false}
		if route.get_object() == production and route.get_method() == "_on_workstation_input":
			return {"name": "Workstation", "action": "Select recipes", "mouse_only": false}
	return {}


func hint(info: Dictionary) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events("world_select")
	if events.is_empty(): return "Selection unbound — open Controls"
	var binding: String = PlayerInputSettings.instance().binding_label("world_select")
	if info["mouse_only"] and not events[0] is InputEventMouseButton:
		return "Wall inspection currently requires a mouse selection binding"
	if info["action"] in ["Request collection", "Request extraction"]:
		return "%s: select · double-click: %s" % [binding, String(info["action"]).to_lower()] if events[0] is InputEventMouseButton else "%s: select and %s" % [binding, String(info["action"]).to_lower()]
	return "%s: %s" % [binding, String(info["action"]).to_lower()]


func _register(target: CollisionObject3D) -> void:
	var id: int = target.get_instance_id()
	if _connections.has(id) or describe(target).is_empty(): return
	var callback: Callable = _on_target_input.bind(weakref(target))
	target.input_event.connect(callback)
	_connections[id] = {"target": weakref(target), "callback": callback}


func _on_target_input(_camera: Node, event: InputEvent, _point: Vector3, _normal: Vector3, _shape: int, reference: WeakRef) -> void:
	var target := reference.get_ref() as CollisionObject3D
	if WorldSelectionInput.gameplay_allowed(get_viewport()) and event.is_action_pressed("world_select") and not event.is_echo() and not describe(target).is_empty():
		selected = target


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(habitat): return
	# Existing previews bound this scan to 256 item areas plus sources/workstation/walls.
	for owner in [habitat.production, habitat.world_inventory._rendered]:
		if not is_instance_valid(owner): continue
		for child in owner.get_children():
			if child is CollisionObject3D: _register(child)
	for id in _connections.keys():
		var entry: Dictionary = _connections[id]
		var target := entry["target"].get_ref() as CollisionObject3D
		if describe(target).is_empty():
			if is_instance_valid(target): target.input_event.disconnect(entry["callback"])
			_connections.erase(id)
	if describe(selected).is_empty(): selected = null
	hovered = null
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	var extent: Vector2 = viewport.get_visible_rect().size
	_markers.clear()
	_marker_colors.clear()
	visible = camera != null and extent.x >= 240 and extent.y >= 180 and WorldSelectionInput.gameplay_allowed(viewport)
	if not visible:
		queue_redraw()
		return
	var pointer: Vector2 = extent / 2.0 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else viewport.get_mouse_position()
	if Rect2(Vector2.ZERO, extent).has_point(pointer):
		var hit: Dictionary = WorldSelectionInput.ray_target(camera, pointer)
		var target := hit.get("collider") as CollisionObject3D
		if not describe(target).is_empty(): hovered = target
	var info: Dictionary = describe(hovered)
	var selection: Dictionary = describe(selected)
	_lines[0].text = "Target: " + String(info.get("name", "Aim at an item, source, workstation or wall"))
	_lines[1].text = hint(info) if not info.is_empty() else "World selection: " + PlayerInputSettings.instance().binding_label("world_select")
	_lines[2].text = "Selected: " + String(selection["name"]) if not selection.is_empty() else "Requests recheck reach, access and resources at the simulation tick"
	size = extent
	_card.size = Vector2(minf(540, extent.x - 24), 90)
	_card.position = Vector2(12, extent.y - _card.size.y - 12)
	for target in [hovered, selected]:
		if is_instance_valid(target) and not camera.is_position_behind(target.global_position):
			var point: Vector2 = camera.unproject_position(target.global_position)
			if Rect2(Vector2.ZERO, extent).has_point(point):
				_markers.append(point)
				_marker_colors.append(Color("#ffe066") if target == selected else Color("#6cdbed"))
	queue_redraw()


func _draw() -> void:
	for index in range(_markers.size()):
		draw_arc(_markers[index], 12, 0, TAU, 24, _marker_colors[index], 2, true)


func _exit_tree() -> void:
	for entry in _connections.values():
		var target := entry["target"].get_ref() as CollisionObject3D
		if is_instance_valid(target): target.input_event.disconnect(entry["callback"])
