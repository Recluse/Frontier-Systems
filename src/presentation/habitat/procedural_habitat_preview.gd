extends Node3D
class_name ProceduralHabitatPreview

## First-party cutaway geometry. Snapshots drive display only, never physical state.
var camera: HabitatInspectionCamera
var character: LocalHabitatCharacter
var world_inventory: ProceduralWorldInventoryPreview
var production: ProceduralProductionPreview
var _door_shapes: Dictionary = {}
var _doors: Dictionary = {}
var _targets: Dictionary = {"inner": 1.2, "outer": 1.2}
var _pressure_label: Label3D


func _ready() -> void:
	add_child(WorldSelectionInput.new())
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#141e2a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b9cbdc")
	environment.ambient_light_energy = 0.6
	var sky := WorldEnvironment.new()
	sky.environment = environment
	add_child(sky)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, -0.5, 0.0)
	light.light_energy = 1.2
	add_child(light)
	_box("Surface", Vector3(60.0, 0.1, 40.0), Vector3(-6.0, -0.3, 0.0), Color("#594840"))
	_box("HabitatFloor", Vector3(20.0, 0.2, 10.0), Vector3(-11.0, -0.1, 0.0), Color("#7e929f"))
	_box("ChamberFloor", Vector3(2.0, 0.2, 2.0), Vector3(0.0, -0.1, 0.0), Color("#c0a56b"))
	var wall_color := Color("#8095a7")
	_box("BackWall", Vector3(0.2, 2.5, 10.0), Vector3(-21.0, 1.25, 0.0), wall_color)
	for side in [-1.0, 1.0]:
		_box("HabitatWall", Vector3(20.0, 2.5, 0.2), Vector3(-11.0, 1.25, side * 5.0), wall_color)
		_box("DoorFrameWall", Vector3(0.2, 2.5, 4.0), Vector3(-1.0, 1.25, side * 3.0), wall_color)
		_box("ChamberWall", Vector3(2.0, 2.5, 0.12), Vector3(0.0, 1.25, side), Color("#96a8b1"))
	_doors["inner"] = _box("InnerDoor", Vector3(0.12, 2.4, 1.8), Vector3(-1.0, 1.2, 0.0), Color("#52a3ba"), false)
	_doors["outer"] = _box("OuterDoor", Vector3(0.12, 2.4, 1.8), Vector3(1.0, 1.2, 0.0), Color("#d69356"), false)
	_door_shapes["inner"] = _collider(self, "InnerBarrier", Vector3(0.12, 2.4, 1.8), Vector3(-1.0, 1.2, 0.0))
	_door_shapes["outer"] = _collider(self, "OuterBarrier", Vector3(0.12, 2.4, 1.8), Vector3(1.0, 1.2, 0.0))
	_pressure_label = Label3D.new()
	_pressure_label.position = Vector3(-6.0, 3.0, 0.0)
	_pressure_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pressure_label.font_size = 40
	_pressure_label.text = "Habitat pressure preview"
	add_child(_pressure_label)
	world_inventory = ProceduralWorldInventoryPreview.new()
	add_child(world_inventory)
	production = ProceduralProductionPreview.new()
	add_child(production)
	camera = HabitatInspectionCamera.new()
	add_child(camera)
	character = LocalHabitatCharacter.new()
	character.position = Vector3(-4.0, 0.95, 0.0)
	character.rotation.y = -PI / 2.0
	add_child(character)
	camera.make_current()


func focus_production() -> void:
	if _pressure_label != null:
		_pressure_label.visible = false


func observe_snapshot(snapshot: Dictionary) -> ServiceResult:
	if typeof(snapshot.get("inner_door_open")) != TYPE_BOOL or typeof(snapshot.get("outer_door_open")) != TYPE_BOOL:
		return ServiceResult.failure(&"invalid_habitat_preview_snapshot", "Door observations must be booleans.")
	var sensors: Variant = snapshot.get("pressure_sensors")
	if typeof(sensors) != TYPE_DICTIONARY:
		return ServiceResult.failure(&"invalid_habitat_preview_pressure", "Pressure sensor observations are required.")
	var readings: Array[float] = []
	for name in ["habitat", "chamber", "exterior"]:
		var sensor: Variant = sensors.get(name)
		if typeof(sensor) != TYPE_DICTIONARY:
			return ServiceResult.failure(&"invalid_habitat_preview_pressure", "A required pressure sensor is missing.")
		var pressure: Variant = sensor.get("pressure_kpa_absolute")
		if (typeof(pressure) != TYPE_INT and typeof(pressure) != TYPE_FLOAT) or not is_finite(float(pressure)) or float(pressure) < 0.0:
			return ServiceResult.failure(&"invalid_habitat_preview_pressure", "Pressure readings must be finite non-negative numbers.")
		readings.append(float(pressure))
	_targets["inner"] = 3.7 if snapshot["inner_door_open"] else 1.2
	_targets["outer"] = 3.7 if snapshot["outer_door_open"] else 1.2
	for id in ["inner", "outer"]:
		var shape := _door_shapes.get(id) as CollisionShape3D
		if shape != null:
			shape.set_deferred("disabled", snapshot[id + "_door_open"])
	if _pressure_label != null:
		_pressure_label.text = "Habitat %.1f kPa | Chamber %.1f kPa | Exterior %.2f kPa" % readings
	return ServiceResult.success()


func presentation_snapshot() -> Dictionary:
	return {"inner_target_height": _targets["inner"], "outer_target_height": _targets["outer"], "camera_mode": int(camera.mode) if camera != null else -1}


func _process(delta: float) -> void:
	for id in _doors:
		var door := _doors[id] as MeshInstance3D
		door.position.y = move_toward(door.position.y, float(_targets[id]), clampf(delta, 0.0, 0.1) * 5.0)


func activate_inspection(view_mode: int) -> void:
	character.set_navigation_enabled(false)
	camera.set_mode(view_mode)
	camera.make_current()


func activate_character(view_mode: int) -> void:
	camera._release_mouse()
	character.set_camera_mode(view_mode)
	character.set_navigation_enabled(true)


func _box(node_name: String, dimensions: Vector3, location: Vector3, color: Color, collidable: bool = true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = location
	add_child(instance)
	if collidable:
		_collider(instance, "Barrier", dimensions, Vector3.ZERO)
	return instance


func _collider(parent: Node3D, node_name: String, dimensions: Vector3, location: Vector3) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = location
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	return collider
