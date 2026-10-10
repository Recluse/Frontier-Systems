extends Node3D
class_name MachineryPreview

## Settled machinery uses one static compound body per physical frame. Its modules
## and canisters are child visuals, not independently simulated rigid bodies.
var _signature: String = ""


func observe(record: Dictionary) -> void:
	var workshop: Dictionary = record["machinery"]
	var poses: Dictionary = {}
	for id in workshop["placements"]: poses[id] = workshop["placements"][id]["position"]
	var signature: String = JSON.stringify([poses, workshop["mounts"], workshop["links"]], "", true)
	if signature == _signature: return
	_signature = signature
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for id in poses:
		var body := StaticBody3D.new()
		body.position = _position(poses[id]) + Vector3(0, 0.4, 0)
		add_child(body)
		_box(body, Vector3(0.7, 0.8, 0.6), Color(0.22, 0.29, 0.35), Vector3.ZERO)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.7, 0.8, 0.6)
		collision.shape = shape
		body.add_child(collision)
		var index: int = 0
		for module in workshop["mounts"]:
			if workshop["mounts"][module] != id: continue
			var kind: String = workshop["parts"][module]["kind"]
			_box(body, Vector3(0.12, 0.12, 0.08), Color(0.2, 0.7, 0.75) if kind == "socket" else Color(0.85, 0.6, 0.2), Vector3(-0.25 + float(index % 4) * 0.16, 0.3 - float(index / 4) * 0.16, -0.33))
			index += 1
		var title := Label3D.new()
		title.text = "Machine %s" % id.right(8)
		title.position.y = 0.65
		title.font_size = 36
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		body.add_child(title)
	for link in workshop["links"].values():
		if not poses.has(link["a"]) or not poses.has(link["b"]): continue
		var a: Vector3 = _position(poses[link["a"]]) + Vector3(0, 0.08, 0)
		var b: Vector3 = _position(poses[link["b"]]) + Vector3(0, 0.08, 0)
		var cable := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.015
		mesh.bottom_radius = 0.015
		mesh.height = maxf(0.01, a.distance_to(b))
		cable.mesh = mesh
		add_child(cable)
		cable.position = (a + b) / 2.0
		if a.distance_to(b) > 0.01: cable.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


static func _position(coords: Array) -> Vector3:
	return ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(coords[0]), float(coords[1]), float(coords[2])) / 1000.0


static func _box(parent: Node3D, size: Vector3, color: Color, offset: Vector3) -> void:
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	visual.position = offset
	parent.add_child(visual)
