extends Node3D
class_name ProceduralProductionPreview

signal source_selected(deposit_id: String)
signal extraction_requested(deposit_id: String)
signal workstation_selected

## First-party display geometry. Logical construction does not modify atmosphere.
var _deposits: Dictionary = {}
var _walls: Array[MeshInstance3D] = []
var _label: Label3D
var _source_areas: Dictionary = {}
var _source_labels: Dictionary = {}
const SOURCE_NAMES: Dictionary = {"deposit.iron": "Iron ore", "deposit.ice": "Ice", "deposit.regolith": "Regolith"}


func _ready() -> void:
	var ids: Array[String] = ["deposit.iron", "deposit.ice", "deposit.regolith"]
	var colors: Array[Color] = [Color("#b36643"), Color("#9bd9ef"), Color("#967951")]
	for index in range(ids.size()):
		var coords: Array = ProductionSimulationSystem.SOURCE_POSITIONS[ids[index]]
		var origin: Vector3 = ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(coords[0]), float(coords[1]), float(coords[2])) / 1000.0
		var ore := _box(Vector3(0.5, 0.5, 0.5), origin + Vector3(0, 0.25, 0), colors[index])
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
		var source_label := Label3D.new()
		source_label.position = origin + Vector3(0, 0.9, 0)
		source_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		source_label.text = ["Iron ore", "Ice", "Regolith"][index] + "\nDouble-click to extract into a carried canister"
		source_label.font_size = 24
		add_child(source_label)
		_source_labels[ids[index]] = source_label
	_box(Vector3(3.5, 0.1, 1.0), Vector3(-6.0, 0.8, 3.0), Color("#667b91"))
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
	_label = Label3D.new()
	_label.position = Vector3(-6.0, 2.3, 3.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 28
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
		return
	for id in _deposits:
		var mass: int = int(record["deposits"][id])
		var mesh: MeshInstance3D = _deposits[id]
		mesh.visible = mass > 0
		_source_areas[id].input_ray_pickable = mass > 0
		_source_labels[id].text = "%s · %.2f kg\n%s" % [SOURCE_NAMES[id], float(mass) / 1000000.0, "Double-click to extract into a carried canister" if mass > 0 else "Depleted"]
		var fraction: float = float(mass) / (5000000.0 if id == "deposit.ice" else 10000000.0)
		mesh.scale = Vector3.ONE * maxf(0.05, pow(fraction, 1.0 / 3.0))
	var count: int = int(record["wall_mass_milligrams"]) / 1000000
	for index in range(_walls.size()):
		_walls[index].visible = index < count
	_label.text = "Refinery and recycler\nClick the workbench for recipes\n%d J · %s" % [record["energy_joules"], "idle" if record["job"].is_empty() else "processing / power pause"]


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
