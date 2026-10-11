extends Node3D
class_name ProceduralProductionPreview

signal source_selected(deposit_id: String)
signal extraction_requested(deposit_id: String)
signal workstation_selected
signal wall_selected(wall_id: String)

## First-party display geometry. Logical construction does not modify atmosphere.
var _deposits: Dictionary = {}
var _walls: Array[MeshInstance3D] = []
var _spatial_walls: Dictionary = {}
var _label: WorldContextLabel
var _source_areas: Dictionary = {}
var _source_labels: Dictionary = {}
const SOURCE_NAMES: Dictionary = {"deposit.iron": "Iron ore", "deposit.ice": "Ice", "deposit.regolith": "Regolith"}


func set_labels_visible(enabled: bool) -> void:
	if _label != null: _label.visible = enabled
	for label in _source_labels.values(): label.visible = enabled


func _ready() -> void:
	var ids: Array[String] = ["deposit.iron", "deposit.ice", "deposit.regolith"]
	var colors: Array[Color] = [Color("#ad7357"), Color("#a6d2de"), Color("#a89778")]
	for index in range(ids.size()):
		var coords: Array = ProductionSimulationSystem.SOURCE_POSITIONS[ids[index]]
		var origin: Vector3 = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(coords[0]), float(coords[1]), float(coords[2])) / 1000.0
		var ore := _box(Vector3(0.5, 0.5, 0.5), origin + Vector3(0, 0.25, 0), colors[index])
		HabitatVisualDetails.resource(ore, index, colors[index])
		_deposits[ids[index]] = ore
		var area := Area3D.new()
		area.position = ore.position
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6, 0.6, 0.6)
		collision.shape = shape
		area.add_child(collision)
		area.input_event.connect(_on_source_input.bind(ids[index]))
		add_child(area)
		_source_areas[ids[index]] = area
		var source_label := WorldContextLabel.new()
		source_label.position = origin + Vector3(0, 0.25, 0)
		source_label.text = ["Iron ore", "Ice", "Regolith"][index] + "\nDouble-click to extract into a carried canister"
		add_child(source_label)
		_source_labels[ids[index]] = source_label
	_box(Vector3(3.5, 0.1, 1.0), Vector3(-6.0, 0.8, 3.0), Color("#667b91"))
	HabitatVisualDetails.workstation(self)
	var workstation := Area3D.new()
	workstation.position = Vector3(-6.0, 0.8, 3.0)
	var workstation_collision := CollisionShape3D.new()
	var workstation_shape := BoxShape3D.new()
	workstation_shape.size = Vector3(3.5, 0.3, 1.0)
	workstation_collision.shape = workstation_shape
	workstation.add_child(workstation_collision)
	workstation.input_event.connect(_on_workstation_input)
	add_child(workstation)
	for index in range(10):
		var wall := _box(Vector3(0.5, 1.5, 0.08), Vector3(-12.0 + float(index) * 0.55, 0.75, 3.5), Color("#b7c2c8"))
		wall.visible = false
		_walls.append(wall)
	_label = WorldContextLabel.new()
	_label.position = Vector3(-6.0, 0.8, 3.0)
	_label.text = "Production fixture — controls in inventory HUD"
	add_child(_label)


func observe(record: Dictionary) -> void:
	if _label == null:
		return
	if record.is_empty():
		_label.text = "Production unavailable"
		for mesh in _deposits.values():
			mesh.visible = false
		for area in _source_areas.values():
			area.input_ray_pickable = false
		for label in _source_labels.values():
			label.text = "Resource source unavailable"
		for wall in _walls:
			wall.visible = false
		_update_spatial_walls({})
		return
	for id in _deposits:
		var mass: int = int(record["deposits"][id])
		var mesh: MeshInstance3D = _deposits[id]
		mesh.visible = mass > 0
		_source_areas[id].input_ray_pickable = mass > 0
		_source_labels[id].text = "%s\n%.2f kg\n%s" % [SOURCE_NAMES[id] + " [" + id + "]", float(mass) / 1000000.0, "Double-click to extract into a carried canister" if mass > 0 else "Depleted"]
		var fraction: float = float(mass) / (5000000.0 if id == "deposit.ice" else 10000000.0)
		mesh.scale = Vector3.ONE * maxf(0.05, pow(fraction, 1.0 / 3.0))
	var count: int = int(record["wall_mass_milligrams"]) / 1000000
	for index in range(_walls.size()):
		_walls[index].visible = index < count
	_update_spatial_walls(record.get("walls", {}))
	_label.text = "Refinery and recycler\nClick the workbench for recipes\n%d J · %s" % [record["energy_joules"], "idle" if record["job"].is_empty() else "processing / power pause"]


## Colliders are views of server records, never construction state owners.
func _update_spatial_walls(walls: Dictionary) -> void:
	for id in _spatial_walls.keys():
		if walls.has(id): continue
		remove_child(_spatial_walls[id])
		_spatial_walls[id].queue_free()
		_spatial_walls.erase(id)
	for id in walls:
		if _spatial_walls.has(id): continue
		var pose: Dictionary = walls[id]
		var body := StaticBody3D.new()
		body.position = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + SpatialWallConstruction.center(pose) / 1000.0
		body.rotation.y = float(pose["quarter_turn"]) * PI / 2.0
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = SpatialWallConstruction.SIZE
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#b7c2c8")
		mesh.material_override = material
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = SpatialWallConstruction.SIZE
		collision.shape = shape
		body.add_child(collision)
		body.input_event.connect(func(_camera: Node, event: InputEvent, _point: Vector3, _normal: Vector3, _shape: int) -> void:
			if PlayerInputSettings.instance().accepts_gameplay_input() and event.is_action_pressed("world_select"): wall_selected.emit(id)
		)
		add_child(body)
		_spatial_walls[id] = body


func _on_workstation_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
	if PlayerInputSettings.instance().accepts_gameplay_input() and event.is_action_pressed("world_select"):
		workstation_selected.emit()


func _on_source_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int, deposit_id: String) -> void:
	if PlayerInputSettings.instance().accepts_gameplay_input() and event.is_action_pressed("world_select"):
		source_selected.emit(deposit_id)
		if not event is InputEventMouseButton or event.double_click:
			extraction_requested.emit(deposit_id)


func _box(size: Vector3, location: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = location
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	add_child(mesh)
	return mesh
