extends Node3D
class_name ProceduralWorldInventoryPreview

## Native placeholder art derived from scoped storage observations, not physical items.
signal item_selected(container_id: String, item_id: String)
signal pickup_requested(container_id: String, item_id: String)
const MAX_VISIBLE_ITEMS_PER_CONTAINER: int = 8
const DISPLAY_ORIGIN := Vector3(-6.0, 0.0, 2.0)
var _record: Dictionary = {"schema_version": 2, "inventory_revision": 0, "containers": []}
var _rendered: Node3D
var _visible_items: Dictionary = {}
var _selected_key: String = ""
var _rebuilds: int = 0
var player_facing_labels: bool = false
var skip_machine_roots: bool = false
var labels_visible: bool = true


func observe(record: Dictionary) -> ServiceResult:
	var validated: ServiceResult = WorldStorageObservation.from_record(record)
	if not validated.is_success:
		return validated
	var next: Dictionary = validated.value.to_record()
	var changed: bool = JSON.stringify(next["containers"]) != JSON.stringify(_record["containers"])
	_record = next
	if changed:
		_rebuild()
	return ServiceResult.success()


func presentation_snapshot() -> Dictionary:
	return {"containers": _record["containers"].size(), "visible_items": _visible_items.size(), "selected_key": _selected_key, "rebuilds": _rebuilds}


func _rebuild() -> void:
	if _rendered != null:
		remove_child(_rendered)
		_rendered.queue_free()
	_rendered = Node3D.new()
	add_child(_rendered)
	_visible_items.clear()
	_rebuilds += 1
	for container in _record["containers"]:
		# The machinery adapter renders these physical roots as assemblies, not trays.
		if skip_machine_roots and String(container["container_id"]).begins_with("machine-root-"): continue
		var coords: Array = container["position_millimetres"]
		var origin: Vector3 = DISPLAY_ORIGIN + Vector3(float(coords[0]), float(coords[1]), float(coords[2])) / 1000.0
		_box(_rendered, Vector3(1.0, 0.08, 0.6), origin + Vector3(0, 0.7, 0), Color("#788a96"))
		var label := Label3D.new()
		label.position = origin + Vector3(0, 1.35, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 28
		label.text = "%s (logical fixture)\nClick to select; double-click to collect" % container["container_id"]
		if player_facing_labels:
			label.text = "Storage tray\nDouble-click an item to collect"
		if container["items"].size() > MAX_VISIBLE_ITEMS_PER_CONTAINER:
			label.text += "\n%d more items available in overlay" % (container["items"].size() - MAX_VISIBLE_ITEMS_PER_CONTAINER)
		_rendered.add_child(label)
		label.visible = labels_visible
		for index in range(mini(container["items"].size(), MAX_VISIBLE_ITEMS_PER_CONTAINER)):
			var item: Dictionary = container["items"][index]
			var dimensions := Vector3(0.15, 0.15, 0.15)
			var color := Color("#b4c7d4")
			if item["definition_id"] in ["item.crowbar.prototype", "item.crowbar.fabricated"]:
				dimensions = Vector3(0.4, 0.04, 0.04)
				color = Color("#bdc8d0")
			elif item["definition_id"] in ["item.backpack.prototype", "item.backpack.fabricated"]:
				dimensions = Vector3(0.25, 0.3, 0.2)
				color = Color("#6a986b")
			elif item["definition_id"] in ["item.pouch.prototype", "item.pouch.fabricated"]:
				dimensions = Vector3(0.18, 0.12, 0.12)
				color = Color("#bba064")
			elif item["definition_id"] in ["item.resource-canister.prototype", "item.resource-canister.fabricated"]:
				dimensions = Vector3(0.16, 0.3, 0.16)
				color = Color("#79b4c2")
			elif item["definition_id"] == "item.plate.prototype":
				dimensions = Vector3(0.4, 0.035, 0.3)
				color = Color("#b9c2ce")
			elif item["definition_id"] in ["item.extractor.prototype", "item.extractor.fabricated"]:
				dimensions = Vector3(0.32, 0.16, 0.12)
				color = Color("#dfa645")
			var location: Vector3 = origin + Vector3(-0.3 + float(index % 4) * 0.2, 0.75 + dimensions.y / 2.0, -0.15 + float(index / 4) * 0.3)
			var mesh: MeshInstance3D = _box(_rendered, dimensions, location, color)
			var key: String = JSON.stringify([container["container_id"], item["item_id"]])
			var identity := Label3D.new()
			identity.position = location + Vector3(0, 0.25, 0)
			identity.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			identity.font_size = 22
			identity.text = "%s\n%s · observed %.2f m" % [item["item_id"], container["container_id"], float(container["distance_millimetres"]) / 1000.0]
			_rendered.add_child(identity)
			_visible_items[key] = {"mesh": mesh, "color": color, "identity": identity, "text": identity.text}
			var area := Area3D.new()
			area.position = location
			area.collision_layer = 4
			area.collision_mask = 0
			area.input_ray_pickable = true
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = dimensions.max(Vector3(0.12, 0.12, 0.12))
			shape.shape = box
			area.add_child(shape)
			area.input_event.connect(_on_item_input.bind(container["container_id"], item["item_id"]))
			_rendered.add_child(area)
	if not _visible_items.has(_selected_key):
		_selected_key = ""
	_highlight()


func _on_item_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int, container_id: String, item_id: String) -> void:
	var key: String = JSON.stringify([container_id, item_id])
	if not _visible_items.has(key) or not PlayerInputSettings.instance().accepts_gameplay_input() or not event.is_action_pressed("world_select"):
		return
	_selected_key = key
	_highlight()
	item_selected.emit(container_id, item_id)
	if not event is InputEventMouseButton or event.double_click:
		pickup_requested.emit(container_id, item_id)


func _highlight() -> void:
	for key in _visible_items:
		var entry: Dictionary = _visible_items[key]
		var material: StandardMaterial3D = entry["mesh"].material_override
		material.albedo_color = Color("#ffe066") if key == _selected_key else entry["color"]
		entry["identity"].visible = labels_visible and key == _selected_key
		entry["identity"].text = entry["text"] if key == _selected_key else ""


func _box(parent: Node3D, dimensions: Vector3, location: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = location
	parent.add_child(instance)
	return instance
